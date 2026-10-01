require 'rails_helper'

RSpec::Matchers.define_negated_matcher :not_have_enqueued_job, :have_enqueued_job

describe SpamTriageListener do
  let(:listener) { described_class.instance }
  let(:account) { create(:account, spam_triage: true) }
  let(:conversation) { create(:conversation, account: account) }
  let(:message) { create(:message, account: account, conversation: conversation, message_type: :incoming) }
  let(:event) { Events::Base.new('message.created', Time.zone.now, message: message) }

  before { account.enable_features!('captain_tasks') }

  describe '#message_created' do
    it 'enqueues triage for the first message of a thread from the contact' do
      expect { listener.message_created(event) }.to have_enqueued_job(Conversations::SpamTriageJob).with(message)
    end

    it 'still triages when a private note came first' do
      create(:message, account: account, conversation: conversation, message_type: :outgoing, private: true)

      expect { listener.message_created(event) }.to have_enqueued_job(Conversations::SpamTriageJob)
    end

    it 'does not triage follow-up messages' do
      create(:message, account: account, conversation: conversation, message_type: :incoming)

      expect { listener.message_created(event) }.not_to have_enqueued_job(Conversations::SpamTriageJob)
    end

    it 'does not triage threads started by an agent' do
      create(:message, account: account, conversation: conversation, message_type: :outgoing)

      expect { listener.message_created(event) }.not_to have_enqueued_job(Conversations::SpamTriageJob)
    end

    it 'does not triage when the account setting is off' do
      account.update!(spam_triage: false)

      expect { listener.message_created(event) }.not_to have_enqueued_job(Conversations::SpamTriageJob)
    end

    it 'does not triage when captain_tasks is disabled' do
      account.disable_features!('captain_tasks')

      expect { listener.message_created(event) }.not_to have_enqueued_job(Conversations::SpamTriageJob)
    end

    it 'does not triage messages from blocked contacts' do
      conversation.contact.update!(blocked: true)

      expect { listener.message_created(event) }.not_to have_enqueued_job(Conversations::SpamTriageJob)
    end

    it 'releases anything held when the first public message turns out not to need triage' do
      auto_reply = create(:message, account: account, conversation: conversation, message_type: :incoming, content_type: :incoming_email,
                                    content_attributes: { email: { auto_reply: true } })
      event = Events::Base.new('message.created', Time.zone.now, message: auto_reply)

      expect { listener.message_created(event) }
        .to have_enqueued_job(Conversations::SpamTriageReleaseJob).with(conversation)
        .and not_have_enqueued_job(Conversations::SpamTriageJob)
    end

    it 'does not triage private messages' do
      private_note = create(:message, account: account, conversation: conversation, message_type: :incoming, private: true)

      expect { listener.message_created(Events::Base.new('message.created', Time.zone.now, message: private_note)) }
        .not_to have_enqueued_job(Conversations::SpamTriageJob)
    end
  end
end
