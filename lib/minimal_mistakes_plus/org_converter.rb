require 'nokogiri'
require 'rouge'

module Jekyll
  FURIGANA_REGEX = /((?:\p{Han}|々|\|)(?:(?:\p{Han}|々|\||\s)*(?:\p{Han}|々|\|))?)\s*[（(]([ぁ-んァ-ヶー|\s]+)[）)]/
end

Jekyll::Hooks.register [:pages, :documents], :pre_render do |doc|
  # Enable Liquid syntax
  if doc.extname.downcase == '.org'
    if doc.data['heading_ids'] == 'topdown'
      doc.content = "%%HEADING_IDS:topdown%%\n" + doc.content
    end

    # Enable {% raw %}...{% endraw %}
    doc.content = doc.content.gsub(/^[ \t]*(\{%[ \t]*raw[ \t]*%\})[ \t]*\n?/, '\1')
    doc.content = doc.content.gsub(/^[ \t]*(\{%[ \t]*endraw[ \t]*%\})[ \t]*\n?/, '\1')

    block_regex = /(?mi:^[ \t]*#\+(?:begin_src|BEGIN_HTML).*?^[ \t]*#\+(?:end_src|END_HTML))/
    raw_regex = /(?mi:\{%[ \t]*raw[ \t]*%\}.*?\{%[ \t]*endraw[ \t]*%\})/
    include_regex = /^[ \t]*(\{%[ \t]*include[ \t]+(?:figure|gallery)(?:(?!%\}).|\{%.*?%\})*%\})[ \t]*$/m

    # Enable figures, galleries, and links to posts (skip inside code or raw blocks)
    doc.content = doc.content.gsub(/#{block_regex}|#{raw_regex}|#{include_regex}/) do |match|
      $1 ? "\n#+BEGIN_HTML\n#{$1}\n#+END_HTML\n" : match
    end

    # Pre-process furigana to strip newlines and prevent org-ruby table corruption
    doc.content = doc.content.gsub(/#{block_regex}|#{raw_regex}|#{Jekyll::FURIGANA_REGEX}/) do |match|
      if match.match?(/\A[ \t]*(?:#\+|\{%)/)
        match
      else
        match.gsub(/[\r\n]+/, '')
      end
    end

    inline_code = /[=~][^=~\n]+[=~]/
    markdown_link = /(?<!\!)\[([^\]]+)\]\(([^)]+)\)/

    doc.content = doc.content.gsub(/#{block_regex}|^[ \t]*:[^\n]*$|#{inline_code}|#{markdown_link}/) do |match|
      match.start_with?('[') && !match.start_with?('[[') ? "[[#{$2}][#{$1}]]" : match
    end
  end
end

module Jekyll
  class OrgConverter < Converter
    safe true
    priority :low

    def matches(ext)
      ext =~ /^\.org$/i
    end

    def output_ext(ext)
      ".html"
    end

    def convert(content)
      topdown = false
      if content.sub!(/\A%%HEADING_IDS:topdown%%\r?\n/, '')
        topdown = true
      end

      # Parse CUSTOM_ID properties and inject a temporary marker
      lines = content.lines
      lines.each_with_index do |line, index|
        if line =~ /^\*+[ \t]+/
          j = index + 1
          if j < lines.length && lines[j] =~ /^[ \t]*:PROPERTIES:[ \t]*$/i
            k = j + 1
            custom_id = nil
            while k < lines.length && lines[k] !~ /^[ \t]*:END:[ \t]*$/i && lines[k] !~ /^\*+[ \t]+/
              if lines[k] =~ /^[ \t]*:CUSTOM_ID:[ \t]+(\S+)/i
                custom_id = $1
              end
              k += 1
            end
            if custom_id && lines[k] =~ /^[ \t]*:END:[ \t]*$/i
              lines[index] = lines[index].chomp + " %%CUSTOM_ID:#{custom_id}%%\n"
            end
          end
        end
      end
      content = lines.join

      require 'org-ruby'
      html = Orgmode::Parser.new(content).to_html
      doc = Nokogiri::HTML.fragment(html)

      id_stack = Array.new(6)
      seen_ids = {}

      doc.css('h1, h2, h3, h4, h5, h6').each do |node|
        level = node.name[1].to_i
        custom_id = nil

        if node.content =~ /%%CUSTOM_ID:(\S+)%%/
          custom_id = $1
          # Clean the marker out of all text nodes inside this heading
          node.xpath('.//text()').each do |t|
            t.content = t.content.gsub(/\s*%%CUSTOM_ID:\S+%%/, '')
          end
        end

        slug = node.text.downcase.strip.gsub(/[^a-z0-9\s-]/, '').gsub(/\s+/, '-')
        slug = 'section' if slug.empty?

        if custom_id
          base_id = custom_id
        elsif topdown
          parent_id = id_stack[0...level-1].compact.last
          base_id = parent_id ? "#{parent_id}-#{slug}" : slug
        else
          base_id = slug
        end

        final_id = base_id
        count = 1
        while seen_ids.key?(final_id)
          final_id = "#{base_id}-#{count}"
          count += 1
        end
        seen_ids[final_id] = true

        node['id'] = final_id
        id_stack[level - 1] = final_id
        (level..5).each { |i| id_stack[i] = nil }
      end

      # Add <thead> to tables
      doc.css('table').each do |table|
        trs = table.xpath('./tr')
        next if trs.empty?

        if trs.first.at_xpath('./th')
          thead = Nokogiri::XML::Node.new('thead', doc)
          thead.add_child(trs.first)
          tbody = Nokogiri::XML::Node.new('tbody', doc)
          trs[1..-1].each { |tr| tbody.add_child(tr) }
          table.add_child(thead)
          table.add_child(tbody)
        else
          tbody = Nokogiri::XML::Node.new('tbody', doc)
          trs.each { |tr| tbody.add_child(tr) }
          table.add_child(tbody)
        end
      end

      # Process code blocks to enable code highlighting
      doc.css('pre.src[lang]').each do |pre|
        lang = pre['lang']
        lexer = Rouge::Lexer.find_fancy(lang) || Rouge::Lexers::PlainText
        formatter = Rouge::Formatters::HTML.new

        # .sub(/\A[\r\n]+/, '') targets the absolute beginning of the string
        # (\A) and removes any leading line breaks or carriage returns.
        # .sub(/\s+\z/, '') targets the absolute end of the string (\z) and
        # removes any trailing whitespace, including empty lines and spaces.
        code_text = pre.text.sub(/\A[\r\n]+/, '').sub(/\s+\z/, '')

        highlighted = formatter.format(lexer.lex(code_text))
        new_node = Nokogiri::HTML.fragment(%Q{
            <div class="language-#{lang} highlighter-rouge">
              <div class="highlight"><pre class="highlight"><code>#{highlighted}</code></pre></div>
            </div>
          })
        pre.replace(new_node)
      end

      # Process Kramdown-style attribute lists {: .class1 .class2 }
      doc.xpath('.//text()[contains(., "{:")]').each do |node|
        # Skip if the syntax is inside a literal code block
        next if node.ancestors('pre, code').any?

        if node.content =~ /\{:\s*((?:\.[a-zA-Z0-9_\-–—]+\s*)+)\}/
          raw_classes = $1
          normalized_classes = raw_classes.gsub(/[–—]/, '--')
          class_names = normalized_classes.scan(/\.([a-zA-Z0-9_-]+)/).flatten

          # Strip the syntax from the text node
          node.content = node.content.sub(/\{:\s*(?:\.[a-zA-Z0-9_\-–—]+\s*)+\}/, '')

          parent = node.parent
          target = parent

          # Clean up trailing <br> if the syntax was on a new line
          if node.content.strip.empty? && node.previous_sibling && node.previous_sibling.name == 'br'
            node.previous_sibling.remove
          end

          # If removing the syntax leaves the block entirely empty, it targets the previous element
          if parent.name == 'p' && parent.text.strip.empty? && parent.children.all? { |c| c.name == 'text' || c.name == 'br' }
            target = parent.previous_element || parent
            parent.remove if target != parent
          end

          # Apply the classes safely without overwriting existing ones
          existing_classes = target['class'] ? target['class'].split(' ') : []
          target['class'] = (existing_classes + class_names).uniq.join(' ')
        end
      end

      # Process complex list items to wrap leading text in <p>
      block_tags = %w[p div ul ol blockquote pre table dl figure h1 h2 h3 h4 h5 h6 hr]
      doc.css('li').each do |li|
        first_block = li.children.find { |c| c.element? && block_tags.include?(c.name.downcase) }

        if first_block
          leading_nodes = []
          li.children.each do |child|
            break if child == first_block
            leading_nodes << child
          end

          # Check if there is actual inline content/text to wrap
          has_content = leading_nodes.any? do |n|
            (n.text? && !n.text.strip.empty?) || (n.element? && n.name.downcase != 'br')
          end

          if has_content
            p_node = Nokogiri::XML::Node.new('p', doc)
            first_block.add_previous_sibling(p_node)
            leading_nodes.each { |n| p_node.add_child(n) }
          end
        end
      end

      # Furigana handling
      # 1. Use XPath to filter out pre/code ancestors at the C-level (libxml2) for maximum speed.
      # 2. Fast pre-filter using 'contains' so Ruby only processes nodes that actually have parentheses.
      target_nodes = doc.xpath('.//text()[not(ancestor::pre or ancestor::code) and (contains(., "（") or contains(., "("))]')
      target_nodes.each do |node|
        content = node.content
        if content.match?(Jekyll::FURIGANA_REGEX)
          new_html = content.gsub(Jekyll::FURIGANA_REGEX) do |match|
            raw_base = $1
            raw_ruby = $2
            clean_base = raw_base.gsub(/\s+/, '')
            clean_ruby = raw_ruby.gsub(/\s+/, '')
            bases = clean_base.split('|')
            rubies = clean_ruby.split('|')

            if bases.length == rubies.length
              ruby_content = bases.zip(rubies).map { |b, r| "#{b}<rt>#{r}</rt>" }.join('')
              "<ruby>#{ruby_content}</ruby>"
            else
              base = clean_base.delete('|')
              rb = clean_ruby.delete('|')
              "<ruby>#{base}<rt>#{rb}</rt></ruby>"
            end
          end
          node.replace(Nokogiri::HTML::DocumentFragment.parse(new_html)) if new_html != content
        end
      end

      # Newline cleanup (Remove extra spaces between CJK characters)
      cjk = "\\p{Han}\\p{Hiragana}\\p{Katakana}ー、。！？「」『』（）【】，．：；"
      doc.xpath('.//text()[not(ancestor::pre or ancestor::code)]').each do |node|
        content = node.content
        next unless content.match?(/[\r\n]/)

        # 1. Completely remove newlines and spaces between CJK characters (uses
        # lookahead to safely handle overlapping lines)
        content = content.gsub(/([#{cjk}])\s*[\r\n]+\s*(?=[#{cjk}])/o, '\1')
        # 2. Safely convert remaining newlines to a single space
        content = content.gsub(/\s*[\r\n]+\s*/, ' ')

        node.content = content if content != node.content
      end

      doc.to_html
    end
  end
end

Jekyll::Hooks.register [:pages, :documents], :post_render, priority: :high do |doc|
  # Only process Org Mode files
  next unless doc.extname.downcase == '.org'

  is_ordered_post = doc.data['ordered'] == true || doc.data['ordered'] == 'true'
  fragment = Nokogiri::HTML(doc.output)
  modified = false

  counters = Array.new(7, 0)
  anchor_stack = is_ordered_post ? [0] : []

  main_content = fragment.at_css('section.page__content') || fragment.at_css('#main') || fragment

  main_content.css('h1, h2, h3, h4, h5, h6').each do |heading|
    # Skip structural layout headings
    next if heading.ancestors('.toc, .page__comments, .page__related, .sidebar').any?

    level = heading.name[1].to_i
    # Exit any ordered scopes that are at the same or higher level than the current heading
    anchor_stack.reject! { |a| a >= level }

    counters[level] += 1
    ((level + 1)..6).each { |i| counters[i] = 0 }

    if anchor_stack.any?
      active_anchor = anchor_stack.last
      visible_counters = counters[(active_anchor + 1)..level]

      if visible_counters.any?
        number_prefix = visible_counters.join('.') + '. '
        heading.inner_html = "<span class=\"heading-number\">#{number_prefix}</span>" + heading.inner_html

        if heading['id']
          toc_link = fragment.at_css(".toc__menu a[href='##{heading['id']}']")
          if toc_link
            toc_link.inner_html = "<span class=\"toc-number\">#{number_prefix}</span>" + toc_link.inner_html
          end
        end
        modified = true
      end
    end

    if heading['class'] && heading['class'].split.include?('ordered')
      anchor_stack << level
    end
  end

  doc.output = fragment.to_html if modified
end
