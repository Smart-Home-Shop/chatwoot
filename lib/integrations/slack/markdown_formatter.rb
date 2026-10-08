# Converts the Markdown agents write in Chatwoot's editor into Slack mrkdwn, so replies and notes read cleanly in the
# thread instead of showing editor syntax (e.g. the trailing backslashes of hard line breaks)
class Integrations::Slack::MarkdownFormatter
  pattr_initialize :text

  def perform
    doc = CommonMarker.render_doc(text.to_s, [:DEFAULT, :STRIKETHROUGH_DOUBLE_TILDE], [:strikethrough])
    Messages::MarkdownRenderers::SlackRenderer.new.render(doc).strip
  end
end
