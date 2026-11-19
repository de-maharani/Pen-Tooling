#!/usr/bin/env bash
# ==============================================================
# FileNamer.sh — Extract names + comments from local files
# ==============================================================
#
# CONFIGURE BEFORE RUNNING:
#   NAMES   — path to your curated names dictionary
#             (one name per line, case-insensitive, blanks ignored)
#
# Run this script from the directory you want to scrape.
# It scans maxdepth 1 only (no recursion into subdirectories).
#
# OUTPUTS:
#   scrapeSA.txt       — single-name candidates
#   scrapeGRP2.txt     — adjacent two-name pairs
#   scrapeGRP3.txt     — adjacent three-name triplets
#   scrapeM.txt        — emails containing a known name
#   COMMscrape.txt     — deduplicated comment lines
#   ARCHIVESscrape.txt — per-file breakdown (SA → GRP2 → GRP3 → M → COMMENT)
#
# DEPENDENCIES: gawk (not awk), perl, unzip, strings, find
# ==============================================================
set -uo pipefail

NAMES="/path/to/names_list.txt"   # CONFIGURE: names dictionary
RAW="scrape_raw.txt"
COMM_PRE="COMMprefixed_scrape.txt"
COMM="COMMscrape.txt"
ARCHIVE="ARCHIVESscrape.txt"
ARCHIVE_RAW="rawARCHIVESscrape.txt"

[ -f "$NAMES" ] || { echo "[x] $NAMES not found"; exit 1; }

: > "$RAW"
: > "$COMM"
: > "$COMM_PRE"
: > "$ARCHIVE_RAW"

