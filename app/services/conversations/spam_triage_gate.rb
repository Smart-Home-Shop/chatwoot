# Decides when spam triage runs for a conversation, and when its auto-replies (out-of-office, greeting) and agent
# notifications must wait for, or be skipped because of, the triage verdict.
class Conversations::SpamTriageGate
  # A verdict normally lands within seconds; after this, hold nothing so a stuck triage can't silence a conversation
  AWAIT_WINDOW = 10.minutes

  pattr_initialize [:conversation!]

  # The first public message of a contact-started thread gets triaged
  def triage?(message)
    triage_enabled? && message.incoming? && !message.private? && !message.auto_reply_email? &&
      eligible_conversation? && first_public_message == message
  end

  def hold?
    awaiting_verdict? || suspected_spam?
  end

  private

  def awaiting_verdict?
    return false unless triage_enabled? && eligible_conversation?
    return false if conversation.additional_attributes&.key?('spam_triage')
    return false if conversation.created_at < AWAIT_WINDOW.ago

    started_by_contact?
  end

  def started_by_contact?
    first = first_public_message
    first.present? && first.incoming? && !first.auto_reply_email?
  end

  # Label-based so an agent removing a false positive restores normal behaviour
  def suspected_spam?
    conversation.label_list.include?(Conversations::SpamTriageJob::LABELS['spam'][:title])
  end

  def triage_enabled?
    account = conversation.account
    # Captain::BaseTaskService refuses to run without captain_tasks
    account.spam_triage && account.feature_enabled?('captain_tasks')
  end

  def eligible_conversation?
    conversation.campaign_id.blank? && !conversation.contact.blocked?
  end

  def first_public_message
    conversation.messages.where(message_type: [:incoming, :outgoing], private: false).order(:id).first
  end
end
