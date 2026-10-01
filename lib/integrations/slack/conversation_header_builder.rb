# Builds the one channel message that represents a conversation in Slack: a compact, consistently sized summary
# (inbox, subject, AI summary, status, assignee, open button). The conversation's messages go in its thread, and this
# message is re-written in place when the status or assignee changes.
class Integrations::Slack::ConversationHeaderBuilder
  STATUS_EMOJI = {
    'open' => ':large_green_circle:',
    'pending' => ':large_yellow_circle:',
    'snoozed' => ':zzz:',
    'resolved' => ':white_check_mark:'
  }.freeze
  CHANNEL_EMOJI = {
    'Channel::Email' => ':email:',
    'Channel::Whatsapp' => ':iphone:',
    'Channel::Sms' => ':iphone:',
    'Channel::TwilioSms' => ':iphone:',
    'Channel::Telegram' => ':airplane:',
    'Channel::FacebookPage' => ':speech_balloon:',
    'Channel::Instagram' => ':camera:'
  }.freeze
  DEFAULT_CHANNEL_EMOJI = ':speech_balloon:'.freeze
  # A fallback summary (no AI summary available) is the first message, cut to one tidy line
  FALLBACK_SUMMARY_LENGTH = 150
  # Keep the header compact whatever the subject or model returns; Slack rejects section text over 3,000 characters
  SUBJECT_LENGTH = 200
  AI_SUMMARY_LENGTH = 250
  SECTION_TEXT_LIMIT = 3000
  NOTIFICATION_LABEL = Conversations::SpamTriageJob::LABELS['notification'][:title]

  pattr_initialize [:conversation!]

  def payload
    { text: fallback_text, blocks: blocks }
  end

  private

  delegate :inbox, :contact, to: :conversation

  def blocks
    [
      { type: 'section', text: { type: 'mrkdwn', text: headline }, accessory: open_button },
      { type: 'context', elements: [{ type: 'mrkdwn', text: meta_line }] }
    ]
  end

  def headline
    lines = ["#{CHANNEL_EMOJI.fetch(inbox.channel_type, DEFAULT_CHANNEL_EMOJI)} *#{escape(inbox.name)}*  ·  ##{conversation.display_id}"]
    lines << "*#{escape(subject)}*" if subject.present?
    lines << escape(summary) if summary.present?
    lines.join("\n").truncate(SECTION_TEXT_LIMIT)
  end

  def meta_line
    parts = [status_text, assignee_text, t('from', sender: escape(sender))]
    parts.unshift(":bell: #{t('notification')}") if conversation.label_list.include?(NOTIFICATION_LABEL)
    parts.join('  ·  ')
  end

  def status_text
    "#{STATUS_EMOJI.fetch(conversation.status, '')} #{t("status.#{conversation.status}")}".strip
  end

  # assigned_entity covers Captain/AI owners as well as agents
  def assignee_text
    owner = conversation.assigned_entity
    owner ? t('assigned_to', name: escape(owner.name)) : t('unassigned')
  end

  def open_button
    {
      type: 'button',
      action_id: 'open_conversation',
      text: { type: 'plain_text', text: t('open_button') },
      url: conversation_url,
      style: 'primary'
    }
  end

  def fallback_text
    escape([subject.presence || summary, sender, inbox.name].compact_blank.join(' — '))
  end

  def subject
    return @subject if defined?(@subject)

    @subject = raw_subject&.squish&.truncate(SUBJECT_LENGTH)
  end

  def raw_subject
    first_incoming_message&.content_attributes&.dig('email', 'subject').presence ||
      conversation.additional_attributes&.dig('mail_subject').presence
  end

  def summary
    @summary ||= conversation.additional_attributes&.dig('spam_triage', 'summary')&.squish&.truncate(AI_SUMMARY_LENGTH).presence ||
                 first_incoming_message&.content.to_s.squish.truncate(FALLBACK_SUMMARY_LENGTH).presence
  end

  def sender
    [contact.name.presence, contact.email.presence && "<#{contact.email}>"].compact.join(' ')
  end

  def first_incoming_message
    return @first_incoming_message if defined?(@first_incoming_message)

    @first_incoming_message = conversation.messages.incoming.where(private: false).reorder(:id).first
  end

  def conversation_url
    "#{ENV.fetch('FRONTEND_URL', nil)}/app/accounts/#{conversation.account_id}/conversations/#{conversation.display_id}"
  end

  # Slack mrkdwn treats &, < and > as control characters
  def escape(text)
    text.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;')
  end

  def t(key, **)
    I18n.t("integration_apps.slack.conversation_header.#{key}", **)
  end
end
