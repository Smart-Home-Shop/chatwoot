class Conversations::SpamTriageJob < ApplicationJob
  queue_as :low

  LABELS = {
    'spam' => { title: 'suspected-spam', color: '#DC2626' },
    'notification' => { title: 'notification', color: '#6B7280' }
  }.freeze
  CONFIDENCE_THRESHOLD = 0.7

  def perform(message)
    conversation = message.conversation
    return if triaged?(conversation)

    # One triage per conversation at a time, so a duplicate delivery doesn't pay for a second LLM call. The run that
    # holds the lock records the verdict and releases what was held. An LLM error is recorded as an 'error' verdict
    # (fail open) and not re-triaged; only a run that dies before recording anything is picked up again.
    token = SecureRandom.uuid
    lock_key = format(::Redis::RedisKeys::SPAM_TRIAGE_RUN_LOCK, conversation_id: conversation.id)
    # Busy: come back once the lease has run out, in case its holder died; the triaged? guard makes this cheap otherwise
    return retry_after_lease(message, lock_key) unless Redis::Alfred.set(lock_key, token, nx: true, ex: run_lock_timeout)

    begin
      # Another run may have recorded the verdict between our check and taking the lock
      triage(message, conversation) unless triaged?(conversation.reload)
    ensure
      Redis::Alfred.delete_if_equals(lock_key, token)
    end
  end

  private

  # Outlasts the longest possible LLM call (every RubyLLM retry hitting its request timeout), so the lease can only
  # expire under a run that has died
  def run_lock_timeout
    ((RubyLLM.config.max_retries + 1) * RubyLLM.config.request_timeout) + 60
  end

  def retry_after_lease(message, lock_key)
    remaining = Redis::Alfred.ttl(lock_key)
    self.class.set(wait: [remaining, 0].max + 1).perform_later(message)
  end

  def triage(message, conversation)
    result = Captain::SpamTriageService.new(account: message.account, message: message).perform
    # A failed triage still records a verdict so held auto-replies and alerts go out (fail open); the error is raised below
    result = { verdict: 'error', confidence: 0.0, reason: result[:error] } if result[:error]

    # Flagging and the verdict marker commit together, so a failed retry never leaves a verdict without its label and note
    decided = conversation.with_lock do
      next false if triaged?(conversation)

      apply_label(conversation, result) if result[:confidence] >= CONFIDENCE_THRESHOLD
      store_verdict(conversation, result)
      true
    end

    # Release (or, for suspected spam, discard) what was held while deciding, in its own retryable job
    Conversations::SpamTriageReleaseJob.perform_later(conversation) if decided
    raise "Spam triage failed for conversation #{conversation.id}: #{result[:reason]}" if result[:verdict] == 'error'
  end

  def triaged?(conversation)
    conversation.additional_attributes&.key?('spam_triage')
  end

  # Stored for every verdict so agent decisions can later be compared against it
  def store_verdict(conversation, result)
    verdict = result.slice(:verdict, :confidence, :reason).merge(triaged_at: Time.current.iso8601).stringify_keys
    conversation.update!(additional_attributes: (conversation.additional_attributes || {}).merge('spam_triage' => verdict))
  end

  def apply_label(conversation, result)
    label = LABELS[result[:verdict]]
    return unless label

    conversation.account.labels.find_or_create_by!(title: label[:title]) do |record|
      record.color = label[:color]
      record.show_on_sidebar = true
    end
    conversation.add_labels([label[:title]])
    return unless result[:verdict] == 'spam'

    note = I18n.t('conversations.spam_triage.note', confidence: (result[:confidence] * 100).round, reason: result[:reason])
    Messages::MessageBuilder.new(nil, conversation, { content: note, private: true }).perform
  end
end