# ── Per-file text + comment extraction ──
n_files=0
while IFS= read -r -d '' FILE; do
  [ -z "$FILE" ] && continue
  n_files=$((n_files+1))
  echo "[*] ($n_files) $FILE"

  # Office / EPUB: unzip the container; everything else: strings
  case "$FILE" in
    *.docx|*.xlsx|*.pptx|*.odt|*.epub)
      unzip -p "$FILE" 2>/dev/null
      ;;
    *)
      strings -n 3 "$FILE" 2>/dev/null
      ;;
  esac | while IFS= read -r line; do
    [ -z "$line" ] && continue
    printf '%s\001file\001%s\n' "$FILE" "$line" >> "$RAW"
  done

  # HTML / JS / CSS / PHP comment scrape per file
  perl -0777 -ne '
      while (/<!--(.*?)-->/sg)    { print "$1\n" }
      while (/\/\*(.*?)\*\//sg)   { print "$1\n" }
      while (/(?<!:)\/\/(.*?)$/mg){ print "$1\n" }
    ' "$FILE" 2>/dev/null \
    | sed "s/^[[:space:]]*//; s/[[:space:]]*$//" \
    | tr '\t' ' ' \
    | grep -v '^$' \
    | while IFS= read -r c; do
        [ -z "$c" ] && continue
        printf '%s\001comment\001%s\n' "$FILE" "$c" >> "$COMM_PRE"
      done
done < <(find . -maxdepth 1 -type f \
  \( -name '*.txt' -o -name '*.md' -o -name '*.markdown' -o -name '*.rst' \
     -o -name '*.tex' -o -name '*.log' -o -name '*.csv' -o -name '*.tsv' \
     -o -name '*.html' -o -name '*.htm' -o -name '*.xhtml' -o -name '*.shtml' \
     -o -name '*.php' -o -name '*.asp' -o -name '*.aspx' -o -name '*.jsp' \
     -o -name '*.cfm' -o -name '*.js' -o -name '*.jsx' -o -name '*.ts' -o -name '*.tsx' \
     -o -name '*.css' -o -name '*.scss' -o -name '*.sass' -o -name '*.less' \
     -o -name '*.py' -o -name '*.rb' -o -name '*.pl' -o -name '*.go' -o -name '*.rs' \
     -o -name '*.c' -o -name '*.cc' -o -name '*.cpp' -o -name '*.cxx' \
     -o -name '*.h' -o -name '*.hpp' -o -name '*.java' -o -name '*.kt' -o -name '*.swift' \
     -o -name '*.sh' -o -name '*.bash' -o -name '*.zsh' -o -name '*.bat' -o -name '*.cmd' \
     -o -name '*.ps1' -o -name '*.psd1' -o -name '*.psm1' \
     -o -name '*.vbs' -o -name '*.vba' \
     -o -name '*.xml' -o -name '*.json' -o -name '*.yaml' -o -name '*.yml' \
     -o -name '*.ini' -o -name '*.conf' -o -name '*.cfg' -o -name '*.properties' \
     -o -name '*.env' -o -name '*.sql' \
     -o -name '*.doc' -o -name '*.docx' -o -name '*.rtf' -o -name '*.odt' \
     -o -name '*.xls' -o -name '*.xlsx' -o -name '*.ppt' -o -name '*.pptx' \
     -o -name '*.pdf' -o -name '*.epub' -o -name '*.mobi' \) \
  ! -name "$RAW" ! -name "$COMM_PRE" ! -name "$COMM" \
  ! -name "$ARCHIVE" ! -name "$ARCHIVE_RAW" \
  ! -name 'scrapeSA.txt' ! -name 'scrapeGRP2.txt' \
  ! -name 'scrapeGRP3.txt' ! -name 'scrapeM.txt' \
  -print0 2>/dev/null)

# ── Dedupe comments for reading ──
if [ -s "$COMM_PRE" ]; then
  cut -d $'\001' -f3 "$COMM_PRE" | sort -u > "$COMM"
else
  : > "$COMM"
fi

# ── Buckets ──
: > scrapeSA.txt
: > scrapeGRP2.txt
: > scrapeGRP3.txt
: > scrapeM.txt

# Same AWK engine as nameweb:
#   SA   — single name substrings (3..maxlen) found in tokens/emails
#   GRP2 — adjacent 2-name combos inside a token or across adjacent tokens
#   GRP3 — adjacent 3-name combos inside a token or across 3 tokens
#   M    — emails whose local-part contains at least one known name
gawk -v names="$NAMES" -v minlen=3 -v maxlen=25 \
    -v out_sa="scrapeSA.txt" -v out_g2="scrapeGRP2.txt" \
    -v out_g3="scrapeGRP3.txt" -v out_m="scrapeM.txt" \
    -v out_arch="$ARCHIVE_RAW" '
  BEGIN {
    FS = "\001"
    while ((getline n < names) > 0) {
      sub(/\r$/, "", n); gsub(/^[ \t]+|[ \t]+$/, "", n)
      n = tolower(n)
      if (length(n) > 0) known[n] = 1
    }
    close(names)
  }

  function emit(bucket, item,    f) {
    if      (bucket == "SA")   f = out_sa
    else if (bucket == "GRP2") f = out_g2
    else if (bucket == "GRP3") f = out_g3
    else if (bucket == "M")    f = out_m
    else return
    print item >> f
    printf "%s\t%s\t%s\n", src, bucket, item >> out_arch
  }

  function adjacent(tok, end_a, start_b,    gap) {
    if (start_b == end_a + 1) return 1
    if (start_b <= end_a)     return 0
    gap = substr(tok, end_a + 1, start_b - end_a - 1)
    return (gap ~ /^[._\047-]+$/)
  }

  function rightmost(i,    m, best, besten) {
    best = ""; besten = -1
    for (m in mtch[i]) {
      if (fen[i][m] > besten) { besten = fen[i][m]; best = m }
    }
    return best
  }

  function leftmost(i,    m, best, bestst) {
    best = ""; bestst = 999999
    for (m in mtch[i]) {
      if (fst[i][m] < bestst) { bestst = fst[i][m]; best = m }
    }
    return best
  }

  {
    src   = $1
    stype = $2
    line  = $3

    if (stype == "comment" && line != "")
      printf "%s\tCOMMENT\t%s\n", src, line >> out_arch

    if (line == "") next

    nt = 0
    while (match(line, /[a-zA-Z0-9][a-zA-Z0-9._\047-]*@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}/)) {
      emails[++ne] = substr(line, RSTART, RLENGTH)
      line = substr(line, 1, RSTART-1) " " substr(line, RSTART+RLENGTH)
    }
    while (match(line, /[a-zA-Z][a-zA-Z0-9._\047-]*/)) {
      tokens[++nt] = substr(line, RSTART, RLENGTH)
      line = substr(line, RSTART + RLENGTH)
    }

    for (k = 1; k <= ne; k++) {
      e = emails[k]; el = length(e); elow = tolower(e)
      has = 0
      for (s = 1; s <= el; s++) {
        if (substr(elow, s, 1) !~ /[a-z]/) continue
        me = el; if (s + maxlen - 1 < el) me = s + maxlen - 1
        for (en = s + minlen - 1; en <= me; en++) {
          c = substr(elow, s, en - s + 1)
          if (c in known) { emit("SA", c); has = 1 }
        }
      }
      if (has) emit("M", e)
      delete emails[k]
    }
    ne = 0

    if (nt == 0) next

    for (i = 1; i <= nt; i++) {
      delete mtch[i]; delete fst[i]; delete fen[i]
      nm[i] = 0
      tl = length(tokens[i]); tlow = tolower(tokens[i])
      for (s = 1; s <= tl; s++) {
        if (substr(tlow, s, 1) !~ /[a-z]/) continue
        me = tl; if (s + maxlen - 1 < tl) me = s + maxlen - 1
        for (en = s + minlen - 1; en <= me; en++) {
          c = substr(tlow, s, en - s + 1)
          if ((c in known) && !(c in mtch[i])) {
            mtch[i][c] = 1; fst[i][c] = s; fen[i][c] = en; nm[i]++
          }
        }
      }
    }

    for (i = 1; i <= nt; i++) {
      if (nm[i] == 0) continue
      tlow = tolower(tokens[i]); tl = length(tokens[i])
      if (index(tokens[i], "\047") == 0) emit("SA", tlow)
      for (m in mtch[i]) {
        emit("SA", m)
        if (fen[i][m] < tl && substr(tlow, fen[i][m]+1, 1) == "s")
          emit("SA", m "s")
      }
    }

    for (i = 1; i <= nt; i++) {
      if (nm[i] < 2) continue
      tlow = tolower(tokens[i])
      for (a in mtch[i]) {
        for (b in mtch[i]) {
          if (a == b) continue
          if (!adjacent(tlow, fen[i][a], fst[i][b])) continue
          emit("GRP2", a " " b)
          for (c in mtch[i]) {
            if (c == a || c == b) continue
            if (!adjacent(tlow, fen[i][b], fst[i][c])) continue
            emit("GRP3", a " " b " " c)
          }
        }
      }
    }

    for (i = 1; i < nt; i++) {
      if (nm[i] == 0 || nm[i+1] == 0) continue
      a = rightmost(i)
      b = leftmost(i+1)
      if (a != "" && b != "" && a != b) emit("GRP2", a " " b)
    }

    for (i = 1; i <= nt - 2; i++) {
      if (nm[i] == 0 || nm[i+1] != 1 || nm[i+2] == 0) continue
      a = rightmost(i)
      c = leftmost(i+2)
      b = ""; for (m in mtch[i+1]) b = m
      if (a != "" && b != "" && c != "" && a != b && b != c)
        emit("GRP3", a " " b " " c)
    }
  }
