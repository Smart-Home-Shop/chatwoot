require 'rails_helper'

RSpec.describe Conversations::SpamTriageReleaseJob do
  let(:account) { create(:account, spam_triage: true) }
  let(:agent) { create(:user, account: account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:message) { create(:message, account: account, conversation: conversation, message_type: :incoming) }
  let(:gate) { Conversations::SpamTriageGate.new(conversation: conversation) }
  let(:hook_service) { instance_double(MessageTemplates::HookExecutionService, perform: true) }

  before do
    account.enable_features!('captain_tasks')
    message
    gate.hold(type: 'templates', message_id: message.id)
    gate.hold(type: 'assignment', user_id: agent.id)
    allow(MessageTemplates::HookExecutionService).to receive(:new).with(message: message).and_return(hook_service)
    allow(NotificationListener.instance).to receive(:notify_assignee)
  end

  after { gate.discard_held }

  it 'waits while the verdict is still pending' do
    described_class.perform_now(conversation)

    expect(hook_service).not_to have_received(:perform)
    expect(gate.held_entries.size).to eq(2)
  end

  context 'with a verdict that is not spam' do
    before { conversation.update!(additional_attributes: { 'spam_triage' => { 'verdict' => 'legit' } }) }

    it 'replays what was held and clears it' do
      conversation.update!(assignee: agent)

      described_class.perform_now(conversation)

      expect(hook_service).to have_received(:perform)
      expect(NotificationListener.instance).to have_received(:notify_assignee).with(conversation)
      expect(gate.held_entries).to be_empty
    end

    it 'skips a held assignment alert when the conversation has since been reassigned' do
      described_class.perform_now(conversation)

      expect(NotificationListener.instance).not_to have_received(:notify_assignee)
    end

    it 'reschedules itself instead of draining while another release holds the lock' do
      lock_key = format(Redis::RedisKeys::SPAM_TRIAGE_HELD_LOCK, conversation_id: conversation.id)
      Redis::LockManager.new.lock(lock_key, 30)

      expect { described_class.perform_now(conversation) }.to have_enqueued_job(described_class).with(conversation)
      expect(hook_service).not_to have_received(:perform)
      expect(gate.held_entries.size).to eq(2)
    ensure
      Redis::LockManager.new.unlock(lock_key)
    end

    it 'keeps the entries that did not run when a replay fails, for the retry' do
      allow(hook_service).to receive(:perform).and_raise(StandardError, 'boom')

      expect { described_class.perform_now(conversation) }.to raise_error(StandardError, 'boom')
      expect(gate.held_entries.size).to eq(2)
    end
  end

  it 'discards everything held when the conversation is flagged as suspected spam' do
    conversation.update!(additional_attributes: { 'spam_triage' => { 'verdict' => 'spam' } }, label_list: ['suspected-spam'])

    described_class.perform_now(conversation)

    expect(hook_service).not_to have_received(:perform)
    expect(gate.held_entries).to be_empty
  end
end
