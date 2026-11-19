FileNamer.sh — extracts names and comments from all possible readable local files

FileNamer recursively ("maxdepth 1") reads every supported file in the current directory, extracts text via unzip -p for Office/EPUB containers or strings -n 3 for everything else, and separately pulls <!-- -->, /* */, and // comments with perl.

Both streams feed the same AWK engine as nameweb, which cross-references every token against a names dictionary and emits four deduplicated buckets — SA (single names), GRP2 (adjacent two-name pairs), GRP3 (adjacent three-name triplets), and M (emails containing a known name) — plus a per-file archive ordered SA → GRP2 → GRP3 → M → COMMENT.
It notably handles ~80 file extensions in one pass and tolerates Office/EPUB binary containers, so a shared drive dump or exported mailbox becomes a spray-ready wordlist without manual triage.

What to tweak in-code:

(-) NAMES — path to your curated names dictionary (one name per line, case-insensitive); output quality depends entirely on this file; I highly recommend "https://github.com/FinNLP/humannames/blob/master/list.txt"

(-) RAW / COMM_PRE / COMM / ARCHIVE / ARCHIVE_RAW — intermediate and final output filenames; safe to leave as-is unless you're merging multiple runs

(-) minlen / maxlen (in the gawk -v call) — substring length bounds for name matching (default 3–25); lower minlen for more hits, raise for fewer false positives
