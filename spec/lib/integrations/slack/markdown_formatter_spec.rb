require 'rails_helper'

describe Integrations::Slack::MarkdownFormatter do
  def to_mrkdwn(text)
    described_class.new(text).perform
  end

  it 'turns the editor hard line breaks into plain newlines' do
    expect(to_mrkdwn("Hi Jonathan, \\\n\\\nThanks, \\\nGeorge")).to eq("Hi Jonathan, \n\nThanks, \nGeorge")
  end

  it 'converts bold, italic, strike, links, lists and headings to Slack mrkdwn' do
    text = "# Update\n**Order** shipped, see [tracking](https://example.com/t?a=1&b=2) and *soon* ~~not~~.\n\n- one\n- two\n\n1. first\n2. second"

    expect(to_mrkdwn(text)).to eq(
      "*Update*\n\n*Order* shipped, see <https://example.com/t?a=1&amp;b=2|tracking> and _soon_ ~not~.\n\n• one\n• two\n\n1. first\n2. second"
    )
  end

  it 'quotes every line of a blockquote' do
    expect(to_mrkdwn("Thanks\n\n> On Thu wrote:\n>\n> Hello **there**\n> again")).to eq("Thanks\n\n> On Thu wrote:\n> \n> Hello *there*\n> again")
  end

  it 'removes backslash escapes and escapes Slack control characters' do
    expect(to_mrkdwn('Price 5\.00 \- 3 < 4 & <b>bold</b>')).to eq('Price 5.00 - 3 &lt; 4 &amp; &lt;b&gt;bold&lt;/b&gt;')
  end

  it 'leaves code as written, including spans delimited by several backticks' do
    expect(to_mrkdwn("Run ``a`b **x**`` then\n\n```\n**y** \\\n```")).to eq("Run `a`b **x**` then\n\n```\n**y** \\\n```")
  end
end
