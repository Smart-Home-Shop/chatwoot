class Conversations::SpamTriageJob < ApplicationJob
  queue_as :low

  LABEL = 'suspected-spam'.freeze
  LABEL_COLOR = '#DC2626'.freeze
  CONFIDENCE_THRESHOLD = 0.7

  def perform(message)
    conversation = message.conversation
    return if conversation.additional_attributes&.key?('spam_triage')

    result = Captain::SpamTriageService.new(account: message.account, message: message).perform
    raise "Spam triage failed for conversation #{conversation.id}: #{result[:error]}" if result[:error]

    # Stored for every verdict so agent decisions can later be compared against it
    conversation.update!(additional_attributes: (conversation.additional_attributes || {}).merge(
      'spam_triage' => result.merge(triaged_at: Time.current.iso8601).stringify_keys
    ))
    flag_as_suspected_spam(conversation, result) if result[:verdict] == 'spam' && result[:confidence] >= CONFIDENCE_THRESHOLD
  end

  private

  def flag_as_suspected_spam(conversation, result)
    conversation.account.labels.find_or_create_by!(title: LABEL) { |label| label.color = LABEL_COLOR }
    conversation.add_labels([LABEL])

    note = I18n.t('conversations.spam_triage.note', confidence: (result[:confidence] * 100).round, reason: result[:reason])
    Messages::MessageBuilder.new(nil, conversation, { content: note, private: true }).perform
  end
end
