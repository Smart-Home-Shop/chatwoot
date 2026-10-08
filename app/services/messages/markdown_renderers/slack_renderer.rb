# Slack mrkdwn is WhatsApp-style (*bold*, _italic_, ~strike~), plus <url|text> links and &, <, > as control characters
class Messages::MarkdownRenderers::SlackRenderer < Messages::MarkdownRenderers::WhatsAppRenderer
  # Paragraphs keep their blank line; inside a list item they stay tight
  def paragraph(node)
    out(:children)
    node.parent&.type == :list_item ? cr : blankline
  end

  def blockquote(_node)
    quoted = capture { out(:children) }.strip
    out(quoted.lines.map { |line| "> #{line}" }.join)
    blankline
  end

  def list(_node)
    super
    blankline
  end

  def text(node)
    out(escape(node.string_content))
  end

  def code(node)
    out('`', escape(node.string_content), '`')
  end

  def code_block(node)
    out("```\n", escape(node.string_content), '```')
    blankline
  end

  def link(node)
    label = node.each.map(&:to_plaintext).join.strip
    url = escape(node.url)
    out(label.blank? || label == node.url ? "<#{url}>" : "<#{url}|#{escape(label)}>")
  end

  def strikethrough(_node)
    out('~', :children, '~')
  end

  def header(_node)
    out('*', :children, '*')
    blankline
  end

  def list_item(_node)
    return super if @list_type == :ordered_list

    out('• ', :children)
    cr
  end

  # Raw HTML in a reply isn't meaningful in Slack; show it as text
  def html(node)
    out(escape(node.string_content))
  end

  def inline_html(node)
    out(escape(node.string_content))
  end

  private

  def capture
    outer = @stream
    @stream = StringIO.new
    yield
    @stream.string
  ensure
    @stream = outer
  end

  # End the current block with one empty line (CommonMarker 0.23's renderer only has cr)
  def blankline
    cr
    @stream.write("\n") unless @stream.string.empty? || @stream.string.end_with?("\n\n")
  end

  def escape(content)
    content.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;')
  end
end
