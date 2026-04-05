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
    live_script_html = <<~JS
      <script>
        if (typeof window.frgntrLiveInitialized === 'undefined') {
          window.frgntrLiveInitialized = true;

          const loadScript = (src) => new Promise((resolve, reject) => {
            const s = document.createElement('script');
            s.src = src;
            s.onload = resolve;
            s.onerror = reject;
            document.head.appendChild(s);
          });

          let globalKuroshiro = null;
          let kuroshiroInitializing = false;

          async function getKuroshiroInstance(statusEl) {
            if (globalKuroshiro) return globalKuroshiro;
            if (kuroshiroInitializing) {
                let attempts = 0;
                while(kuroshiroInitializing && attempts < 150) {
                    await new Promise(r => setTimeout(r, 100));
                    attempts++;
                }
                return globalKuroshiro;

            }

            kuroshiroInitializing = true;
            if (statusEl) {
                statusEl.style.display = 'block';
                statusEl.innerText = "Loading dictionary engine...";
            }

            try {
              if (typeof window.Kuroshiro === 'undefined') {
                await loadScript("https://cdn.jsdelivr.net/npm/kuroshiro@1.1.2/dist/kuroshiro.min.js");
              }
              if (typeof window.KuromojiAnalyzer === 'undefined') {
                await loadScript("https://cdn.jsdelivr.net/npm/kuroshiro-analyzer-kuromoji@1.1.0/dist/kuroshiro-analyzer-kuromoji.min.js");
              }

              const KsClass = window.Kuroshiro.default || window.Kuroshiro;
              const AnalyzerClass = window.KuromojiAnalyzer.default || window.KuromojiAnalyzer;

              const ks = new KsClass();
              const analyzer = new AnalyzerClass({
                  dictPath: "https://cdn.jsdelivr.net/npm/kuromoji@0.1.2/dict/"
              });

              const initPromise = ks.init(analyzer);
              const timeoutPromise = new Promise((_, reject) => setTimeout(() => reject(new Error("Dictionary load timeout")), 15000));
              await Promise.race([initPromise, timeoutPromise]);

              globalKuroshiro = ks;
            } catch (e) {
              console.error("Furigana Live Converter Error:", e);
              if (statusEl) statusEl.innerText = "Error loading dictionary.";
            } finally {
              kuroshiroInitializing = false;
              if (statusEl && globalKuroshiro) {
                  statusEl.style.display = 'none';
              }
            }
            return globalKuroshiro;
          }

          document.addEventListener("DOMContentLoaded", () => {
            document.querySelectorAll('.frgntr-live-converter').forEach(container => {
              const input = container.querySelector('.frgntr-live-input');
              const output = container.querySelector('.frgntr-live-output');
              const status = container.querySelector('.frgntr-live-status');
              let timeout = null;

              input.addEventListener('focus', () => getKuroshiroInstance(status), { once: true });

              input.addEventListener('input', (e) => {
                clearTimeout(timeout);
                timeout = setTimeout(async () => {
                  const text = e.target.value;
                  if (!text.trim()) {
                    output.innerHTML = "";
                    return;
                  }

                  const ks = await getKuroshiroInstance(status);
                  if (!ks) return;

                  let html = await ks.convert(text, { mode: "furigana", to: "hiragana" });
                  const mode = window.frgntrLiveMode || "hiragana";

                  const parser = new DOMParser();
                  const doc = parser.parseFromString(html, 'text/html');

                  doc.querySelectorAll('ruby').forEach(ruby => {
                      const rt = ruby.querySelector('rt');
                      if (!rt) return;
                      let baseText = "";
                      ruby.childNodes.forEach(node => {
                          if (node.nodeType === Node.TEXT_NODE) baseText += node.textContent;
                      });
                      if (baseText.trim() === rt.textContent.trim()) {
                          ruby.replaceWith(baseText);
                      }
                  });

                  if (mode === "pattern") {
                    doc.querySelectorAll('ruby').forEach(ruby => {
                        const rt = ruby.querySelector('rt');
                        if (!rt) return;
                        const rtText = rt.textContent;
                        ruby.querySelectorAll('rp, rt').forEach(el => el.remove());
                        const baseText = ruby.textContent;
                        ruby.replaceWith(`（${baseText}：${rtText}）`);
                    });
                    output.innerHTML = doc.body.textContent.replace(/\\n/g, '<br>');
                    return;
                  }

                  if (mode === "katakana" || mode === "romaji") {
                      const rts = doc.querySelectorAll('rt');
                      const uniqueReadings = [...new Set(Array.from(rts).map(rt => rt.textContent))];
                      const readingMap = {};
                      for (const reading of uniqueReadings) {
                          if (mode === "katakana") readingMap[reading] = reading.replace(/[\\u3041-\\u3096]/g, m => String.fromCharCode(m.charCodeAt(0) + 0x60));
                          else readingMap[reading] = await ks.convert(reading, { mode: "normal", to: "romaji" });
                      }
                      rts.forEach(rt => { rt.textContent = readingMap[rt.textContent]; });
                  }

                  html = doc.body.innerHTML;

                  let classes = [];
                  const isHoverOn = document.querySelector('.frgntr-global-toolbar .fas.fa-eye-slash[title*="Visibility"]');
                  const isSelectOff = document.querySelector('.frgntr-global-toolbar .fas.fa-lock[title*="Selectability"]');

                  if (isHoverOn) classes.push('frgntr_hidden');
                  if (isSelectOff) classes.push('frgntr_unselectable');

                  const classAttr = classes.length > 0 ? ` class="${classes.join(' ')}"` : '';

                  html = html.split('<ruby>').join('<ruby furiganated="true">')
                             .split('<rp>(</rp><rt>').join(`<rp>(</rp><rt${classAttr}>`)
                             .split('\\n').join('<br>');

                  output.innerHTML = html;
                }, 400);
              });
            });
          });
        }
      </script>
    JS
    body = html_doc.at_css('body')
    body.add_child(Nokogiri::HTML::DocumentFragment.parse(live_script_html)) if body
    doc.output = html_doc.to_html
  end
end
