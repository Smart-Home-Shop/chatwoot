class SpamTriageListener < BaseListener
  # Triage once per conversation, on the first message when it came from the contact
  def message_created(event)
    message = extract_message_and_account(event)[0]
    gate = Conversations::SpamTriageGate.new(conversation: message.conversation)

    if gate.triage?(message)
      Conversations::SpamTriageJob.perform_later(message)
    elsif message.outgoing? && !message.private? && gate.first_public_message?(message)
      # An agent started this thread, so anything held while that was unknown can go out now
      Conversations::SpamTriageReleaseJob.perform_later(message.conversation)
    end
  end
end
