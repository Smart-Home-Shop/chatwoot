# Re-writes a conversation's Slack channel message in place, so its status and assignee stay current
class Integrations::Slack::UpdateConversationHeaderService
  pattr_initialize [:conversation!, :hook!]

  def perform
    # Not posted to Slack (yet), e.g. held for spam triage or suspected spam
    return if conversation.identifier.blank?

    Slack::Web::Client.new(token: hook.access_token).chat_update(
      channel: hook.reference_id,
      ts: conversation.identifier,
      **Integrations::Slack::ConversationHeaderBuilder.new(conversation: conversation).payload
    )
  rescue Slack::Web::Api::Errors::MessageNotFound, Slack::Web::Api::Errors::ChannelNotFound, Slack::Web::Api::Errors::CantUpdateMessage => e
    # The thread was deleted, or the hook now points at another channel: nothing left to keep in sync
    Rails.logger.info "Slack: conversation #{conversation.id} header not updated: #{e.message}"
  end
end
