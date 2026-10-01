require 'rails_helper'

RSpec.describe Captain::SpamTriageService do
  let(:account) { create(:account, name: 'Smart Home Shop') }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, name: 'Daniel Growth', email: 'daniel@rank-boost.biz') }
  let(:conversation) do
    create(:conversation, account: account, inbox: inbox, contact: contact, additional_attributes: { 'mail_subject' => 'Quick question' })
  end
  let(:message) do
    create(:message, account: account, inbox: inbox, conversation: conversation, sender: contact,
                     message_type: :incoming, content: 'We can get you to page 1 of Google.')
  end
  let(:service) { described_class.new(account: account, message: message) }

  before do
    create(:installation_config, name: 'CAPTAIN_OPEN_AI_API_KEY', value: 'test-key')
    allow(Integrations::Openai::KeyValidator).to receive(:valid?).and_return(true)
    account.enable_features!('captain_tasks')
  end

  def respond_with(raw)
    allow(service).to receive(:make_api_call).and_return(message: raw)
  end

  describe '#perform' do
    it 'returns the verdict and keeps the raw message for usage metering' do
      respond_with('{"verdict":"spam","confidence":0.92,"reason":" Cold SEO pitch. "}')

      expect(service.perform).to eq(verdict: 'spam', confidence: 0.92, reason: 'Cold SEO pitch.', summary: nil,
                                    message: '{"verdict":"spam","confidence":0.92,"reason":" Cold SEO pitch. "}')
    end

    it 'returns the summary when the LLM gives one' do
      respond_with('{"verdict":"legit","confidence":0.9,"reason":"Order query.","summary":" Asks when order 10442 will ship. "}')

      expect(service.perform).to include(summary: 'Asks when order 10442 will ship.')
    end

    it 'rejects a non-string summary' do
      respond_with('{"verdict":"legit","confidence":0.9,"reason":"Order query.","summary":42}')

      expect(service.perform).to include(error: 'Invalid LLM response format')
    end

    it 'accepts JSON wrapped in a code fence' do
      respond_with("```json\n{\"verdict\":\"notification\",\"confidence\":1,\"reason\":\"Carrier invoice.\"}\n```")

      expect(service.perform).to include(verdict: 'notification', confidence: 1.0)
    end

    {
      'an unknown verdict' => '{"verdict":"maybe","confidence":0.5,"reason":"x"}',
      'a text confidence' => '{"verdict":"spam","confidence":"high","reason":"x"}',
      'a missing confidence' => '{"verdict":"spam","reason":"x"}',
      'an out-of-range confidence' => '{"verdict":"spam","confidence":1.4,"reason":"x"}',
      'a blank reason' => '{"verdict":"legit","confidence":0.8,"reason":" "}',
      'a non-object' => '["spam"]',
      'invalid JSON' => 'not json'
    }.each do |description, raw|
      it "rejects #{description}" do
        respond_with(raw)

        # the raw reply is kept alongside the error for debugging; with :error present the Enterprise wrapper doesn't meter it
        expect(service.perform).to eq(error: 'Invalid LLM response format', message: raw)
      end
    end

    it 'passes LLM errors through unchanged' do
      allow(service).to receive(:make_api_call).and_return(error: 'API key missing', error_code: 401)

      expect(service.perform).to eq(error: 'API key missing', error_code: 401)
    end

    it 'sends the business name, channel, sender, subject and message to the spam_triage feature' do
      respond_with('{"verdict":"legit","confidence":0.9,"reason":"Order query."}')

      service.perform

      expect(service).to have_received(:make_api_call) do |args|
        expect(args[:feature]).to eq('spam_triage')
        expect(args[:messages].first[:content]).to include('Smart Home Shop')
        expect(args[:messages].last[:content]).to include(
          'Channel: WebWidget', 'From: Daniel Growth <daniel@rank-boost.biz>', 'Subject: Quick question',
          'We can get you to page 1 of Google.'
        )
      end
    end
  end
end
