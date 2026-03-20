require "nokogiri"

module MinimalMistakesPlus
  FURIGANA_REGEX = /((?:\p{Han}|々|｜)(?:(?:\p{Han}|々|｜|\s)*(?:\p{Han}|々|｜))?)\s*（([ぁ-んァ-ヶー｜\s]+)）/

  module Furigana
    def self.process(doc)
      ext = doc.extname.downcase
      return unless %w[.org .md .markdown .mkd].include?(ext)

      html_doc = Nokogiri::HTML(doc.output)
      modified = false

      target_nodes = html_doc.xpath('.//text()[not(ancestor::pre or ancestor::code) and contains(., "（")]')
      target_nodes.each do |node|
        content = node.content
        if content.match?(FURIGANA_REGEX)
          new_html = content.gsub(FURIGANA_REGEX) do
            raw_base = ::Regexp.last_match(1)
            raw_ruby = ::Regexp.last_match(2)
            clean_base = raw_base.gsub(/\s+/, "")
            clean_ruby = raw_ruby.gsub(/\s+/, "")
            bases = clean_base.split("｜")
            rubies = clean_ruby.split("｜")

            if bases.length == rubies.length
              ruby_content = bases.zip(rubies).map { |b, r| "#{b}<rt>#{r}</rt>" }.join("")
              "<ruby>#{ruby_content}</ruby>"
            else
              base = clean_base.delete("｜")
              rb = clean_ruby.delete("｜")
              "<ruby>#{base}<rt>#{rb}</rt></ruby>"
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
