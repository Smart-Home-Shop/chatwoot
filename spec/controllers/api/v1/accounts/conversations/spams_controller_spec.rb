require 'rails_helper'

RSpec.describe 'Conversation Spam API', type: :request do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:url) { api_v1_account_conversation_spam_url(account_id: account.id, conversation_id: conversation.display_id) }

  describe 'POST /api/v1/accounts/{account.id}/conversations/<id>/spam' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        post url
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an agent without access to the conversation' do
      let(:agent) { create(:user, account: account, role: :agent) }

      it 'returns unauthorized and changes nothing' do
        post url, headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unauthorized)
        expect(conversation.reload.label_list).to be_empty
        expect(conversation.contact.reload).not_to be_blocked
      end
    end

    context 'when it is an agent with access to the conversation' do
      let(:agent) { create(:user, account: account, role: :agent) }

      before do
        create(:inbox_member, inbox: conversation.inbox, user: agent)
        conversation.update_labels('suspected-spam')
      end

      it 'creates the spam label, adds it alongside existing labels and blocks the contact' do
        post url, headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body['payload']).to contain_exactly('suspected-spam', 'spam')
        expect(account.labels.find_by(title: 'spam')).to have_attributes(show_on_sidebar: true)
        expect(conversation.reload).to be_resolved
        expect(conversation.contact.reload).to be_blocked
      end

      it 'reuses an existing spam label' do
        create(:label, account: account, title: 'spam', color: '#123456')

        post url, headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(account.labels.where(title: 'spam').count).to eq(1)
        expect(account.labels.find_by(title: 'spam').color).to eq('#123456')
      end
    end
  end
end
