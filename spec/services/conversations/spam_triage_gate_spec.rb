require 'rails_helper'

RSpec.describe Conversations::SpamTriageGate do
  subject(:gate) { described_class.new(conversation: conversation) }

  let(:account) { create(:account, spam_triage: true) }
  let(:conversation) { create(:conversation, account: account) }

  before do
    account.enable_features!('captain_tasks')
    create(:message, account: account, conversation: conversation, message_type: :incoming)
  end

  describe '#hold?' do
    it 'holds a new conversation started by the contact until it has a verdict' do
      expect(gate.hold?).to be(true)

      conversation.update!(additional_attributes: { 'spam_triage' => { 'verdict' => 'legit' } })
      expect(described_class.new(conversation: conversation.reload).hold?).to be(false)
    end

    it 'holds a conversation labelled suspected spam, until the label is removed' do
      conversation.update!(additional_attributes: { 'spam_triage' => { 'verdict' => 'spam' } }, label_list: ['suspected-spam'])
      expect(gate.hold?).to be(true)

      conversation.update!(label_list: [])
      expect(described_class.new(conversation: conversation.reload).hold?).to be(false)
    end

    it 'stops holding once the await window has passed without a verdict' do
      conversation.update!(created_at: 11.minutes.ago)

      expect(gate.hold?).to be(false)
    end

    it 'does not hold when spam triage is off' do
      account.update!(spam_triage: false)

      expect(gate.hold?).to be(false)
    end

    it 'does not hold threads an agent started' do
      other = create(:conversation, account: account)
      create(:message, account: account, conversation: other, message_type: :outgoing)
      create(:message, account: account, conversation: other, message_type: :incoming)

      expect(described_class.new(conversation: other).hold?).to be(false)
    end
  end
end
