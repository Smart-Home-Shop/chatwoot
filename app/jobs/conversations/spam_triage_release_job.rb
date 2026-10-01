# Replays the auto-replies and agent notifications Conversations::SpamTriageGate held while triage decided.
# Each entry is removed only after it ran, so a failed release retries the rest without losing or repeating any.
class Conversations::SpamTriageReleaseJob < ApplicationJob
  queue_as :low

  def perform(conversation)
    gate = Conversations::SpamTriageGate.new(conversation: conversation)
    # Still deciding: the triage job enqueues the release once it has a verdict
    return if !gate.suspected_spam? && gate.awaiting_verdict?

    done = gate.suspected_spam? ? gate.discard_held : gate.drain_held { |entry| replay(conversation, entry) }
    # Another release or a recording holds the lock; come back once it's done
    self.class.set(wait: 5.seconds).perform_later(conversation) unless done
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
    when 'slack'
      replay_slack(conversation, entry)
    end
  end

  # A retry after a crash between sending and removing the entry must not alert the same agent twice. These alerts are
  # one per agent per conversation; templates and new-message alerts already guard themselves.
  def replay_alert(conversation, entry)
    type = entry['type'] == 'assignment' ? 'conversation_assignment' : 'conversation_creation'
    return if Notification.exists?(user_id: entry['user_id'], primary_actor: conversation, notification_type: type)

    if entry['type'] == 'assignment'
      # Only the assignment that was actually held, and only if it still stands (reloaded: it may have just changed)
      NotificationListener.instance.notify_assignee(conversation) if conversation.reload.assignee_id == entry['user_id']
    else
      agent = conversation.inbox.members.find_by(id: entry['user_id'])
      NotificationListener.instance.notify_conversation_creation(conversation, agent) if agent
    end
  end

  # Inline and in order, so the conversation header is posted with the first held message and the thread keeps its order.
  # Already-posted messages are skipped by the Slack service (external_source_id_slack), so a retry can't post twice.
  def replay_slack(conversation, entry)
    hook = conversation.account.hooks.find_by(id: entry['hook_id'])
    return if hook.blank? || hook.disabled?

    replay_for_message(conversation, entry) { |message| ::SendOnSlackJob.perform_now(message, hook) }
  end

  def replay_for_message(conversation, entry)
    message = conversation.messages.find_by(id: entry['message_id'])
    yield message if message
  end
end
