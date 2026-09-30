class Conversations::SpamTriageJob < ApplicationJob
  queue_as :low

  LABEL = 'suspected-spam'.freeze
  LABEL_COLOR = '#DC2626'.freeze
  CONFIDENCE_THRESHOLD = 0.7

  def perform(message)
    conversation = message.conversation
    return if triaged?(conversation)

    result = Captain::SpamTriageService.new(account: message.account, message: message).perform
    raise "Spam triage failed for conversation #{conversation.id}: #{result[:error]}" if result[:error]

    # Flagging and the verdict marker commit together, so a failed retry never leaves a verdict without its label and note
    conversation.with_lock do
      next if triaged?(conversation)

      flag_as_suspected_spam(conversation, result) if result[:verdict] == 'spam' && result[:confidence] >= CONFIDENCE_THRESHOLD
      store_verdict(conversation, result)
    end
  end

  private

  def triaged?(conversation)
    conversation.additional_attributes&.key?('spam_triage')
  end

  # Stored for every verdict so agent decisions can later be compared against it
  def store_verdict(conversation, result)
    verdict = result.slice(:verdict, :confidence, :reason).merge(triaged_at: Time.current.iso8601).stringify_keys
    conversation.update!(additional_attributes: (conversation.additional_attributes || {}).merge('spam_triage' => verdict))
  end

  def flag_as_suspected_spam(conversation, result)
    conversation.account.labels.find_or_create_by!(title: LABEL) { |label| label.color = LABEL_COLOR }
    conversation.add_labels([LABEL])

    note = I18n.t('conversations.spam_triage.note', confidence: (result[:confidence] * 100).round, reason: result[:reason])
    Messages::MessageBuilder.new(nil, conversation, { content: note, private: true }).perform
  end
end
