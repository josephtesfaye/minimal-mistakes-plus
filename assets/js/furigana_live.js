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

                        try {
                            // 1. Normalize Source Text
                            let cleanText = text.replace(/\n/g, ''); // Remove newlines

                            // Remove spaces between CJK characters and CJK punctuation
                            const cjk = "[\u3400-\u4DBF\u4E00-\u9FFF\u3040-\u309F\u30A0-\u30FF\uAC00-\uD7AF，。、！？；：”’（）《》〈〉【】『』「」]";
                            const cjkSpaceRegex = new RegExp(`(${cjk})\\s+(?=(${cjk}|\\d))`, 'g');
                            cleanText = cleanText.replace(cjkSpaceRegex, '$1');

                            // 2. Segment strictly by punctuation
                            const rawSegments = cleanText.match(/[^。！？]+[。！？]*/g) || [cleanText];
                            let segments = [];
                            for (let seg of rawSegments) {
                                // Keep emojis and trailing spaces attached to the previous segment
                                let leadingMatch = seg.match(/^([\uD800-\uDBFF][\uDC00-\uDFFF]|\s|[、，,])+/);
                                if (leadingMatch && segments.length > 0) {
                                    segments[segments.length - 1] += leadingMatch[0];
                                    seg = seg.substring(leadingMatch[0].length);
                                }
                                if (seg.trim().length > 0) segments.push(seg.trim());
                            }

                            // 3. Ensure every segment contains a delimiter
                            let normalizedSegments = segments.map(seg => {
                                if (!/[。！？]/.test(seg)) return seg + '。';
                                return seg;
                            });

                            // 4. Construct unified request payload using the @ neutral delimiter
                            const requestText = normalizedSegments.join(" @ ");

                            // 5. Send single batch request
                            const res = await fetch("https://translate-worker.josephtesfaye022.workers.dev", {
                                method: "POST",
                                body: JSON.stringify({
                                    text: requestText,
                                    target: transTarget
                                }),
                                headers: {
                                    "Content-Type": "application/json"
                                }
                            });

                            if (!res.ok) {
                                const errorPayload = await res.json();
                                throw new Error(errorPayload.error || "Unknown Worker Error");
                            }

                            const data = await res.json();

                            // 6. Split translation back into perfectly aligned segments
                            const translatedSegments = (data.translated || "").split(/\s*@\s*/);

                            // 7. Generate HTML for each aligned pair
                            let finalOutput = "";
                            for (let i = 0; i < normalizedSegments.length; i++) {
                                const segment = normalizedSegments[i];
                                const trans = translatedSegments[i] || "";

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

                                finalOutput += `<div class="frgntr-sentence-pair" style="margin-bottom: 0.8em;"><div>${furiHtml}</div><div class="frgntr-translation" style="color: rgba(128,128,128,0.85); font-size: 0.9em; margin-top: 0.2em;">${trans}</div></div>`;
                            }

                            output.innerHTML = finalOutput;
                        } catch (e) {
                            console.error("Translation Failed:", e.message);
                            // Fallback to pure Furigana if the API fails entirely
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
                        } finally {
                            status.style.display = 'none';
                        }
                    }
                }, 400);
            });
        });
    });
}