' "$RAW" "$COMM_PRE"

# ── Dedupe buckets ──
sort -u scrapeSA.txt   -o scrapeSA.txt
sort -u scrapeGRP2.txt -o scrapeGRP2.txt
sort -u scrapeGRP3.txt -o scrapeGRP3.txt
sort -u scrapeM.txt    -o scrapeM.txt

# ── Per-file archive (SA → GRP2 → GRP3 → M → COMMENT) ──
if [ -s "$ARCHIVE_RAW" ]; then
  sort -u "$ARCHIVE_RAW" \
  | gawk -F'\t' 'BEGIN {
      rank["SA"]=1; rank["GRP2"]=2; rank["GRP3"]=3; rank["M"]=4; rank["COMMENT"]=5
    }
    { print $1 "\t" (rank[$2]?rank[$2]:99) "\t" $2 "\t" $3 }' \
  | sort -t$'\t' -k1,1 -k2,2n -k4,4 \
  | gawk -F'\t' '
      {
        if ($1 != prev) {
          if (NR > 1) print ""
          print $1
          prev = $1
        }
        printf "\t%s\t%s\n", $3, $4
      }' > "$ARCHIVE"
else
  : > "$ARCHIVE"
fi

echo "[i] files: $n_files  SA: $(wc -l < scrapeSA.txt)  GRP2: $(wc -l < scrapeGRP2.txt)  GRP3: $(wc -l < scrapeGRP3.txt)  M: $(wc -l < scrapeM.txt)  COMM: $(wc -l < "$COMM")  ARCH: $(grep -c '^[^[:space:]]' "$ARCHIVE" 2>/dev/null || echo 0) files logged"
