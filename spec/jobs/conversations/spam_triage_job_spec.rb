require 'rails_helper'

RSpec.describe Conversations::SpamTriageJob do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  # Reloaded like a Sidekiq-deserialized argument, so the conversation isn't the dirty in-memory record from create
  let(:message) { create(:message, conversation: conversation, account: account, message_type: :incoming).reload }
  let(:service) { instance_double(Captain::SpamTriageService) }
  let(:spam_result) { { verdict: 'spam', confidence: 0.92, reason: 'Cold SEO pitch.', message: '{"verdict":"spam"}' } }

  before { allow(Captain::SpamTriageService).to receive(:new).with(account: account, message: message).and_return(service) }

  it 'enqueues on the low queue' do
    expect { described_class.perform_later(message) }.to have_enqueued_job(described_class).on_queue('low')
  end

  context 'when the verdict is spam at or above the threshold' do
    before { allow(service).to receive(:perform).and_return(spam_result) }

    it 'adds the label, a private note and stores the verdict' do
      described_class.perform_now(message)
      conversation.reload

      expect(conversation.label_list).to eq(['suspected-spam'])
      expect(account.labels.find_by(title: 'suspected-spam')).to be_present
      expect(conversation.messages.where(private: true).last.content).to eq('Suspected spam (92% confidence): Cold SEO pitch.')
      expect(conversation.additional_attributes['spam_triage']).to include('verdict' => 'spam', 'confidence' => 0.92, 'reason' => 'Cold SEO pitch.')
      expect(conversation.additional_attributes['spam_triage']).not_to have_key('message')
    end

    it 'does not flag or call the service again when re-run' do
      described_class.perform_now(message)
      described_class.perform_now(message)

      expect(service).to have_received(:perform).once
      expect(conversation.reload.messages.where(private: true).count).to eq(1)
    end
  end

  it 'stores a spam verdict below the threshold without flagging' do
    allow(service).to receive(:perform).and_return(spam_result.merge(confidence: 0.69))

    described_class.perform_now(message)
    conversation.reload

    expect(conversation.label_list).to be_empty
    expect(conversation.messages.where(private: true)).to be_empty
    expect(conversation.additional_attributes.dig('spam_triage', 'confidence')).to eq(0.69)
  end

  it 'labels a notification without adding a note' do
    allow(service).to receive(:perform).and_return(verdict: 'notification', confidence: 0.9, reason: 'Carrier invoice.', message: '{}')

    described_class.perform_now(message)
    conversation.reload

    expect(conversation.label_list).to eq(['notification'])
    expect(conversation.messages.where(private: true)).to be_empty
    expect(conversation.additional_attributes.dig('spam_triage', 'verdict')).to eq('notification')
  end

  it 'stores a legit verdict without flagging' do
    allow(service).to receive(:perform).and_return(verdict: 'legit', confidence: 0.95, reason: 'Order query.', message: '{}')

    described_class.perform_now(message)
    conversation.reload

    expect(conversation.label_list).to be_empty
    expect(conversation.additional_attributes.dig('spam_triage', 'verdict')).to eq('legit')
  end

  it 'raises and stores nothing when the service fails, so the job is retried' do
    allow(service).to receive(:perform).and_return(error: 'Invalid LLM response format')

    expect { described_class.perform_now(message) }.to raise_error(RuntimeError, /Spam triage failed/)
    expect(conversation.reload.additional_attributes).not_to have_key('spam_triage')
  end

  it 'rolls back the verdict when flagging fails' do
    allow(service).to receive(:perform).and_return(spam_result)
    allow(Messages::MessageBuilder).to receive(:new).and_raise(ActiveRecord::RecordInvalid)

    expect { described_class.perform_now(message) }.to raise_error(ActiveRecord::RecordInvalid)
    conversation.reload
    expect(conversation.additional_attributes).not_to have_key('spam_triage')
    expect(conversation.label_list).to be_empty
  end
end
