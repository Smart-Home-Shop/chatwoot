# Converts the Markdown agents write in Chatwoot's editor into Slack mrkdwn, so replies and notes read cleanly in the
# thread instead of showing editor syntax (e.g. the trailing backslashes of hard line breaks).
class Integrations::Slack::MarkdownFormatter
  pattr_initialize :text

  CODE_SPAN = /(```.*?```|`[^`\n]*`)/m

  def perform
    # Leave code as written; convert everything around it
    text.to_s.split(CODE_SPAN).each_with_index.map { |part, index| index.odd? ? part : convert(part) }.join
  end

  private

  def convert(part)
    part
      .gsub("\\\n", "\n")                                     # hard line break
      .gsub(/\[([^\]\n]+)\]\((\S+?)\)/, '<\2|\1>')           # [text](url)
      .gsub(/^(\s*)[-*+] /, '\1• ')                          # bullet lists
      .gsub(/(?<![*\w])\*([^*\n]+)\*(?![*\w])/, '_\1_')      # *italic*
      .gsub(/\*\*(.+?)\*\*/, '*\1*')                         # **bold**
      .gsub(/~~(.+?)~~/, '~\1~')                             # ~~strike~~
      .gsub(/^#+ +(.+)$/, '*\1*')                            # headings
      .gsub(/\\([\\`*_{}\[\]()#+\-.!~>|])/, '\1')            # backslash escapes
  end
end
