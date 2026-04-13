require 'nokogiri'

Jekyll::Hooks.register [:pages, :documents], :post_render do |doc|
  next unless doc.output.include?('@@FRGNTR_LIVE_CONVERTER')
  next unless doc.output_ext == '.html'

  html_doc = Nokogiri::HTML(doc.output)
  inject_live_script = false

  html_doc.xpath('.//text()[contains(., "@@FRGNTR_LIVE_CONVERTER|")]').each do |node|
    if node.content =~ /@@FRGNTR_LIVE_CONVERTER\|(.*?)@@/
      placeholder = $1
      payload = <<~HTML
        <div class="frgntr-live-converter" style="margin-bottom: 1.5em;">
          <textarea
            class="frgntr-live-input"
            placeholder="#{placeholder}"
            oninput="this.style.height = 'auto'; this.style.height = this.scrollHeight + 'px'"
          ></textarea>
          <div class="frgntr-live-status"></div>
          <div class="frgntr-live-output"></div>
        </div>
      HTML

      parent = node.parent
      if parent.name == 'p' && parent.text.strip == "@@FRGNTR_LIVE_CONVERTER|#{placeholder}@@"
        parent.replace(Nokogiri::HTML::DocumentFragment.parse(payload))
      else
        node.content = node.content.sub("@@FRGNTR_LIVE_CONVERTER|#{placeholder}@@", '')
        node.before(Nokogiri::HTML::DocumentFragment.parse(payload))
      end

      inject_live_script = true
    end
  end

  if inject_live_script
    baseurl = doc.site.config['baseurl'] || ""
    live_script_html = "<script src=\"#{baseurl}/assets/js/furigana_live.js\"></script>"
    body = html_doc.at_css('body')
    body.add_child(Nokogiri::HTML::DocumentFragment.parse(live_script_html)) if body
    doc.output = html_doc.to_html
  end
end
