require 'rails_helper'

RSpec.describe Conversations::SpamTriageGate do
  subject(:gate) { described_class.new(conversation: conversation) }

  let(:account) { create(:account, spam_triage: true) }
  let(:conversation) { create(:conversation, account: account) }
  let(:entry) { { type: 'conversation_creation' } }

  before do
    account.enable_features!('captain_tasks')
    create(:message, account: account, conversation: conversation, message_type: :incoming)
    # creating the message already held its own auto-reply hook; start each example from an empty hold
    gate.discard_held
  end

  after { gate.discard_held }

  describe '#hold' do
    it 'records the entry once and schedules a fallback release at the hold deadline' do
      deadline = conversation.created_at + described_class::AWAIT_WINDOW

      expect { gate.hold(entry) }
        .to have_enqueued_job(Conversations::SpamTriageReleaseJob).with(conversation).at(deadline)
      expect(gate.hold(entry)).to be(true)

      expect(gate.held_entries.map(&:last)).to eq([{ 'type' => 'conversation_creation' }])
    end

    it 'lets the side effect run when a verdict lands while it waits for the lock' do
      stale_gate = described_class.new(conversation: Conversation.find(conversation.id))
      # awaiting before the lock, decided by the time the lock is held and the conversation is reloaded
      allow(stale_gate).to receive(:awaiting_verdict?).and_return(true, false)

      expect(stale_gate.hold(entry)).to be(false)
      expect(gate.held_entries).to be_empty
    end

    it 'drops the side effect when a spam verdict lands while it waits for the lock' do
      stale_gate = described_class.new(conversation: Conversation.find(conversation.id))
      conversation.update!(additional_attributes: { 'spam_triage' => { 'verdict' => 'spam' } }, label_list: ['suspected-spam'])
      # not spam yet before the lock, flagged by the time the lock is held and the conversation is reloaded
      allow(stale_gate).to receive_messages(awaiting_verdict?: true)
      allow(stale_gate).to receive(:suspected_spam?).and_return(false, true)

      expect(stale_gate.hold(entry)).to be(true)
      expect(gate.held_entries).to be_empty
    end

    it 'un-records the entry when the fallback release cannot be scheduled, so a retry can schedule it' do
      job = class_double(Conversations::SpamTriageReleaseJob)
      allow(Conversations::SpamTriageReleaseJob).to receive(:set).and_return(job)
      allow(job).to receive(:perform_later).and_raise(RedisClient::CannotConnectError)

      expect { gate.hold(entry) }.to raise_error(RedisClient::CannotConnectError)
      expect(gate.held_entries).to be_empty
    end

    it 'lets the side effect run once there is a verdict' do
      conversation.update!(additional_attributes: { 'spam_triage' => { 'verdict' => 'legit' } })

      expect(described_class.new(conversation: conversation.reload).hold(entry)).to be(false)
    end

    it 'drops the side effect without recording it while the conversation is labelled suspected spam' do
      conversation.update!(additional_attributes: { 'spam_triage' => { 'verdict' => 'spam' } }, label_list: ['suspected-spam'])

      expect(gate.hold(entry)).to be(true)
      expect(gate.held_entries).to be_empty
    end

    it 'stops holding once the await window has passed without a verdict' do
      conversation.update!(created_at: 11.minutes.ago)

      expect(gate.hold(entry)).to be(false)
    end

    it 'does not hold when spam triage is off' do
      account.update!(spam_triage: false)

      expect(gate.hold(entry)).to be(false)
    end

    it 'does not hold threads an agent started' do
      other = create(:conversation, account: account)
      create(:message, account: account, conversation: other, message_type: :outgoing)

      expect(described_class.new(conversation: other).hold(entry)).to be(false)
    end
  end
end
