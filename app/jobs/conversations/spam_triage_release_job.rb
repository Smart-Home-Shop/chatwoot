# Replays the auto-replies and agent notifications Conversations::SpamTriageGate held while triage decided.
# Each entry is removed only after it ran, so a failed release retries the rest without losing or repeating any.
class Conversations::SpamTriageReleaseJob < ApplicationJob
  queue_as :low

  def perform(conversation)
    gate = Conversations::SpamTriageGate.new(conversation: conversation)
    return gate.discard_held if gate.suspected_spam?
    # Still deciding: the triage job enqueues the release once it has a verdict
    return if gate.awaiting_verdict?

    drained = gate.drain_held { |entry| replay(conversation, entry) }
    # Another release or a recording holds the lock; come back once it's done
    self.class.set(wait: 5.seconds).perform_later(conversation) unless drained
  end

  private

  def replay(conversation, entry)
    case entry['type']
    when 'templates'
      replay_for_message(conversation, entry) { |message| ::MessageTemplates::HookExecutionService.new(message: message).perform }
    when 'new_message'
      replay_for_message(conversation, entry) { |message| Messages::NewMessageNotificationService.new(message: message).perform }
    when 'conversation_creation', 'assignment'
      replay_alert(conversation, entry)
    end
  end

  # A retry after a crash between sending and removing the entry must not alert the same agent twice. These alerts are
  # one per agent per conversation; templates and new-message alerts already guard themselves.
  def replay_alert(conversation, entry)
    type = entry['type'] == 'assignment' ? 'conversation_assignment' : 'conversation_creation'
    return if Notification.exists?(user_id: entry['user_id'], primary_actor: conversation, notification_type: type)

    if entry['type'] == 'assignment'
      # Only the assignment that was actually held, and only if it still stands
      NotificationListener.instance.notify_assignee(conversation) if conversation.assignee_id == entry['user_id']
    else
      agent = conversation.inbox.members.find_by(id: entry['user_id'])
      NotificationListener.instance.notify_conversation_creation(conversation, agent) if agent
    end
  end

  def replay_for_message(conversation, entry)
    message = conversation.messages.find_by(id: entry['message_id'])
    yield message if message
  end
end
