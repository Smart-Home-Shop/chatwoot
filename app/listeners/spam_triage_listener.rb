class SpamTriageListener < BaseListener
  # Triage once per conversation, on the first message when it came from the contact
  def message_created(event)
    message, account = extract_message_and_account(event)
    return unless account.spam_triage && new_thread_from_contact?(message)

    Conversations::SpamTriageJob.perform_later(message)
  end

  private

  def new_thread_from_contact?(message)
    return false unless message.incoming? && !message.private? && !message.auto_reply_email?

    conversation = message.conversation
    return false if conversation.campaign_id.present? || conversation.contact.blocked?

    !conversation.messages.where(message_type: [:incoming, :outgoing]).exists?(id: ...message.id)
  end
end
