require 'nokogiri'
require 'rouge'

module Jekyll
  # register a custom Liquid filter called orgify. This mirrors Jekyll's
  # built-in markdownify, but dynamically routes the captured string through the
  # org-ruby parser.
  module OrgifyFilter
    def orgify(input)
      return "" if input.nil? || input.empty?
      site = @context.registers[:site]
      converter = site.find_converter_instance(Jekyll::OrgConverter)
      converter.convert(input)
    end
  end

  # Process complex tables
  module OrgAdvancedTables
    def self.generate_html_table(table_text, type)
      lines = table_text.lines.map { |l| l.chomp.sub(/^[ \t]+/, '') }

      preserve_newlines = false
      if lines.first.match?(/#\+ATTR_ARGS:/i)
        preserve_newlines = !!lines.first.match?(/(?:^|\s):newlines[ \t]+t\b/i)
        lines.shift
      end

      lines.reject! { |l| l.strip.empty? }

      max_len = lines.map(&:length).max
      lines.map! { |l| l.ljust(max_len, ' ') }

      if type == :org_complex
        grid_x_tmp = lines.first.enum_for(:scan, /[|+]/).map { Regexp.last_match.begin(0) }
        border_line = " " * max_len
        grid_x_tmp.each { |x| border_line[x] = '|' }
        (0...grid_x_tmp.size - 1).each do |c|
          ((grid_x_tmp[c] + 1)...grid_x_tmp[c + 1]).each { |i| border_line[i] = '-' }
        end
        lines.unshift(border_line) unless lines.first.strip.match?(/^[|+-=]+$/)
        lines.push(border_line) unless lines.last.strip.match?(/^[|+-=]+$/)
      end

      if type == :emacs
        grid_x = lines.first.enum_for(:scan, /\+/).map { Regexp.last_match.begin(0) }
      else
        grid_x = lines.first.enum_for(:scan, /[|+]/).map { Regexp.last_match.begin(0) }
      end

      grid_y = lines.each_index.select do |i|
        (0...grid_x.size - 1).any? do |c|
          lb, rb = lines[i][grid_x[c]], lines[i][grid_x[c + 1]]
          if ['+', '|'].include?(lb) && ['+', '|'].include?(rb)
            seg = lines[i][(grid_x[c] + 1)...grid_x[c + 1]]
            seg && !seg.strip.empty? && seg.strip.match?(/^[-=+]+$/)
          else
            false
          end
        end
      end

      cells = []
      visited = Array.new(grid_y.size - 1) { Array.new(grid_x.size - 1, false) }

      (0...grid_y.size - 1).each do |r|
        (0...grid_x.size - 1).each do |c|
          next if visited[r][c]

          cs = 1
          while c + cs < grid_x.size - 1
            y_check = grid_y[r] + 1
            y_check = grid_y[r] if y_check == grid_y[r + 1]
            char = lines[y_check][grid_x[c + cs]]
            break if char == '|' || char == '+'
            cs += 1
          end

          rs = 1
          while r + rs < grid_y.size - 1
            seg = lines[grid_y[r + rs]][(grid_x[c] + 1)...(grid_x[c + cs])]
            break if seg && !seg.strip.empty? && seg.strip.match?(/^[-=+]+$/)
            rs += 1
          end

          (r...r + rs).each { |vr| (c...c + cs).each { |vc| visited[vr][vc] = true } }

          text_lines = ((grid_y[r] + 1)...grid_y[r + rs]).map { |yy| lines[yy][(grid_x[c] + 1)...grid_x[c + cs]] }

          is_header = type == :org_complex ? (r == 0) : (r == 0 && lines[grid_y[1]].include?('='))

          align = "left"
          if (first_text = text_lines.find { |l| !l.strip.empty? })
            l_space, r_space = first_text[/\A\s*/].length, first_text[/\s*\z/].length
            align = "center" if l_space > 1 && r_space > 1
            align = "right" if l_space > 1 && r_space <= 1
          end

          cells << { r: r, c: c, rs: rs, cs: cs, text_lines: text_lines, align: align, is_header: is_header }
        end
      end

      if type == :org_complex
        new_cells = []
        cells.group_by { |cell| cell[:r] }.each do |r, row_cells|
          i = 0
          while i < row_cells.size
            cell = row_cells[i]
            if cell[:text_lines].map(&:strip).join("").start_with?("<span")
              merged_cs = cell[:cs]
              i += 1
              while i < row_cells.size
                next_cell = row_cells[i]
                merged_cs += next_cell[:cs]
                break if next_cell[:text_lines].map(&:strip).join("") == ">"
                i += 1
              end
              cell[:cs], cell[:text_lines] = merged_cs, []
            end
            new_cells << cell; i += 1
          end
        end
        cells = new_cells
      end

      html = "<table>\n"
      build_tbody = ->(cell_group) {
        return "" if cell_group.empty?
        res = ""
        cell_group.group_by { |c| c[:r] }.each do |r, row_cells|
          res << "    <tr>\n"
          row_cells.sort_by { |c| c[:c] }.each do |cell|
            tag = cell[:is_header] ? "th" : "td"
            attrs = []
            attrs << "colspan=\"#{cell[:cs]}\"" if cell[:cs] > 1
            attrs << "rowspan=\"#{cell[:rs]}\"" if cell[:rs] > 1
            attrs << "align=\"#{cell[:align]}\" valign=\"top\""

            if preserve_newlines
              content = cell[:text_lines].map(&:strip).drop_while(&:empty?)
                          .reverse.drop_while(&:empty?).reverse.join("<br>\n")
            else
              content = cell[:text_lines].map(&:strip).reject(&:empty?).join(" ")
            end

            if content.empty?
              res << "      <#{tag} #{attrs.join(' ')}></#{tag}>\n"
            elsif content.include?("<br>")
              res << "      <#{tag} #{attrs.join(' ')}>\n        #{content.gsub("\n", "\n        ")}</#{tag}>\n"
            else
              res << "      <#{tag} #{attrs.join(' ')}>#{content}</#{tag}>\n"
            end
          end
          res << "    </tr>\n"
        end
        res
      }

      html << "  <thead>\n#{build_tbody.call(cells.select { |c| c[:is_header] })}  </thead>\n" if cells.any? { |c| c[:is_header] }
      html << "  <tbody>\n#{build_tbody.call(cells.reject { |c| c[:is_header] })}  </tbody>\n</table>"
      "\n#+BEGIN_HTML\n#{html}\n#+END_HTML\n"
    end
  end
end

Liquid::Template.register_filter(Jekyll::OrgifyFilter)

Jekyll::Hooks.register [:pages, :documents], :pre_render do |doc|
  # Enable Liquid syntax
  if doc.extname.downcase == '.org'
    if doc.data['heading_ids'] == 'topdown'
      doc.content = "%%HEADING_IDS:topdown%%\n" + doc.content
    end

    # Safely encode {% raw %} blocks to bypass Jekyll's buggy excerpt generator
    doc.content = doc.content.gsub(/\{%[ \t]*raw[ \t]*%\}(.*?)\{%[ \t]*endraw[ \t]*%\}/m) do
      ::Regexp.last_match(1).gsub('{%', '@@L_OPEN@@').gsub('%}', '@@L_CLOSE@@')
        .gsub('{{', '@@L_OUT_OPEN@@').gsub('}}', '@@L_OUT_CLOSE@@')
    end
    block_regex = /(?mi:^[ \t]*#\+(?:begin_src|BEGIN_HTML).*?^[ \t]*#\+(?:end_src|END_HTML))/
    include_regex = /^[ \t]*(\{%[ \t]*include[ \t]+(?:figure|gallery)(?:(?!%\}).|\{%.*?%\})*%\})[ \t]*$/m

    # Notices for block contents
    div_open_regex = /(?i:^[ \t]*<div[^>]+(?:markdown|org)="1"[^>]*>[ \t]*$)/
    div_close_regex = /(?i:^[ \t]*<\/div>[ \t]*$)/
    orgify_block_regex = /(?mi:^[ \t]*<div[^>]*>(?:(?!<\/div>).)*?\{\{[^}]*\|[ \t]*orgify[ \t]*\}\}(?:(?!<\/div>).)*?<\/div>[ \t]*$)/

    # Advanced Tables
    emacs_table_regex = /^(?:[ \t]*#\+ATTR_ARGS:.*?\r?\n)?[ \t]*\+[-=+]+\+[ \t]*\r?\n(?:^[ \t]*[+|].*?\r?\n)*^[ \t]*\+[-=+]+\+[ \t]*(?=\r?\n|\z)/i
    org_complex_regex = /^[ \t]*#\+ATTR_ARGS:.*?:complex[ \t]+t\b.*?\r?\n(?:^[ \t]*\|.*?\r?\n)*^[ \t]*\|.*?(?=\r?\n|\z)/i

    # Enable figures, galleries, and links to posts (skip inside code or raw blocks)
    depth = 0
    doc.content = doc.content.gsub(/#{block_regex}|#{include_regex}|#{orgify_block_regex}|#{div_open_regex}|#{div_close_regex}|#{emacs_table_regex}|#{org_complex_regex}/) do |match|
      if match.match?(/\A[ \t]*#\+(?:begin_src|BEGIN_HTML)/i)
        match
      elsif match.match?(/\A(?:[ \t]*#\+ATTR_ARGS:.*?\r?\n)?[ \t]*\+[-=+]+\+/i)
        Jekyll::OrgAdvancedTables.generate_html_table(match, :emacs)
      elsif match.match?(/\A[ \t]*#\+ATTR_ARGS:.*?:complex[ \t]+t\b/i)
        Jekyll::OrgAdvancedTables.generate_html_table(match, :org_complex)
      elsif match.match?(include_regex) || match.match?(orgify_block_regex)
        "\n#+BEGIN_HTML\n#{match.strip}\n#+END_HTML\n"
      elsif match.match?(div_open_regex)
        depth += 1
        tag = match.strip.gsub(/[ \t]*(?:markdown|org)="1"/i, '')
        "\n#+BEGIN_HTML\n#{tag}\n#+END_HTML\n"
      elsif match.match?(div_close_regex) && depth > 0
        depth -= 1
        "\n#+BEGIN_HTML\n</div>\n#+END_HTML\n"
      else
        match
      end
    end

    # Pre-process furigana to strip newlines and prevent org-ruby table corruption
    doc.content = doc.content.gsub(/#{block_regex}|#{MinimalMistakesPlus::FURIGANA_REGEX}/) do |match|
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

Jekyll::Hooks.register [:pages, :documents], :post_render do |doc|
  # Decode Liquid tags preserved from {% raw %} blocks
  if doc.output.include?('@@L_OPEN@@') || doc.output.include?('@@L_OUT_OPEN@@')
    doc.output = doc.output.gsub('@@L_OPEN@@', '{%').gsub('@@L_CLOSE@@', '%}').gsub('@@L_OUT_OPEN@@', '{{').gsub('@@L_OUT_CLOSE@@', '}}')
  end
end
