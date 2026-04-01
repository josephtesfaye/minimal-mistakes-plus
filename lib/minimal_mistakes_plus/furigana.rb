require "nokogiri"

module MinimalMistakesPlus
  # Regular expression to capture the （Base：Ruby） format, including newlines
  # (using the 'm' modifier to match across newlines)
  FURIGANA_REGEX = /（([^（）：]+?)：([^（）：]+?)）/m

  module Furigana
    def self.process(doc)
      ext = doc.extname.downcase
      return unless %w[.org .md .markdown .mkd].include?(ext)

      html_doc = Nokogiri::HTML(doc.output)
      modified = false

      # Exclude inside 'pre' and 'code' tags, and fast-extract only text nodes
      # containing both "（" and "："
      target_nodes = html_doc.xpath('.//text()[not(ancestor::pre or ancestor::code) and contains(., "（") and contains(., "：")]')

      target_nodes.each do |node|
        content = node.content
        if content.match?(FURIGANA_REGEX)
          new_html = content.gsub(FURIGANA_REGEX) do
            raw_base = ::Regexp.last_match(1)
            raw_ruby = ::Regexp.last_match(2)

            # Remove only line-wrapping newlines (use [\r\n]+ instead of \s+ to
            # preserve spaces in English ruby)
            clean_base = raw_base.gsub(/[\r\n]+/, "")
            clean_ruby = raw_ruby.gsub(/[\r\n]+/, "")

            bases = clean_base.split("｜")
            rubies = clean_ruby.split("｜")

            # If the number of parts divided by '｜' matches, apply ruby to each
            # part (single parts are also processed here)
            if bases.length == rubies.length
              ruby_content = bases.zip(rubies).map { |b, r| "#{b}<rt>#{r}</rt>" }.join("")
              "<ruby>#{ruby_content}</ruby>"
            else
              # As a fallback, if the number of parts somehow doesn't match,
              # apply ruby as a single block for the whole text
              base_fallback = clean_base.delete("｜")
              ruby_fallback = clean_ruby.delete("｜")
              "<ruby>#{base_fallback}<rt>#{ruby_fallback}</rt></ruby>"
            end
          end

          if new_html != content
            node.replace(Nokogiri::HTML::DocumentFragment.parse(new_html))
            modified = true
          end
        end
      end

      doc.output = html_doc.to_html if modified
    end
  end
end

Jekyll::Hooks.register [:pages, :documents], :post_render do |doc|
  MinimalMistakesPlus::Furigana.process(doc)
end
