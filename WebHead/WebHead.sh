#!/usr/bin/env bash
# ==============================================================
# WebHead.sh — Build username wordlists from live web targets
# ==============================================================
#
# CONFIGURE BEFORE RUNNING:
#   URLS    — target list, one base URL per line
#   NAMES   — curated names dictionary (one name per line)
#
# DEPENDENCIES: cewl, wget, perl, awk, sort
#
# OUTPUTS:
#   webheadSA.txt       — single-name candidates
#   webheadGRP2.txt     — adjacent two-name pairs
#   webheadGRP3.txt     — adjacent three-name triplets
#   webheadM.txt        — emails containing a known name
#   COMMwebhead.txt     — deduplicated comment lines
#   ARCHIVESwebhead.txt — per-URL breakdown (SA → GRP2 → GRP3 → M → COMMENT)
#
# For local files instead of live URLs, use FileNamer.sh.
# ==============================================================
set -uo pipefail

URLS="/path/to/urls.txt"          # CONFIGURE: your target URL list
NAMES="/path/to/names_list.txt"   # CONFIGURE: your names dictionary
TARGETS="/tmp/targets.txt"
RAW="cewl_raw.txt"
COMM_PRE="/tmp/COMMprefixed.txt"
COMM="COMMwebhead.txt"
ARCHIVE="ARCHIVESwebhead.txt"
ARCHIVE_RAW="rawARCHIVESwebhead.txt"
TMP_CEWL="/tmp/cewl_one.txt"

[ -f "$URLS" ]  || { echo "[x] $URLS not found"; exit 1; }
[ -f "$NAMES" ] || { echo "[x] $NAMES not found"; exit 1; }

# Freeze the URL list for the duration of the run
cat "$URLS" > "$TARGETS"

# ── Clear outputs ──
: > "$RAW"
: > "$COMM"
: > "$COMM_PRE"
: > "$ARCHIVE_RAW"
mkdir -p "$(dirname "$TMP_CEWL")"

# ── Per-URL crawl + comment scrape ──
n_urls=0
while IFS= read -r TARGET; do
  TARGET="${TARGET%$'\r'}"
  [ -z "$TARGET" ] && continue
  n_urls=$((n_urls+1))
  echo "[*] ($n_urls) $TARGET"

  # cewl -g 2 — single/double-word terms
  cewl -d 3 -m 3 --with-numbers -g 2 -e -w "$TMP_CEWL" "$TARGET" 2>/dev/null || true
  if [ -s "$TMP_CEWL" ]; then
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      printf '%s\001cewl\001%s\n' "$TARGET" "$line" >> "$RAW"
    done < "$TMP_CEWL"
  fi

  # cewl -g 3 — longer phrases
  cewl -d 3 -m 3 --with-numbers -g 3 -e -w "$TMP_CEWL" "$TARGET" 2>/dev/null || true
  if [ -s "$TMP_CEWL" ]; then
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      printf '%s\001cewl\001%s\n' "$TARGET" "$line" >> "$RAW"
    done < "$TMP_CEWL"
  fi

  # HTML / JS / CSS / PHP comment scrape
  {
    wget -qO- --timeout 10 --tries 2 "$TARGET" 2>/dev/null \
      | perl -0777 -ne '
          while (/<!--(.*?)-->/sg)    { print "$1\n" }
          while (/\/\*(.*?)\*\//sg)   { print "$1\n" }
          while (/(?<!:)\/\/(.*?)$/mg){ print "$1\n" }
        ' \
      | sed "s/^[[:space:]]*//; s/[[:space:]]*$//" \
      | grep -v '^$'
  } | tr '\t' ' ' | while IFS= read -r c; do
      [ -z "$c" ] && continue
      printf '%s\001comment\001%s\n' "$TARGET" "$c" >> "$COMM_PRE"
    done
done < "$TARGETS"

# ── Dedupe comments for reading ──
if [ -s "$COMM_PRE" ]; then
  cut -d $'\001' -f3 "$COMM_PRE" | sort -u > "$COMM"
else
  : > "$COMM"
fi

# ── Buckets ──
: > webheadSA.txt
: > webheadGRP2.txt
: > webheadGRP3.txt
: > webheadM.txt

# Same AWK engine as FileNamer.sh:
#   SA   — single name substrings (3..maxlen) found in tokens/emails
#   GRP2 — adjacent 2-name combos inside a token or across adjacent tokens
#   GRP3 — adjacent 3-name combos inside a token or across 3 tokens
#   M    — emails whose local-part contains at least one known name
awk -v names="$NAMES" -v minlen=3 -v maxlen=25 \
    -v out_sa="webheadSA.txt" -v out_g2="webheadGRP2.txt" \
    -v out_g3="webheadGRP3.txt" -v out_m="webheadM.txt" \
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
    printf "%s\t%s\t%s\n", url, bucket, item >> out_arch
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
    url   = $1
    stype = $2
    line  = $3

    if (stype == "comment" && line != "")
      printf "%s\tCOMMENT\t%s\n", url, line >> out_arch

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
sort -u webheadSA.txt   -o webheadSA.txt
sort -u webheadGRP2.txt -o webheadGRP2.txt
sort -u webheadGRP3.txt -o webheadGRP3.txt
sort -u webheadM.txt    -o webheadM.txt

# ── Per-URL archive (SA → GRP2 → GRP3 → M → COMMENT) ──
if [ -s "$ARCHIVE_RAW" ]; then
  sort -u "$ARCHIVE_RAW" \
  | awk -F'\t' 'BEGIN {
      rank["SA"]=1; rank["GRP2"]=2; rank["GRP3"]=3; rank["M"]=4; rank["COMMENT"]=5
    }
    { print $1 "\t" (rank[$2]?rank[$2]:99) "\t" $2 "\t" $3 }' \
  | sort -t$'\t' -k1,1 -k2,2n -k4,4 \
  | awk -F'\t' '
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

echo "[i] URLs in: $n_urls  SA: $(wc -l < webheadSA.txt)  GRP2: $(wc -l < webheadGRP2.txt)  GRP3: $(wc -l < webheadGRP3.txt)  M: $(wc -l < webheadM.txt)  COMM: $(wc -l < "$COMM")  ARCH: $(grep -c '^http' "$ARCHIVE" 2>/dev/null || echo 0) URLs logged"
