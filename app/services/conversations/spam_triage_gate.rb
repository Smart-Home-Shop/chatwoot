# Decides when spam triage runs for a conversation, and holds its auto-replies (out-of-office, greeting) and agent
# notifications until the verdict is known. Each held side effect is recorded where it would have run, so
# Conversations::SpamTriageReleaseJob replays exactly those, once, after the verdict (or the await window) passes.
class Conversations::SpamTriageGate
  # A verdict normally lands within seconds; after this, holding stops and anything held is released (fail open)
  AWAIT_WINDOW = 10.minutes
  HELD_TTL = 1.day
  # Recording and draining share one per-conversation lock so neither can miss or repeat the other's entries
  LOCK_TIMEOUT = 30.seconds
  LOCK_WAIT = 3.seconds

  pattr_initialize [:conversation!]

  # The first public message of a contact-started thread gets triaged
  def triage?(message)
    triage_enabled? && message.incoming? && !message.private? && !message.auto_reply_email? &&
      eligible_conversation? && first_public_message?(message)
  end

  def first_public_message?(message)
    first_public_message == message
  end

  # True when the caller must not run its side effect now: suspected spam drops it, a pending verdict records it
  def hold(entry)
    return true if suspected_spam?
    return false unless awaiting_verdict?

    # Re-check under the lock: a verdict may have landed and its release drained the list meanwhile.
    # If the lock can't be had, fail open and let the side effect run now.
    !!with_lock(wait: LOCK_WAIT) do
      conversation.reload
      # A spam verdict that landed meanwhile drops the side effect rather than releasing it
      next true if suspected_spam?
      next false unless awaiting_verdict?

      record(entry)
      true
    end
  end

  # Yields each held entry oldest first, removing it once handled; false if another drain holds the lock
  def drain_held
    with_lock do
      held_entries.each do |raw, entry|
        yield entry
        remove_held(raw)
      end
      true
    end
  end

  def awaiting_verdict?
    return false unless triage_enabled? && eligible_conversation?
    return false if conversation.additional_attributes&.key?('spam_triage')
    return false if conversation.created_at < AWAIT_WINDOW.ago

    contact_started_or_unknown?
  end

  # Label-based so an agent removing a false positive restores normal behaviour
  def suspected_spam?
    conversation.label_list.include?(Conversations::SpamTriageJob::LABELS['spam'][:title])
  end

  def held?
    Redis::Alfred.llen(held_key).positive?
  end

  # Oldest first, as [raw, parsed] pairs so each can be removed once replayed
  def held_entries
    Redis::Alfred.lrange(held_key).reverse.map { |raw| [raw, JSON.parse(raw)] }
  end

  def remove_held(raw)
    Redis::Alfred.lrem(held_key, raw, 1)
  end

  # Under the shared lock so an entry being recorded right now can't survive the discard; false if the lock is busy
  def discard_held
    with_lock do
      Redis::Alfred.delete(held_key)
      true
    end
  end

  private

  # No message yet: some channels commit the conversation before its first message, so wait to see who started it
  def contact_started_or_unknown?
    first = first_public_message
    first.nil? || (first.incoming? && !first.auto_reply_email?)
  end

  def record(entry)
    raw = entry.to_json
    return if Redis::Alfred.lrange(held_key).include?(raw)

    first_hold = Redis::Alfred.llen(held_key).zero?
    Redis::Alfred.lpush(held_key, raw)
    Redis::Alfred.expire(held_key, HELD_TTL)
    # Fallback at the hold deadline in case triage never decides; it does nothing if the verdict already released all
    deadline = conversation.created_at + AWAIT_WINDOW
    Conversations::SpamTriageReleaseJob.set(wait_until: deadline).perform_later(conversation) if first_hold
  end

  # Owner-token lock: only the holder can release it, so an expired lease can't delete a later owner's lock.
  # Draining is a handful of quick writes, well inside LOCK_TIMEOUT.
  def with_lock(wait: 0)
    token = SecureRandom.uuid
    give_up_at = Time.current + wait
    until Redis::Alfred.set(lock_key, token, nx: true, ex: LOCK_TIMEOUT)
      return false if Time.current >= give_up_at

      sleep 0.05
    end

    begin
      yield
    ensure
      Redis::Alfred.delete_if_equals(lock_key, token)
    end
  end

  def lock_key
    format(::Redis::RedisKeys::SPAM_TRIAGE_HELD_LOCK, conversation_id: conversation.id)
  end

  def held_key
    format(::Redis::RedisKeys::SPAM_TRIAGE_HELD, conversation_id: conversation.id)
  end

  def triage_enabled?
    account = conversation.account
    # Captain::BaseTaskService refuses to run without captain_tasks
    account.spam_triage && account.feature_enabled?('captain_tasks')
  end

  def eligible_conversation?
    conversation.campaign_id.blank? && !conversation.contact.blocked?
  end

  def first_public_message
    conversation.messages.where(message_type: [:incoming, :outgoing], private: false).order(:id).first
  end
end
