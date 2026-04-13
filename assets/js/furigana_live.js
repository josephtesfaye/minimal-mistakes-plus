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
            while (kuroshiroInitializing && attempts < 150) {
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
            // Fix Kuromoji path.join() bug corrupting HTTPS absolute URLs
            if (!window._frgntrXhrPatched) {
                const origOpen = window.XMLHttpRequest.prototype.open;
                window.XMLHttpRequest.prototype.open = function(method, url) {
                    if (typeof url === 'string' && url.startsWith('https:/cdn.jsdelivr.net')) {
                        url = url.replace('https:/cdn.jsdelivr.net', 'https://cdn.jsdelivr.net');
                    }
                    return origOpen.apply(this, arguments);
                };
                window._frgntrXhrPatched = true;
            }

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

    async function formatFurigana(html, mode, ks) {
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
            return doc.body.textContent.replace(/\n/g, '<br>');
        }

        if (mode === "katakana" || mode === "romaji") {
            const rts = doc.querySelectorAll('rt');
            const uniqueReadings = [...new Set(Array.from(rts).map(rt => rt.textContent))];
            const readingMap = {};
            for (const reading of uniqueReadings) {
                if (mode === "katakana") readingMap[reading] = reading.replace(/[\u3041-\u3096]/g, m => String.fromCharCode(m.charCodeAt(0) + 0x60));
                else readingMap[reading] = await ks.convert(reading, {
                    mode: "normal",
                    to: "romaji"
                });
            }
            rts.forEach(rt => {
                rt.textContent = readingMap[rt.textContent];
            });
        }

        let outHtml = doc.body.innerHTML;
        let classes = [];
        const isHoverOn = document.querySelector('.frgntr-global-toolbar .fas.fa-eye-slash[title*="Visibility"]');
        const isSelectOff = document.querySelector('.frgntr-global-toolbar .fas.fa-lock[title*="Selectability"]');
        if (isHoverOn) classes.push('frgntr_hidden');
        if (isSelectOff) classes.push('frgntr_unselectable');
        const classAttr = classes.length > 0 ? ` class="${classes.join(' ')}"` : '';

        return outHtml.split('<ruby>').join('<ruby furiganated="true">')
            .split('<rp>(</rp><rt>').join(`<rp>(</rp><rt${classAttr}>`)
            .split('\n').join('<br>');
    }

    document.addEventListener("DOMContentLoaded", () => {
        document.querySelectorAll('.frgntr-live-converter').forEach(container => {
            const input = container.querySelector('.frgntr-live-input');
            const output = container.querySelector('.frgntr-live-output');
            const status = container.querySelector('.frgntr-live-status');
            let timeout = null;

            input.addEventListener('focus', () => getKuroshiroInstance(status), {
                once: true
            });

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

                    const mode = window.frgntrLiveMode || "hiragana";
                    const transTarget = window.frgntrLiveTransTarget || "off";

                    const extractSurrogates = (str) => {
                        const surrogates = [];
                        let processed = "";
                        for (const char of str) {
                            if (char.length > 1) { // It's a surrogate pair (e.g., emoji)
                                surrogates.push(char);
                                processed += `@@SRG${surrogates.length - 1}@@`;
                            } else {
                                processed += char;
                            }
                        }
                        return {
                            processed,
                            surrogates
                        };
                    };
                    const restoreSurrogates = (str, surrogates) => {
                        let res = str;
                        surrogates.forEach((srg, idx) => {
                            res = res.split(`@@SRG${idx}@@`).join(srg);
                        });
                        return res;
                    };

                    if (transTarget === "off") {
                        let {
                            processed,
                            surrogates
                        } = extractSurrogates(text);
                        let rawFuri = await ks.convert(processed, {
                            mode: "furigana",
                            to: "hiragana"
                        });
                        rawFuri = restoreSurrogates(rawFuri, surrogates);
                        output.innerHTML = await formatFurigana(rawFuri, mode, ks);
                    } else {
                        status.style.display = 'block';
                        status.innerText = 'Translating...';

                        // Split text into sentences for sentence-by-sentence alignment
                        const rawSegments = text.match(/[^。！？\n]+[。！？\n]*/g) || [text];
                        let pass1 = [];
                        for (let seg of rawSegments) {
                            let leadingMatch = seg.match(/^([\uD800-\uDBFF][\uDC00-\uDFFF]|\s|[。！？、，,.])+/);
                            if (leadingMatch && pass1.length > 0) {
                                pass1[pass1.length - 1] += leadingMatch[0];
                                seg = seg.substring(leadingMatch[0].length);
                            }
                            if (seg.length > 0) pass1.push(seg);
                        }

                        let segments = [];
                        let buffer = "";
                        for (let i = 0; i < pass1.length; i++) {
                            buffer += pass1[i];
                            let stripped = buffer.replace(/[。！？、，,.\n\s]/g, '').replace(/[\uD800-\uDBFF][\uDC00-\uDFFF]/g, '');
                            let charCount = Array.from(stripped).length;
                            if (charCount <= 5 && i < pass1.length - 1) continue;
                            segments.push(buffer);
                            buffer = "";
                        }

                        let finalOutput = "";

                        for (const segment of segments) {
                            if (!segment.trim()) {
                                finalOutput += segment.replace(/\n/g, '<br>');
                                continue;
                            }

                            let {
                                processed,
                                surrogates
                            } = extractSurrogates(segment);
                            let rawFuri = await ks.convert(processed, {
                                mode: "furigana",
                                to: "hiragana"
                            });
                            rawFuri = restoreSurrogates(rawFuri, surrogates);
                            let furiHtml = await formatFurigana(rawFuri, mode, ks);

                            try {
                                const res = await fetch("https://translate-worker.josephtesfaye022.workers.dev", {
                                    method: "POST",
                                    body: JSON.stringify({
                                        text: segment,
                                        target: transTarget
                                    }),
                                    headers: {
                                        "Content-Type": "application/json"
                                    }
                                });
                                const data = await res.json();
                                if (data.translated) {
                                    finalOutput += `<div class="frgntr-sentence-pair" style="margin-bottom: 0.8em;"><div>${furiHtml}</div><div class="frgntr-translation" style="color: rgba(128,128,128,0.85); font-size: 0.9em; margin-top: 0.2em;">${data.translated}</div></div>`;
                                    continue;
                                }
                            } catch (e) {
                                console.error("Translation Error:", e);
                            }
                            finalOutput += `<div>${furiHtml}</div>`;
                        }
                        output.innerHTML = finalOutput;
                        status.style.display = 'none';
                    }
                }, 400);
            });
        });
    });
}
