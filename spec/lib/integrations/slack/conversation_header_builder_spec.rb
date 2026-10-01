require 'rails_helper'

describe Integrations::Slack::ConversationHeaderBuilder do
  subject(:payload) { described_class.new(conversation: conversation.reload).payload }

  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account, name: 'Support & Sales') }
  let(:contact) { create(:contact, account: account, name: 'Sarah Jones', email: 'sarah@example.com') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:text) { payload[:blocks].flat_map { |block| [block.dig(:text, :text), *block[:elements]&.pluck(:text)] }.join("\n") }

  before do
    create(:message, account: account, inbox: inbox, conversation: conversation, sender: contact, message_type: :incoming,
                     content: "Hello,\n\nwhere is my <order> 10442? It still shows as processing.",
                     content_attributes: { email: { subject: 'Where is my order?' } })
  end

  it 'shows the inbox, conversation number, subject, sender and an open button' do
    expect(text).to include('Support &amp; Sales', "##{conversation.display_id}", '*Where is my order?*')
    expect(text).to include('From Sarah Jones &lt;sarah@example.com&gt;')
    button = payload[:blocks].first[:accessory]
    expect(button).to include(type: 'button', style: 'primary')
    expect(button[:url]).to end_with("/app/accounts/#{account.id}/conversations/#{conversation.display_id}")
  end

  it 'uses the spam triage summary when there is one' do
    conversation.update!(additional_attributes: { 'spam_triage' => { 'summary' => 'Asks when order 10442 will ship.' } })

    expect(text).to include('Asks when order 10442 will ship.')
    expect(text).not_to include('still shows as processing')
  end

  it 'falls back to the first message on one line, escaped, when there is no summary' do
    expect(text).to include('Hello, where is my &lt;order&gt; 10442? It still shows as processing.')
  end

  it 'shows the current status and assignee' do
    agent = create(:user, account: account, name: 'Paul')
    conversation.update!(status: :resolved, assignee: agent)

    expect(text).to include(':white_check_mark: Resolved', 'Assigned to Paul')
  end

  it 'shows an agent bot or AI owner rather than unassigned' do
    bot = create(:agent_bot, account: account, name: 'Captain Bot')
    allow(conversation).to receive(:assigned_entity).and_return(bot)

    text = described_class.new(conversation: conversation).payload[:blocks].last[:elements].first[:text]
    expect(text).to include('Assigned to Captain Bot')
  end

  it 'shows unassigned conversations and tags automated notifications' do
    conversation.update!(label_list: ['notification'])

    expect(text).to include('Unassigned', ':bell: Automated notification')
  end

  it 'has a plain fallback text for Slack notifications' do
    expect(payload[:text]).to eq('Where is my order? — Sarah Jones &lt;sarah@example.com&gt; — Support &amp; Sales')
  end
end
