WebHead.sh — mines a list of live URLs for names and emails to spray with

WebHead crawls each URL with cewl at depth 3 using both -g 2 and -g 3 (so multi-word pages aren't truncated to single tokens), then fetches each page with wget and extracts <!-- -->, /* */, and // comments via perl. Both streams feed the same AWK engine as FileNamer.sh, which cross-references every token against a names dictionary and emits four deduplicated buckets — SA (single names, including plural-s variants), GRP2 (adjacent two-name pairs, validated so only ./_/'/- may sit between matches), GRP3 (adjacent three-name triplets, in-token and across-token), and M (emails whose local-part contains a known name) — plus a per-URL archive ordered SA → GRP2 → GRP3 → M → COMMENT.
The main differentiator vs plain-old cewl, is that output is people-shaped rather than vocabulary-shaped, because every candidate is adjacency-validated against a known-name list (i.e. "https://github.com/FinNLP/humannames/blob/master/list.txt")

What to tweak in-code:
• URLS — path to your target URL list (one base URL per line); validated to exist at startup

• NAMES — path to your curated names dictionary; output quality depends entirely on this

• TARGETS, COMM_PRE, TMP_CEWL — intermediate scratch paths; leave in /tmp unless you want to keep artifacts between runs

• minlen / maxlen (in the awk -v call) — substring length bounds for name matching (default 3–25)

• cewl flags — -d 3 (crawl depth), -m 3 (minimum word length), -g 2 / -g 3 (group size); tune per engagement

• wget --timeout 10 --tries 2 — raise for slow or flaky targets
