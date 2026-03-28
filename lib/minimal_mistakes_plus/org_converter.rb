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
    # Pre-compiled Regex constants for ultra-fast matching in tight loops
    CJK_CHARS = "\\p{Han}\\p{Hiragana}\\p{Katakana}\\p{Hangul}，。、！？；：”’（）《》〈〉【】『』「」".freeze
    CJK_SPACE_REGEX = /([#{CJK_CHARS}])\s+(?=[#{CJK_CHARS}])/u.freeze
    BORDER_ONLY_REGEX = /^[|+=\-\s]+$/.freeze
    HORIZONTAL_RULE_REGEX = /^[-=+]+$/.freeze

    def self.generate_html_table(table_text, type)
      lines = table_text.lines.map { |line| line.chomp.sub(/^[ \t]+/, '') }

      preserve_newlines = false
      if lines.first&.match?(/#\+ATTR_ARGS:/i)
        preserve_newlines = !!lines.first.match?(/(?:^|\s):newlines[ \t]+t\b/i)
        lines.shift
      end

      lines.reject! { |line| line.strip.empty? }
      return "" if lines.empty?

      max_length = lines.map(&:length).max
      lines.map! { |line| line.ljust(max_length, ' ') }

      cells = if type == :org_complex
                parse_org_complex(lines, max_length)
              else
                parse_emacs(lines)
              end

      render_html(cells, preserve_newlines)
    end

    private

    # --- Parsers ---

    def self.parse_org_complex(lines, max_length)
      cells = []

      # 1. Convert text lines into a 2D logical grid of cell segments
      raw_grid = lines.map do |line|
        if line.include?('|')
          is_separator = line.strip.match?(BORDER_ONLY_REGEX) && line.match?(/[-=]/)
          line = line.tr('+', '|') if is_separator

          segments = line.split('|', -1)
          segments.shift if segments.first && segments.first.strip.empty?
          segments.pop if segments.last && segments.last.strip.empty?
          segments
        else
          []
        end
      end

      raw_grid.reject!(&:empty?)
      return cells if raw_grid.empty?

      # 2. Equalize columns to form a perfect box
      columns_count = raw_grid.map(&:size).max
      raw_grid.each { |row| row << " " while row.size < columns_count }

      # 3. Ensure top and bottom borders exist for logical boundary calculation
      separator_row = Array.new(columns_count, "---")
      raw_grid.unshift(separator_row.dup) unless raw_grid.first.all? { |col| col.strip.match?(HORIZONTAL_RULE_REGEX) }
      raw_grid.push(separator_row.dup) unless raw_grid.last.all? { |col| col.strip.match?(HORIZONTAL_RULE_REGEX) }

      # 4. Identify rows that serve as horizontal borders
      logical_boundaries = []
      raw_grid.each_with_index do |row, y_index|
        logical_boundaries << y_index if row.any? { |col| col.strip.match?(HORIZONTAL_RULE_REGEX) }
      end

      visited_cells = Array.new(logical_boundaries.size - 1) { Array.new(columns_count, false) }

      # 5. Traverse the logical boundaries to construct cells and calculate row spans
      (0...logical_boundaries.size - 1).each do |row_idx|
        (0...columns_count).each do |col_idx|
          next if visited_cells[row_idx][col_idx]

          row_span = 1
          while row_idx + row_span < logical_boundaries.size - 1
            boundary_y = logical_boundaries[row_idx + row_span]
            break if raw_grid[boundary_y][col_idx].strip.match?(HORIZONTAL_RULE_REGEX)
            row_span += 1
          end

          (0...row_span).each { |dr| visited_cells[row_idx + dr][col_idx] = true }

          # Extract internal text for the current cell box
          text_lines = []
          y_start = logical_boundaries[row_idx] + 1
          y_end = logical_boundaries[row_idx + row_span] - 1
          (y_start..y_end).each { |yy| text_lines << raw_grid[yy][col_idx] }

          cells << {
            row_index: row_idx,
            col_index: col_idx,
            row_span: row_span,
            col_span: 1,
            text_lines: text_lines,
            align: determine_alignment(text_lines),
            is_header: (row_idx == 0)
          }
        end
      end

      merge_column_spans(cells)
    end

    def self.parse_emacs(lines)
      cells = []

      # 1. Determine vertical column boundaries by finding '+' in the first line
      grid_x = lines.first.enum_for(:scan, /\+/).map { Regexp.last_match.begin(0) }

      # 2. Determine horizontal row boundaries
      grid_y = []
      lines.each_with_index do |line, i|
        is_boundary = (0...grid_x.size - 1).any? do |col_idx|
          left_char = line[grid_x[col_idx]]
          right_char = line[grid_x[col_idx + 1]]
          if (left_char == '+' || left_char == '|') && (right_char == '+' || right_char == '|')
            segment = line[(grid_x[col_idx] + 1)...grid_x[col_idx + 1]]
            segment && !segment.strip.empty? && segment.strip.match?(HORIZONTAL_RULE_REGEX)
          else
            false
          end
        end
        grid_y << i if is_boundary
      end

      visited_cells = Array.new(grid_y.size - 1) { Array.new(grid_x.size - 1, false) }

      # 3. Traverse the identified boundaries to map cells
      (0...grid_y.size - 1).each do |row_idx|
        (0...grid_x.size - 1).each do |col_idx|
          next if visited_cells[row_idx][col_idx]

          # Calculate column span by reading across
          col_span = 1
          while col_idx + col_span < grid_x.size - 1
            y_check = grid_y[row_idx] + 1
            y_check = grid_y[row_idx] if y_check == grid_y[row_idx + 1]
            char = lines[y_check][grid_x[col_idx + col_span]]
            break if char == '|' || char == '+'
            col_span += 1
          end

          # Calculate row span by reading downwards
          row_span = 1
          while row_idx + row_span < grid_y.size - 1
            segment = lines[grid_y[row_idx + row_span]][(grid_x[col_idx] + 1)...(grid_x[col_idx + col_span])]
            break if segment && !segment.strip.empty? && segment.strip.match?(HORIZONTAL_RULE_REGEX)
            row_span += 1
          end

          # Mark the spanned area as visited
          (row_idx...row_idx + row_span).each do |vr|
            (col_idx...col_idx + col_span).each { |vc| visited_cells[vr][vc] = true }
          end

          # Extract internal text for the current cell box
          text_lines = ((grid_y[row_idx] + 1)...grid_y[row_idx + row_span]).map do |yy|
            lines[yy][(grid_x[col_idx] + 1)...grid_x[col_idx + col_span]]
          end

          cells << {
            row_index: row_idx,
            col_index: col_idx,
            row_span: row_span,
            col_span: col_span,
            text_lines: text_lines,
            align: determine_alignment(text_lines),
            is_header: (row_idx == 0 && lines[grid_y[1]].include?('='))
          }
        end
      end

      cells
    end

    # --- Helpers ---

    def self.determine_alignment(text_lines)
      align = "left"
      if (first_text = text_lines.find { |l| !l.strip.empty? })
        left_spaces = first_text[/\A\s*/].length
        right_spaces = first_text[/\s*\z/].length
        align = "center" if left_spaces > 1 && right_spaces > 1
        align = "right" if left_spaces > 1 && right_spaces <= 1
      end
      align
    end

    def self.merge_column_spans(cells)
      merged_cells = []
      cells.group_by { |cell| cell[:row_index] }.each do |_, row_cells|
        index = 0
        while index < row_cells.size
          current_cell = row_cells[index]

          # Check if the cell acts as a <span ... > start marker
          if current_cell[:text_lines].map(&:strip).join("").start_with?("<span")
            total_col_span = current_cell[:col_span]
            index += 1

            # Traverse subsequent cells until the closing '>' is found
            while index < row_cells.size
              next_cell = row_cells[index]
              total_col_span += next_cell[:col_span]
              break if next_cell[:text_lines].map(&:strip).join("") == ">"
              index += 1
            end

            current_cell[:col_span] = total_col_span
            current_cell[:text_lines] = []
          end

          merged_cells << current_cell
          index += 1
        end
      end
      merged_cells
    end

    # --- HTML Rendering ---

    def self.render_html(cells, preserve_newlines)
      html = "<table>\n"

      header_cells = cells.select { |c| c[:is_header] }
      body_cells = cells.reject { |c| c[:is_header] }

      html << "  <thead>\n#{build_tbody_html(header_cells, preserve_newlines)}  </thead>\n" unless header_cells.empty?
      html << "  <tbody>\n#{build_tbody_html(body_cells, preserve_newlines)}  </tbody>\n</table>"

      "\n#+BEGIN_HTML\n#{html}\n#+END_HTML\n"
    end

    def self.build_tbody_html(cell_group, preserve_newlines)
      return "" if cell_group.empty?

      result = ""
      cell_group.group_by { |c| c[:row_index] }.each do |_, row_cells|
        result << "    <tr>\n"
        row_cells.sort_by { |c| c[:col_index] }.each do |cell|
          tag = cell[:is_header] ? "th" : "td"
          attrs = []
          attrs << "colspan=\"#{cell[:col_span]}\"" if cell[:col_span] > 1
          attrs << "rowspan=\"#{cell[:row_span]}\"" if cell[:row_span] > 1
          attrs << "align=\"#{cell[:align]}\" valign=\"top\""

          content = process_cell_content(cell[:text_lines], preserve_newlines)

          if content.empty?
            result << "      <#{tag} #{attrs.join(' ')}></#{tag}>\n"
          elsif content.include?("<br>")
            result << "      <#{tag} #{attrs.join(' ')}>\n        #{content.gsub("\n", "\n        ")}</#{tag}>\n"
          else
            result << "      <#{tag} #{attrs.join(' ')}>#{content}</#{tag}>\n"
          end
        end
        result << "    </tr>\n"
      end
      result
    end

    def self.process_cell_content(text_lines, preserve_newlines)
      if preserve_newlines
        text_lines.map(&:strip).drop_while(&:empty?).reverse.drop_while(&:empty?).reverse.join("<br>\n")
      else
        content = text_lines.map(&:strip).reject(&:empty?).join(" ")
        content.gsub(CJK_SPACE_REGEX, '\1')
      end
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
