class SpamTriageListener < BaseListener
  # Triage once per conversation, on the first message when it came from the contact
  def message_created(event)
    message = extract_message_and_account(event)[0]
    return unless Conversations::SpamTriageGate.new(conversation: message.conversation).triage?(message)

    Conversations::SpamTriageJob.perform_later(message)
  end
end
