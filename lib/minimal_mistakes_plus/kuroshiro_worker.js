const KuroshiroImport = require("kuroshiro");
const KuromojiAnalyzerImport = require("kuroshiro-analyzer-kuromoji");
const readline = require("readline");

const Kuroshiro = KuroshiroImport.default || KuroshiroImport;
const KuromojiAnalyzer = KuromojiAnalyzerImport.default || KuromojiAnalyzerImport;

const kuroshiro = new Kuroshiro();
const analyzer = new KuromojiAnalyzer();

async function start() {
    try {
        // Initialize dictionary once. This is the heavy operation.
        await kuroshiro.init(analyzer);

        // Signal to Ruby that the worker is ready to receive jobs
        console.log("READY");

        const rl = readline.createInterface({
            input: process.stdin,
            output: process.stdout,
            terminal: false
        });

        // Ensure the Node process exits automatically when Jekyll stops
        rl.on("close", () => {
            process.exit(0);
        });

        // Listen for batch jobs from Jekyll
        rl.on("line", async (line) => {
            try {
                const jobs = JSON.parse(line);
                const results = {};

                // Process each text block with its requested target mode
                for (const job of jobs) {
                    // Step 1: ALWAYS generate furigana in "hiragana" mode first.
                    // This forces Kuroshiro to correctly isolate Kanji and prevents
                    // it from over-wrapping pure Kana or English when target is Romaji.
                    let html = await kuroshiro.convert(job.text, {
                        mode: "furigana",
                        to: "hiragana"
                    });

                    // Step 2: If the requested mode is romaji or katakana,
                    // convert ONLY the isolated <rt> contents.
                    if (job.mode === "romaji" || job.mode === "katakana") {
                        const rtRegex = /<rt>(.*?)<\/rt>/g;
                        const matches = [...html.matchAll(rtRegex)];

                        const uniqueReadings = [...new Set(matches.map(m => m[1]))];
                        const readingMap = {};

                        for (const reading of uniqueReadings) {
                            if (job.mode === "katakana") {
                                // Fast and reliable native conversion to bypass Kuromoji's "unknown word" fallback
                                readingMap[reading] = reading.replace(/[\u3041-\u3096]/g, match =>
                                    String.fromCharCode(match.charCodeAt(0) + 0x60)
                                );
                            } else {
                                readingMap[reading] = await kuroshiro.convert(reading, {
                                    mode: "normal",
                                    to: "romaji"
                                });
                            }
                        }

                        html = html.replace(rtRegex, (match, p1) => `<rt>${readingMap[p1]}</rt>`);
                    }

                    results[job.id] = html;
                }

                // Return results synchronously over stdout
                console.log(JSON.stringify(results));
            } catch (e) {
                console.log(JSON.stringify({ error: e.toString() }));
            }
        });
    } catch(e) {
        console.error("Kuroshiro initialization failed:", e);
        process.exit(1);
    }
}

start();
