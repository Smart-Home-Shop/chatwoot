# Re-writes a conversation's Slack channel message in place, so its status and assignee stay current
class Integrations::Slack::UpdateConversationHeaderService
  # The header was deleted, or belongs to a channel the hook no longer posts to: nothing left to keep in sync
  STALE_HEADER_ERRORS = [Slack::Web::Api::Errors::MessageNotFound, Slack::Web::Api::Errors::CantUpdateMessage].freeze
  # Same as the other Slack writers: the connection is unusable, so ask for reauthorization instead of failing every event
  BROKEN_CONNECTION_ERRORS = [
    Slack::Web::Api::Errors::IsArchived, Slack::Web::Api::Errors::AccountInactive, Slack::Web::Api::Errors::MissingScope,
    Slack::Web::Api::Errors::InvalidAuth, Slack::Web::Api::Errors::ChannelNotFound, Slack::Web::Api::Errors::NotInChannel
  ].freeze

  pattr_initialize [:conversation!, :hook!]

  def perform
    # Not posted to Slack (yet), e.g. held for spam triage or suspected spam
    return if conversation.identifier.blank?

    update_header
  rescue *STALE_HEADER_ERRORS => e
    Rails.logger.info "[Slack] conversation #{conversation.id} header not updated: #{e.message}"
  rescue *BROKEN_CONNECTION_ERRORS => e
    Rails.logger.error "[Slack] header update failed (account=#{conversation.account_id}, hook=#{hook.id}): #{e.message}"
    hook.prompt_reauthorization!
    hook.disable
  end

  private

  def update_header
    Slack::Web::Client.new(token: hook.access_token).chat_update(
      channel: hook.reference_id,
      ts: conversation.identifier,
      **Integrations::Slack::ConversationHeaderBuilder.new(conversation: conversation).payload
    )
  end
end
