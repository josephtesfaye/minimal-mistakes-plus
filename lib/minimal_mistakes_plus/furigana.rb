require "nokogiri"
require "json"
require "open3"

module MinimalMistakesPlus
  # Regular expression to capture the （Base：Ruby） format, including newlines
  # (using the 'm' modifier to match across newlines)
  FURIGANA_REGEX = /（([^（）：]+?)：([^（）：]+?)）/m
  CJK_CHARS = "\\p{Han}\\p{Hiragana}\\p{Katakana}\\p{Hangul}，。、！？；：”’（）《》〈〉【】『』「」".freeze
  CJK_SPACE_REGEX = /(?:([#{CJK_CHARS}])\s+(?=[#{CJK_CHARS}\d])|(\d)\s+(?=[#{CJK_CHARS}]))/u.freeze

  module Furigana
    # --- Daemon Process Manager ---
    # Keeps a single Node.js instance alive during the entire Jekyll build
    # to guarantee ultra-fast parsing without dictionary reload latency.
    class KuroshiroWorker
      def self.instance
        @instance ||= new
      end

      def initialize
        @disabled = false
        script_path = File.join(File.dirname(__FILE__), 'kuroshiro_worker.js')

        unless File.exist?(script_path)
          Jekyll.logger.warn "Furigana:", "kuroshiro_worker.js not found at #{script_path}. Auto-parsing disabled."
          @disabled = true
          return
        end

        # Auto-install Node dependencies if missing (e.g., in GitHub Actions or fresh gem install)
        unless Dir.exist?(File.join(File.dirname(__FILE__), 'node_modules'))
          Jekyll.logger.info "Furigana:", "Installing Node.js dependencies. This may take a moment..."
          system("npm install", chdir: File.dirname(__FILE__))
        end

        @stdin, @stdout, @stderr, @wait_thr = Open3.popen3("node #{script_path}")

        # Block until Kuromoji dictionaries are fully loaded
        ready = @stdout.gets
        unless ready && ready.strip == "READY"
          Jekyll.logger.error "Furigana:", "Worker failed to start: #{@stderr.read}"
          @disabled = true
        end
      end

      def convert(jobs)
        return {} if @disabled || jobs.empty?

        # Dispatch to Node.js
        @stdin.puts(jobs.to_json)
        result_line = @stdout.gets

        return {} unless result_line
        parsed = JSON.parse(result_line)

        if parsed['error']
          Jekyll.logger.error "Furigana Node Error:", parsed['error']
          return {}
        end

        parsed
      end

      def stop
        @stdin.close if @stdin && !@stdin.closed?
        begin
          Process.kill("TERM", @wait_thr.pid) if @wait_thr
        rescue Errno::ESRCH
          # Process already dead, ignore
        end
      end
    end

    def self.process(doc)
      ext = doc.extname.downcase
      return unless %w[.org .md .markdown .mkd].include?(ext)

      html_doc = Nokogiri::HTML(doc.output)
      modified = false

      # Global cleanup: Strip Kramdown line-wrapping newlines between CJK characters and numbers
      html_doc.xpath('.//text()[not(ancestor::pre or ancestor::code)]').each do |node|
        if node.content.match?(CJK_SPACE_REGEX)
          node.content = node.content.gsub(CJK_SPACE_REGEX, '\1\2')
          modified = true
        end
      end

      furigana_enabled = doc.data['furigana'] == true || doc.data['furigana'] == 'true'

      # -----------------------------------------------------------------------
      # Scenario A: Furigana is globally turned OFF
      # -----------------------------------------------------------------------
      if !furigana_enabled
        html_doc.css('[furigana_mode], [furigana_selectable], [furigana_mouse_over]').each do |node|
          node.remove_attribute('furigana_mode')
          node.remove_attribute('furigana_selectable')
          node.remove_attribute('furigana_mouse_over')
          modified = true
        end

        html_doc.xpath('.//text()[not(ancestor::pre or ancestor::code)]').each do |node|
          text = node.content
          changed = false

          if text =~ /\{:.*furigana_/
            text.gsub!(/furigana_(?:mode|selectable|mouse_over)\s*=\s*["'“”‘’]?(?:hiragana|katakana|romaji|true|false)["'“”‘’]?/i, '')
            text.gsub!(/\{:\s*\}/, '')
            changed = true
          end

          if text.match?(FURIGANA_REGEX)
            text = text.gsub(FURIGANA_REGEX) do
              ::Regexp.last_match(1).gsub(/[\r\n]+/, "").delete("｜")
            end
            changed = true
          end

          if changed
            node.content = text
            modified = true
          end
        end
        doc.output = html_doc.to_html if modified
        return
      end

      # -----------------------------------------------------------------------
      # Scenario B: Furigana is globally turned ON
      # -----------------------------------------------------------------------
      global_mode = doc.data['furigana_mode'] || 'hiragana'
      f_selectable = doc.data['furigana_selectable'] == true || doc.data['furigana_selectable'] == 'true'
      f_hover = doc.data['furigana_mouse_over'] == true || doc.data['furigana_mouse_over'] == 'true'

      translate_enabled = doc.data['translate'] == true || doc.data['translate'] == 'true'
      translate_targets = doc.data['translate_targets'] || []
      translate_targets = [translate_targets] if translate_targets.is_a?(String)

      if furigana_enabled
        global_buttons = []

        mode_html = <<~HTML
          <div class="frgntr-dropdown" style="position: relative; display: inline-flex; align-items: center;">
            <i class="fas fa-language frgntr-icon" id="frgntr-mode-btn" title="Converter Mode" onclick="frgntrToggleDropdown(this)"></i>
            <div class="frgntr-dropdown-menu" id="frgntr-mode-menu">
              <div class="frgntr-dropdown-item active" data-mode="hiragana" data-icon="fa-language" onclick="frgntrSelectMode(this)">Hiragana</div>
              <div class="frgntr-dropdown-item" data-mode="katakana" data-icon="fa-font" onclick="frgntrSelectMode(this)">Katakana</div>
              <div class="frgntr-dropdown-item" data-mode="romaji" data-icon="fa-italic" onclick="frgntrSelectMode(this)">Romaji</div>
              <div class="frgntr-dropdown-item" data-mode="pattern" data-icon="fa-code" onclick="frgntrSelectMode(this)">Pattern</div>
            </div>
          </div>
        HTML
        global_buttons << mode_html

        trans_buttons = []
        default_code = 'off'

        if translate_enabled && !translate_targets.empty?
          lang_map = {
            'english' => 'en', 'chinese' => 'zh-CN', 'spanish' => 'es', 'french' => 'fr',
            'korean' => 'ko', 'german' => 'de', 'russian' => 'ru'
          }

          icon_map = {
            'english' => 'fa-font', 'chinese' => 'fa-language', 'spanish' => 'fa-globe-americas',
            'french' => 'fa-globe-europe', 'korean' => 'fa-comment-dots', 'german' => 'fa-comment-alt',
            'russian' => 'fa-comment'
          }

          default_target = translate_targets.first
          default_code = lang_map[default_target.downcase] || default_target.downcase
          default_icon = icon_map[default_target.downcase] || 'fa-globe'

          items_html = translate_targets.map do |t|
            code = lang_map[t.downcase] || t.downcase
            icon = icon_map[t.downcase] || 'fa-globe'
            active_class = (t == default_target) ? ' active' : ''
            "<div class=\"frgntr-dropdown-item#{active_class}\" data-target=\"#{code}\" data-icon=\"#{icon}\" onclick=\"frgntrSelectTranslation(this)\">#{t}</div>"
          end.join('')

          trans_html = <<~HTML
            <div class="frgntr-dropdown" style="position: relative; display: inline-flex; align-items: center;">
              <i class="fas #{default_icon} frgntr-icon" id="frgntr-trans-btn" title="Live Translation" onclick="frgntrToggleTransDropdown(this)"></i>
              <div class="frgntr-dropdown-menu" id="frgntr-trans-menu">
              <div class="frgntr-dropdown-item" data-target="off" data-icon="fa-comment-slash" onclick="frgntrSelectTranslation(this)">Off</div>
                #{items_html}
              </div>
            </div>
          HTML
          trans_buttons << trans_html
        end

        icon_hover = f_hover ? 'fa-eye-slash' : 'fa-eye'
        global_buttons << "<i class=\"fas #{icon_hover} frgntr-icon\" title=\"Toggle Visibility (Hover Mode)\" onclick=\"frgntrToggleGlobalHover(this)\"></i>"

        icon_selectable = f_selectable ? 'fa-unlock' : 'fa-lock'
        global_buttons << "<i class=\"fas #{icon_selectable} frgntr-icon\" title=\"Toggle Selectability\" onclick=\"frgntrToggleGlobalSelectable(this)\"></i>"

        all_buttons = trans_buttons + global_buttons
        row_style = "display: flex; justify-content: flex-start; align-items: center;"
        toolbar_html = "<header><h4 class=\"nav__title\"><i class=\"fas fa-tools\"></i> Tools</h4></header><div class=\"frgntr-global-toolbar\"><div class=\"frgntr-toolbar-row\" style=\"#{row_style}\"><div class=\"frgntr-icon-group\">#{all_buttons.join(' ')}</div></div></div>"

        sidebar_toc = html_doc.at_css('.sidebar__right.sticky .toc')
        if sidebar_toc
          sidebar_toc.prepend_child(toolbar_html)
        else
          sidebar_right = html_doc.at_css('.sidebar__right.sticky')
          if sidebar_right
            sidebar_right.prepend_child("<nav class=\"toc\">#{toolbar_html}</nav>")
          else
            page_content = html_doc.at_css('.page__content')
            if page_content
              page_content.prepend_child("<aside class=\"sidebar__right sticky\"><nav class=\"toc\">#{toolbar_html}</nav></aside>")
            end
          end
        end
        modified = true
      end

      blocks = html_doc.css('p, li, h1, h2, h3, h4, h5, h6, td, th')
      jobs = []

      blocks.each_with_index do |block, idx|
        next if block.ancestors('pre, code').any?

        mode = global_mode
        b_selectable = f_selectable
        b_hover = f_hover
        has_selectable_override = false
        has_hover_override = false

        # Check if Kramdown already parsed it into an HTML attribute on the block element
        if block['furigana_mode'] && %w[hiragana katakana romaji].include?(block['furigana_mode'].downcase)
          mode = block['furigana_mode'].downcase
          block.remove_attribute('furigana_mode')
        end
        if block.key?('furigana_selectable')
          b_selectable = block['furigana_selectable'].downcase == 'true'
          has_selectable_override = true
          block.remove_attribute('furigana_selectable')
        end
        if block.key?('furigana_mouse_over')
          b_hover = block['furigana_mouse_over'].downcase == 'true'
          has_hover_override = true
          block.remove_attribute('furigana_mouse_over')
        end

        # Check for raw attribute syntax left behind in text nodes (e.g., by org-ruby)
        # We account for Kramdown transforming quotes to smart quotes and loose spacing.
        block.xpath('.//text()[not(ancestor::pre or ancestor::code)]').each do |node|
          text = node.content
          if text =~ /\{:.*furigana_/
            if text =~ /furigana_mode\s*=\s*["'“”‘’]?(hiragana|katakana|romaji)["'“”‘’]?/i
              mode = $1.downcase
              text.gsub!(/furigana_mode\s*=\s*["'“”‘’]?(?:hiragana|katakana|romaji)["'“”‘’]?/i, '')
            end
            if text =~ /furigana_selectable\s*=\s*["'“”‘’]?(true|false)["'“”‘’]?/i
              b_selectable = $1.downcase == 'true'
              has_selectable_override = true
              text.gsub!(/furigana_selectable\s*=\s*["'“”‘’]?(?:true|false)["'“”‘’]?/i, '')
            end
            if text =~ /furigana_mouse_over\s*=\s*["'“”‘’]?(true|false)["'“”‘’]?/i
              b_hover = $1.downcase == 'true'
              has_hover_override = true
              text.gsub!(/furigana_mouse_over\s*=\s*["'“”‘’]?(?:true|false)["'“”‘’]?/i, '')
            end
            text.gsub!(/\{:\s*\}/, '')
            node.content = text
          end
        end

        b_classes = []
        b_classes << "frgntr_hidden" if b_hover
        b_classes << "frgntr_unselectable" unless b_selectable
        b_classes << "has-local-hover" if has_hover_override
        b_classes << "has-local-selectable" if has_selectable_override
        rt_class_attr = b_classes.empty? ? ' class=""' : " class=\"#{b_classes.join(' ')}\""

        buttons = []
        if has_hover_override
          icon = b_hover ? 'fa-eye-slash' : 'fa-eye'
          buttons << "<i class=\"fas #{icon} frgntr-icon\" title=\"Toggle Visibility (Hover Mode)\" onclick=\"frgntrToggleLocalHover(this)\"></i>"
        end
        if has_selectable_override
          icon = b_selectable ? 'fa-unlock' : 'fa-lock'
          buttons << "<i class=\"fas #{icon} frgntr-icon\" title=\"Toggle Selectability\" onclick=\"frgntrToggleLocalSelectable(this)\"></i>"
        end

        # 1. Process Manual Priorities (Takes precedence, skipped by Kuroshiro)
        block.xpath('.//text()[not(ancestor::pre or ancestor::code)]').each do |node|
          if node.content.match?(FURIGANA_REGEX)
            new_html = node.content.gsub(FURIGANA_REGEX) do
              raw_base = ::Regexp.last_match(1)
              raw_ruby = ::Regexp.last_match(2)
              clean_base = raw_base.gsub(/[\r\n]+/, "")
              clean_ruby = raw_ruby.gsub(/[\r\n]+/, "")
              bases, rubies = clean_base.split("｜"), clean_ruby.split("｜")

              if bases.length == rubies.length
                ruby_content = bases.zip(rubies).map { |b, r| "#{b}<rp>(</rp><rt#{rt_class_attr}>#{r}</rt><rp>)</rp>" }.join("")
                "<ruby furiganated=\"true\" data-manual=\"true\">#{ruby_content}</ruby>"
              else
                base_f, ruby_f = clean_base.delete("｜"), clean_ruby.delete("｜")
                "<ruby furiganated=\"true\" data-manual=\"true\">#{base_f}<rp>(</rp><rt#{rt_class_attr}>#{ruby_f}</rt><rp>)</rp></ruby>"
              end
            end
            node.replace(Nokogiri::HTML::DocumentFragment.parse(new_html))
          end
        end

        # 2. Extract code blocks and manual rubies, swap for placeholders to protect them from Node.js
        placeholders = {}
        block.css('code, pre, ruby[data-manual="true"]').each_with_index do |node, c_idx|
          token = "@@PROTECTED_#{c_idx}@@"
          placeholders[token] = node.to_html
          node.replace(token)
        end

        if buttons.any?
          ctrl_token = "@@CONTROLS_#{idx}@@"
          placeholders[ctrl_token] = "<span class=\"frgntr-local-controls\">#{buttons.join(' ')}</span>"
          block.inner_html = ctrl_token + block.inner_html
        end

        # Only queue if there's actual text remaining
        if block.inner_html.strip.length > 0
          jobs << { id: idx, text: block.inner_html, mode: mode, placeholders: placeholders, rt_class_attr: rt_class_attr }
        end
      end

      # 3. Batch run automatic parsing via Node.js worker
      unless jobs.empty?
        results = KuroshiroWorker.instance.convert(jobs)

        jobs.each do |job|
          res_html = results[job[:id].to_s]
          next unless res_html

          # Strip the <ruby> tags whenever the base text perfectly matches the reading text
          res_html.gsub!(/<ruby>([^<]+)<rp>\(<\/rp><rt>\1<\/rt><rp>\)<\/rp><\/ruby>/, '\1')

          # 4. Inject specific HTML attributes to match Furiganator format exactly.
          # Note: Kuroshiro skips modifying our <ruby data-manual="true"> blocks,
          # so replacing basic <ruby> explicitly targets only the auto-generated ones.
          res_html.gsub!('<ruby>', '<ruby furiganated="true">')
          res_html.gsub!('<rp>(</rp><rt>', "<rp>(</rp><rt#{job[:rt_class_attr]}>")

          # Restore protected code blocks and manual rubies
          job[:placeholders].each { |token, orig_html| res_html.gsub!(token) { orig_html } }

          res_html.gsub!(' data-manual="true"', '') # Clean up temp property AFTER restoration
          if blocks[job[:id]].inner_html != res_html
            blocks[job[:id]].inner_html = res_html
            modified = true
          end
        end
      end

      if modified
        baseurl = doc.site.config['baseurl'] || ""
        script_html = <<~HTML
          <script>window.frgntrLiveTransTarget = '#{default_code}';</script>
          <script src="#{baseurl}/assets/js/furigana_global.js"></script>
        HTML
        body = html_doc.at_css('body')
        body.add_child(Nokogiri::HTML::DocumentFragment.parse(script_html)) if body
      end
      doc.output = html_doc.to_html if modified
    end
  end
end

Jekyll::Hooks.register [:pages, :documents], :post_render do |doc|
  next unless doc.output_ext == '.html'
  MinimalMistakesPlus::Furigana.process(doc)
end

# Register the JS file to be automatically copied to _site/assets/js/
Jekyll::Hooks.register :site, :post_read do |site|
  gem_dir = File.expand_path("../../", __dir__)
  site.static_files << Jekyll::StaticFile.new(site, gem_dir, 'assets/js', 'furigana_global.js')
  site.static_files << Jekyll::StaticFile.new(site, gem_dir, 'assets/js', 'furigana_live.js')
end
