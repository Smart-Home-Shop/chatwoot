# Replays the auto-replies and agent notifications Conversations::SpamTriageGate held while triage decided.
# Each entry is removed only after it ran, so a failed release retries the rest without losing or repeating any.
class Conversations::SpamTriageReleaseJob < ApplicationJob
  queue_as :low

  def perform(conversation)
    gate = Conversations::SpamTriageGate.new(conversation: conversation)
    return gate.discard_held if gate.suspected_spam?
    # Still deciding: the triage job enqueues the release once it has a verdict
    return if gate.awaiting_verdict?

    gate.held_entries.each do |raw, entry|
      replay(conversation, entry)
      gate.remove_held(raw)
    end
  end

  private

  def replay(conversation, entry)
    case entry['type']
    when 'templates'
      replay_for_message(conversation, entry) { |message| ::MessageTemplates::HookExecutionService.new(message: message).perform }
    when 'new_message'
      replay_for_message(conversation, entry) { |message| Messages::NewMessageNotificationService.new(message: message).perform }
    when 'conversation_creation'
      NotificationListener.instance.notify_conversation_creation(conversation)
    when 'assignment'
      # Only the assignment that was actually held, and only if it still stands
      NotificationListener.instance.notify_assignee(conversation) if conversation.assignee_id == entry['user_id']
    end
  end

  def replay_for_message(conversation, entry)
    message = conversation.messages.find_by(id: entry['message_id'])
    yield message if message
  end
end
