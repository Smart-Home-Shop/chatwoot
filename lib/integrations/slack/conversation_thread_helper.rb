# How a conversation maps to a Slack thread: its header message in the channel, and the thread under it.
# Included by SendOnSlackService (needs `conversation`, `hook` and `slack_client`).
module Integrations::Slack::ConversationThreadHelper
  MISSING_THREAD_ERRORS = [Slack::Web::Api::Errors::ThreadNotFound, Slack::Web::Api::Errors::InvalidThreadTs].freeze

  private

  # New to Slack, or its header lives in a channel the hook no longer posts to (the integration was reconnected elsewhere)
  def needs_conversation_header?
    return true if conversation.identifier.blank?

    header_channel = conversation.additional_attributes&.dig('slack_channel')
    header_channel.present? && header_channel != hook.reference_id
  end

  # The channel message for a conversation; its ts becomes the thread the conversation's messages are posted in.
  # The channel is remembered so a reconnect to another channel starts a fresh header there.
  def post_conversation_header
    header = slack_client.chat_postMessage(
      channel: hook.reference_id,
      **Integrations::Slack::ConversationHeaderBuilder.new(conversation: conversation).payload,
      unfurl_links: false
    )
    conversation.update!(
      identifier: header['ts'],
      additional_attributes: (conversation.additional_attributes || {}).merge('slack_channel' => hook.reference_id)
    )
  end
end
