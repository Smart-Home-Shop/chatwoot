require 'rails_helper'

describe Integrations::Slack::MarkdownFormatter do
  def to_mrkdwn(text)
    described_class.new(text).perform
  end

  it 'turns the editor hard line breaks into plain newlines' do
    expect(to_mrkdwn("Hi Jonathan, \\\n\\\nThanks, \\\nGeorge")).to eq("Hi Jonathan, \n\nThanks, \nGeorge")
  end

  it 'converts bold, italic, strike, links, lists and headings to Slack mrkdwn' do
    text = "# Update\n**Order** shipped, see [tracking](https://example.com/t?a=1) and *soon* ~~not~~.\n- one\n- two"

    expect(to_mrkdwn(text)).to eq("*Update*\n*Order* shipped, see <https://example.com/t?a=1|tracking> and _soon_ ~not~.\n• one\n• two")
  end

  it 'removes backslash escapes' do
    expect(to_mrkdwn('Price 5\.00 \- 10\% off\!')).to eq('Price 5.00 - 10\% off!')
  end

  it 'leaves code as written' do
    expect(to_mrkdwn("Run `a\\_b **x**` then\n```\n**y** \\\n```")).to eq("Run `a\\_b **x**` then\n```\n**y** \\\n```")
  end
end
