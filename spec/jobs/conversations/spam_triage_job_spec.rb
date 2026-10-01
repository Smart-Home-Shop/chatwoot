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

  it 'skips the LLM call and retries after the lease while another job is triaging the conversation' do
    allow(service).to receive(:perform)
    lock_key = format(Redis::RedisKeys::SPAM_TRIAGE_RUN_LOCK, conversation_id: conversation.id)
    Redis::Alfred.set(lock_key, 'other-run', nx: true, ex: 60)
    allow(Redis::Alfred).to receive(:ttl).and_call_original
    allow(Redis::Alfred).to receive(:ttl).with(lock_key).and_return(45)

    freeze_time do
      # just after the holder's lease runs out, never immediately (that would hot-loop while the lock is held)
      expect { described_class.perform_now(message) }
        .to have_enqueued_job(described_class).with(message).at(46.seconds.from_now)
    end
    expect(service).not_to have_received(:perform)
    expect(Redis::Alfred.get(lock_key)).to eq('other-run')
  ensure
    Redis::Alfred.delete(lock_key)
  end

  it 'holds the run lock for longer than the slowest possible LLM call' do
    allow(service).to receive(:perform).and_return(verdict: 'legit', confidence: 0.9, reason: 'Order query.', message: '{}')
    lock_key = format(Redis::RedisKeys::SPAM_TRIAGE_RUN_LOCK, conversation_id: conversation.id)
    allow(Redis::Alfred).to receive(:set).and_call_original

    described_class.perform_now(message)

    slowest_call = (RubyLLM.config.max_retries + 1) * RubyLLM.config.request_timeout
    expect(Redis::Alfred).to have_received(:set).with(lock_key, anything, nx: true, ex: be > slowest_call)
  end

  it 'does not call the LLM when another run recorded the verdict just before this one took the lock' do
    allow(service).to receive(:perform)
    stale = message.conversation # loaded untriaged, so the job's first check passes
    Conversation.find(conversation.id).update!(additional_attributes: { 'spam_triage' => { 'verdict' => 'legit' } })
    expect(stale.additional_attributes).not_to have_key('spam_triage')

    described_class.perform_now(message)

    expect(service).not_to have_received(:perform)
  end

  context 'when the verdict is spam at or above the threshold' do
    before { allow(service).to receive(:perform).and_return(spam_result) }

    it 'adds the label, a private note and stores the verdict' do
      described_class.perform_now(message)
      conversation.reload

      expect(conversation.label_list).to eq(['suspected-spam'])
      expect(account.labels.find_by(title: 'suspected-spam')).to have_attributes(show_on_sidebar: true)
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

  context 'when releasing auto-replies and alerts held during triage' do
    it 'enqueues the release once the verdict is recorded' do
      allow(service).to receive(:perform).and_return(verdict: 'legit', confidence: 0.95, reason: 'Order query.', message: '{}')

      expect { described_class.perform_now(message) }
        .to have_enqueued_job(Conversations::SpamTriageReleaseJob).with(conversation)
    end

    it 'records an error verdict, still enqueues the release and raises when the service fails' do
      allow(service).to receive(:perform).and_return(error: 'Invalid LLM response format')

      expect { described_class.perform_now(message) }
        .to raise_error(RuntimeError, /Spam triage failed/)
        .and have_enqueued_job(Conversations::SpamTriageReleaseJob).with(conversation)
      expect(conversation.reload.additional_attributes.dig('spam_triage', 'verdict')).to eq('error')
    end
  end
end
