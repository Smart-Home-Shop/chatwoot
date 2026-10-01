class NotificationListener < BaseListener
  def conversation_bot_handoff(event)
    conversation = extract_conversation_and_account(event)[0]
    return if conversation.pending?

    notify_inbox_members(conversation)
  end

  def conversation_created(event)
    conversation = extract_conversation_and_account(event)[0]
    return if conversation.pending?

    notify_inbox_members(conversation)
  end

  def assignee_changed(event)
    conversation = extract_conversation_and_account(event)[0]
    assignee = conversation.assignee

    # NOTE:  The issue was that when a team change results in an assignee being set to nil,
    # the system was still trying to create a notification about the assignment change,
    # but there was no assignee to notify, causing potential issues in the notification system.
    # We need to debug this properly, but for now no need to pollute the jobs
    return if assignee.blank?
    return if event.data[:notifiable_assignee_change].blank?
    return if conversation.pending?
    return if spam_triage_hold(conversation, type: 'assignment', user_id: assignee.id)

    notify_assignee(conversation)
  end

  def message_created(event)
    message = extract_message_and_account(event)[0]

    Messages::MentionService.new(message: message).perform
    notify_new_message(message)
  end

  # Public so Conversations::SpamTriageReleaseJob can replay alerts held during spam triage
  def notify_conversation_creation(conversation, agent)
    NotificationBuilder.new(
      notification_type: 'conversation_creation',
      user: agent,
      account: conversation.account,
      primary_actor: conversation
    ).perform
  end

  def notify_assignee(conversation)
    NotificationBuilder.new(
      notification_type: 'conversation_assignment',
      user: conversation.assignee,
      account: conversation.account,
      primary_actor: conversation
    ).perform
  end

  private

  # Held per agent while spam triage decides, so a partly failed release only resends to the agents it missed
  def notify_inbox_members(conversation)
    conversation.inbox.members.each do |agent|
      next if spam_triage_hold(conversation, type: 'conversation_creation', user_id: agent.id)

      notify_conversation_creation(conversation, agent)
    end
  end

  # Only notifiable messages are worth holding; the service itself skips the rest
  def notify_new_message(message)
    return if message.notifiable? && spam_triage_hold(message.conversation, type: 'new_message', message_id: message.id)

    Messages::NewMessageNotificationService.new(message: message).perform
  end

  def spam_triage_hold(conversation, entry)
    Conversations::SpamTriageGate.new(conversation: conversation).hold(entry)
  end
end
