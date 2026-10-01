require 'rails_helper'

describe Integrations::Slack::UpdateConversationHeaderService do
  let(:conversation) { create(:conversation, identifier: 'header.ts') }
  let(:hook) { create(:integrations_hook, account: conversation.account) }
  let(:slack_client) { instance_double(Slack::Web::Client, chat_update: true) }

  before { allow(Slack::Web::Client).to receive(:new).and_return(slack_client) }

  it 're-writes the conversation header in place' do
    described_class.new(conversation: conversation, hook: hook).perform

    expect(slack_client).to have_received(:chat_update)
      .with(hash_including(channel: hook.reference_id, ts: 'header.ts', blocks: kind_of(Array)))
  end

  it 'does nothing for conversations that were never posted' do
    conversation.update!(identifier: nil)

    described_class.new(conversation: conversation, hook: hook).perform

    expect(slack_client).not_to have_received(:chat_update)
  end

  it 'prompts reauthorization and disables the hook when the Slack connection is unusable' do
    allow(slack_client).to receive(:chat_update).and_raise(Slack::Web::Api::Errors::InvalidAuth.new('invalid_auth'))
    allow(hook).to receive(:prompt_reauthorization!)

    described_class.new(conversation: conversation, hook: hook).perform

    expect(hook).to have_received(:prompt_reauthorization!)
    expect(hook.reload).to be_disabled
  end

  it 'ignores a header that no longer exists in Slack' do
    allow(slack_client).to receive(:chat_update).and_raise(Slack::Web::Api::Errors::MessageNotFound.new('message_not_found'))

    expect { described_class.new(conversation: conversation, hook: hook).perform }.not_to raise_error
  end
end
