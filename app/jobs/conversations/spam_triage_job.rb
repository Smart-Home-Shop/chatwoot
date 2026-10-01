class Conversations::SpamTriageJob < ApplicationJob
  queue_as :low

  LABELS = {
    'spam' => { title: 'suspected-spam', color: '#DC2626' },
    'notification' => { title: 'notification', color: '#6B7280' }
  }.freeze
  CONFIDENCE_THRESHOLD = 0.7
  # Longer than an LLM call can take; it only expires early if a worker dies mid-triage
  RUN_LOCK_TIMEOUT = 5.minutes

  def perform(message)
    conversation = message.conversation
    return if triaged?(conversation)

    # One triage per conversation at a time, so a duplicate delivery doesn't pay for a second LLM call. The run that
    # holds the lock records the verdict and releases what was held (and Sidekiq retries it if it fails).
    token = SecureRandom.uuid
    lock_key = format(::Redis::RedisKeys::SPAM_TRIAGE_RUN_LOCK, conversation_id: conversation.id)
    return unless Redis::Alfred.set(lock_key, token, nx: true, ex: RUN_LOCK_TIMEOUT)

    begin
      triage(message, conversation)
    ensure
      Redis::Alfred.delete_if_equals(lock_key, token)
    end
  end

  private

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
