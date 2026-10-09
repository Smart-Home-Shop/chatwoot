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
  end
end
