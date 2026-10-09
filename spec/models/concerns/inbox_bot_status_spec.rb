require 'rails_helper'

RSpec.describe InboxBotStatus do
  let(:inbox) { create(:inbox) }

  describe '#bot_connected?' do
    it 'is false without a bot' do
      expect(inbox.bot_connected?).to be(false)
    end

    it 'is true with an agent bot connected' do
      create(:agent_bot_inbox, inbox: inbox, agent_bot: create(:agent_bot, account: inbox.account))

      expect(inbox.reload.bot_connected?).to be(true)
    end

    it 'is true with an enabled Dialogflow hook' do
      create(:integrations_hook, :dialogflow, inbox: inbox, account: inbox.account)

      expect(inbox.reload.bot_connected?).to be(true)
    end
  end

  it 'refreshes the cached inbox list when a bot is connected, so bot_connected is current' do
    agent_bot = create(:agent_bot, account: inbox.account)
    travel 2.seconds # the cache key is a timestamp in seconds

    expect { create(:agent_bot_inbox, inbox: inbox, agent_bot: agent_bot) }.to(change { inbox.account.reload.cache_keys[:inbox] })
  end
end
