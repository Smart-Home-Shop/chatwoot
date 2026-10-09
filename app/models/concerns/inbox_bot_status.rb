module InboxBotStatus
  extend ActiveSupport::Concern

  def active_bot?
    external_bot_active?
  end

  # A bot is set up to handle conversations here (even if it's out of responses right now). Pending exists for bot-handled
  # conversations, so the dashboard hides it when no inbox has one.
  def bot_connected?
    external_bot_active?
  end

  def external_bot_active?
    agent_bot_inbox&.active? || dialogflow_active?
  end

  private

  def dialogflow_active?
    hooks.exists?(app_id: %w[dialogflow], status: 'enabled')
  end
end
