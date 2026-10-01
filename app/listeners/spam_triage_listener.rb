class SpamTriageListener < BaseListener
  # Triage once per conversation, on the first message when it came from the contact
  def message_created(event)
    message = extract_message_and_account(event)[0]
    gate = Conversations::SpamTriageGate.new(conversation: message.conversation)

    if gate.triage?(message)
      Conversations::SpamTriageJob.perform_later(message)
    elsif gate.held? && !message.private? && gate.first_public_message?(message) && !gate.awaiting_verdict?
      # The thread turned out not to need triage (agent-started, auto-reply, ...), so anything held while that was
      # unknown can go out now rather than at the fallback deadline
      Conversations::SpamTriageReleaseJob.perform_later(message.conversation)
    end
  end
end
