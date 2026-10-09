module InboxBotStatus
  extend ActiveSupport::Concern

  def active_bot?
    external_bot_active?
  end

  # A bot is set up to handle conversations here (even if it's out of responses right now). Pending exists for bot-handled
  # conversations, so the dashboard hides it when no inbox has one. Reads associations the inbox list preloads.
  def bot_connected?
    agent_bot_inbox&.active? || hooks.any? { |hook| hook.app_id == 'dialogflow' && hook.enabled? }
  end

  def external_bot_active?
    agent_bot_inbox&.active? || dialogflow_active?
  end

  private

  def dialogflow_active?
    hooks.exists?(app_id: %w[dialogflow], status: 'enabled')
  end
end
