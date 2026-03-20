# frozen_string_literal: true

require "addressable/uri"

module MinimalMistakesPlus
  # Processes link abbreviations in Org and Markdown files
  module LinkAbbr
    def self.process(doc)
      ext = doc.extname.downcase

      if ext == ".org"
        process_org(doc)
      elsif %w[.md .markdown .mkd].include?(ext)
        process_md(doc)
      end
    end

    def self.process_org(doc)
      abbrs = gather_org_abbrs(doc).merge(gather_common_abbrs(doc))
      return if abbrs.empty?

      keys_regex = Regexp.union(abbrs.keys.map { |k| Regexp.escape(k) })
      placeholders = {}
      counter = 0

      counter = protect_common_literals(doc, placeholders, counter)
      protect_org_literals(doc, placeholders, counter)

      expand_org_links(doc, abbrs, keys_regex)
      expand_liquid_attributes(doc, abbrs, keys_regex)
      restore_literals(doc, placeholders)
      process_org_front_matter(doc, abbrs, keys_regex)
    end

    def self.process_md(doc)
      abbrs = gather_common_abbrs(doc)
      return if abbrs.empty?

      keys_regex = Regexp.union(abbrs.keys.map { |k| Regexp.escape(k) })
      placeholders = {}
      counter = 0

      counter = protect_common_literals(doc, placeholders, counter)
      protect_md_literals(doc, placeholders, counter)

      # Expand links
      expand_md_links(doc, abbrs, keys_regex)
      expand_liquid_attributes(doc, abbrs, keys_regex)
      restore_literals(doc, placeholders)
      process_md_front_matter(doc, abbrs, keys_regex)
    end

    # --- 1. GATHERING ABBREVIATIONS ---

    def self.gather_common_abbrs(doc)
      abbrs = {}
      if doc.data["link_abbrs"].is_a?(Array)
        doc.data["link_abbrs"].each do |item|
          next unless item.is_a?(Hash) && item["link_abbr"]

          k, url = item["link_abbr"].split(" ", 2)
          abbrs[k] = url.strip if k && url
        end
      end
      abbrs
    end

    def self.gather_org_abbrs(doc)
      abbrs = {}
      doc.content.scan(/^[ \t]*#\+LINK:[ \t]+(\S+)[ \t]+(.*)$/i).each do |match|
        k = match[0]
        url = match[1].strip
        abbrs[k] ||= url unless url.empty?
      end
      abbrs
    end

    def self.build_full_url(base_url, path, inject_liquid: true)
      escaped_path = Addressable::URI.escape(base_url + path)
      if inject_liquid
        prefix = base_url.start_with?("/assets") ? "{{ site.url }}{{ site.baseurl }}" : ""
        "#{prefix}#{escaped_path}"
      else
        escaped_path
      end
    end

    # --- 2. PROTECTING LITERAL BLOCKS ---

    def self.protect_common_literals(doc, placeholders, counter)
      doc.content = doc.content.gsub(/\{%\s*raw\s*%\}.*?\{%\s*endraw\s*%\}/m) do |m|
        p = "@@LIT_#{counter += 1}@@"
        placeholders[p] = m
        p
      end

      doc.content = doc.content.gsub(/\{%\s*highlight\s+.*?%\}.*?\{%\s*endhighlight\s*%\}/m) do |m|
        p = "@@LIT_#{counter += 1}@@"
        placeholders[p] = m
        p
      end
      counter
    end

    def self.protect_org_literals(doc, placeholders, counter)
      doc.content = doc.content.gsub(/^[ \t]*#\+begin_(src|example|export)\b.*?^[ \t]*#\+end_\1\b/im) do |m|
        p = "@@LIT_#{counter += 1}@@"
        placeholders[p] = m
        p
      end

      doc.content = doc.content.gsub(/(^|[\s({\['"])(~|=)([^\n]+?)\2([\s)}\]'".,?:;]|$)/) do
        before = ::Regexp.last_match(1)
        marker = ::Regexp.last_match(2)
        text = ::Regexp.last_match(3)
        after = ::Regexp.last_match(4)
        p = "@@LIT_#{counter += 1}@@"
        placeholders[p] = "#{marker}#{text}#{marker}"
        "#{before}#{p}#{after}"
      end
      counter
    end

    def self.protect_md_literals(doc, placeholders, counter)
      doc.content = doc.content.gsub(/^[ \t]*(`{3,}|~{3,}).*?^[ \t]*\1/m) do |m|
        p = "@@LIT_#{counter += 1}@@"
        placeholders[p] = m
        p
      end

      doc.content = doc.content.gsub(/`[^`\n]+`/) do |m|
        p = "@@LIT_#{counter += 1}@@"
        placeholders[p] = m
        p
      end
      counter
    end

    def self.expand_org_links(doc, abbrs, keys_regex)
      doc.content = doc.content.gsub(/\[\[(#{keys_regex}):([^\]]+)(\]\[.*?\]\]|\]\])/) do
        "[[#{build_full_url(abbrs[::Regexp.last_match(1)], ::Regexp.last_match(2))}#{::Regexp.last_match(3)}"
      end
    end

    def self.expand_md_links(doc, abbrs, keys_regex)
      doc.content = doc.content.gsub(/\]\((#{keys_regex}):([^)]+)\)/) do
        "](#{build_full_url(abbrs[::Regexp.last_match(1)], ::Regexp.last_match(2))})"
      end
    end

    def self.expand_liquid_attributes(doc, abbrs, keys_regex)
      doc.content = doc.content.gsub(/(image_path|url)="(#{keys_regex}):([^"]+)"/) do
        "#{::Regexp.last_match(1)}=\"#{build_full_url(abbrs[::Regexp.last_match(2)], ::Regexp.last_match(3), inject_liquid: false)}\""
      end
    end

    def self.restore_literals(doc, placeholders)
      placeholders.each do |p, text|
        doc.content = doc.content.gsub(p, text)
      end
    end

    # --- 4. PROCESSING FRONT MATTER ---

    def self.process_org_front_matter(doc, abbrs, keys_regex)
      doc.data.each do |_, value|
        next unless value.is_a?(Array)

        value.map! do |raw_item|
          is_org_link_format = (raw_item.is_a?(Array) && raw_item.size == 1 &&
                                raw_item.first.is_a?(Array)) ||
                               (raw_item.is_a?(String) && raw_item.start_with?("[[") &&
                                raw_item.end_with?("]]"))

          item = is_org_link_format && raw_item.is_a?(Array) ?
                   raw_item.first.first.to_s : raw_item

          if item.is_a?(Hash)
            %w[url image_path].each do |attr|
              next unless item[attr]

              val = item[attr].is_a?(Array) ? item[attr].first.first.to_s : item[attr].to_s
              val_clean = val.sub(/^\[\[(.*)\]\]$/, '\\1')

              if val_clean =~ /^(#{keys_regex}):(.*)$/
                # FIX: Never re-wrap URL fields to prevent Addressable::URI crashes in Liquid
                item[attr] = build_full_url(abbrs[::Regexp.last_match(1)], ::Regexp.last_match(2), inject_liquid: false)
              end
            end

            if item["title"]
              item["title"] = item["title"].to_s.gsub(/\[\[(#{keys_regex}):([^\]]+)(\]\[.*?\]\]|\]\])/) do
                "[[#{build_full_url(abbrs[::Regexp.last_match(1)], ::Regexp.last_match(2))}#{::Regexp.last_match(3)}"
              end
            end

            item
          elsif item.is_a?(String)
            val_clean = item.sub(/^\[\[(.*)\]\]$/, '\\1')
            if val_clean =~ /^(#{keys_regex}):(.*)$/
              # FIX: Never re-wrap raw URL strings to prevent Addressable::URI crashes in Liquid
              build_full_url(abbrs[::Regexp.last_match(1)], ::Regexp.last_match(2), inject_liquid: false)
            else
              raw_item
            end
          else
            raw_item
          end
        end
      end
    end

    def self.process_md_front_matter(doc, abbrs, keys_regex)
      doc.data.each do |_, value|
        next unless value.is_a?(Array)

        value.map! do |raw_item|
          is_org_link_format = (raw_item.is_a?(Array) && raw_item.size == 1 &&
                                raw_item.first.is_a?(Array)) ||
                               (raw_item.is_a?(String) && raw_item.start_with?("[[") &&
                                raw_item.end_with?("]]"))

          # Strictly bypass Org-formatted links located in Markdown files
          next raw_item if is_org_link_format

          item = raw_item

          if item.is_a?(Hash)
            %w[url image_path].each do |attr|
              next unless item[attr]

              val = item[attr].to_s
              if val =~ /^(#{keys_regex}):(.*)$/
                item[attr] = build_full_url(abbrs[::Regexp.last_match(1)], ::Regexp.last_match(2), inject_liquid: false)
              end
            end

            if item["title"]
              item["title"] = item["title"].to_s.gsub(/\]\((#{keys_regex}):([^)]+)\)/) do
                "](#{build_full_url(abbrs[::Regexp.last_match(1)], ::Regexp.last_match(2))})"
              end
            end

            item
          elsif item.is_a?(String)
            if item =~ /^(#{keys_regex}):(.*)$/
              build_full_url(abbrs[::Regexp.last_match(1)], ::Regexp.last_match(2), inject_liquid: false)
            else
              raw_item
            end
          else
            raw_item
          end
        end
      end
    end
  end
end

Jekyll::Hooks.register [:pages, :documents], :pre_render do |doc|
  MinimalMistakesPlus::LinkAbbr.process(doc)
end
