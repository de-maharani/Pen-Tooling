TARGET="http://YOUR_TARGET_HOST:YOUR_PORT/YOUR_PATH" bash <<'BASH'
#!/bin/bash
# ==============================================================
# Paramecia.sh — Multi-stage web parameter discovery & fuzzer
# ==============================================================
#
# CONFIGURE BEFORE RUNNING:
#   TARGET    — set on the invocation line (above), not inside
#   COOKIE    — session cookie value if the target is authenticated
#   WORDLIST  — parameter-name wordlist path (SecLists recommended)
#
# DEPENDENCIES: curl, jq, x8, ffuf
#   Missing jq  -> JSON field extraction in stage 3 is skipped
#   Missing x8  -> stage 4 GET/POST and stage 5 JSON fuzz are skipped
#   Missing ffuf-> stage 4 POST query-string fuzz is skipped
#
# STAGES:
#   [1/5] Visible GET params  — parsed from TARGET's query string
#   [2/5] Visible POST params — parsed from any <form> on the page
#   [3/5] JS endpoint mining + JSON flip probe
#   [4/5] Hidden-param fuzz (x8 GET, x8 POST, ffuf POST query-string)
#   [5/5] Per-endpoint JSON fuzz using templates mined in [3/5]
# ==============================================================
WORDLIST="/usr/share/seclists/Discovery/Web-Content/burp-parameter-names.txt"
COOKIE="session=YOUR_SESSION_VALUE"   # empty string = no auth header

echo "═══════════════════════════════════════════════════════════════"
echo " 🎯 TARGET: $TARGET"
[ -n "$COOKIE" ] && echo " 🍪 COOKIE: $COOKIE"
echo "═══════════════════════════════════════════════════════════════"

TMP_DIR=$(mktemp -d)
JS_ENDPOINTS="$TMP_DIR/js_endpoints.txt"
: > "$JS_ENDPOINTS"
trap 'rm -rf "$TMP_DIR"' EXIT

# ═══════════════════════════════════════════════════════════════
# 1. VISIBLE GET
# ═══════════════════════════════════════════════════════════════
echo -e "\n─── [1/5] VISIBLE GET PARAMS ───"
if [[ "$TARGET" == *"?"* ]]; then
  base="${TARGET%%\?*}"
  params=$(echo "$TARGET" | sed 's/.*?//' | tr '&' '\n' | sed 's/=.*//' | tr '\n' ',' | sed 's/,$//')
  printf '  URL    : %s\n  Params : %s\n' "$base" "$params"
else
  echo "  (no query string)"
fi

# ═══════════════════════════════════════════════════════════════
# 2. VISIBLE POST
# ═══════════════════════════════════════════════════════════════
echo -e "\n─── [2/5] VISIBLE POST PARAMS ───"
tmpf="$TMP_DIR/index.html"
meta=$(curl -skL --max-time 10 --compressed --max-filesize 5000000 \
  -H "Cookie: $COOKIE" \
  -o "$tmpf" -w '%{content_type}|%{url_effective}' "$TARGET" 2>/dev/null)
ctype="${meta%%|*}"
final_url="${meta##*|}"

action=""
fields=""
if [[ "$ctype" == *"html"* || "$ctype" == *"xml"* || "$ctype" == *"xhtml"* || -z "$ctype" ]] && grep -qai '<form' "$tmpf"; then
  action=$(tr '\n' ' ' < "$tmpf" | grep -aoE '<form[^>]*action=["'"'"']?[^"'"'"' >]+' | head -1 | sed 's/.*action=["'"'"']\?//')
  [ -z "$action" ] && action="$final_url"
  case "$action" in
    http*) ;;
    /*)   action="$(printf '%s' "$final_url" | grep -oE 'https?://[^/]+')$action" ;;
    *)    action="${final_url%/*}/$action" ;;
  esac
  fields=$(grep -aoE '<input[^>]*name=["'"'"']?[^"'"'"' >]+' "$tmpf" | grep -aoE 'name=["'"'"']?[^"'"'"' >]+' | sed 's/name=["'"'"']\?//' | grep -avE '^(submit|reset|button)$' | sort -u | tr '\n' ',' | sed 's/,$//')

  if [ -n "$fields" ]; then
    printf '  Action : %s\n  Fields : %s\n' "$action" "$fields"
  else
    echo "  (form found, no named inputs)"
  fi
else
  echo "  (no HTML form found)"
fi

# ═══════════════════════════════════════════════════════════════
# 3. JSON EXTRACTIONS & FLIP
# ═══════════════════════════════════════════════════════════════
echo -e "\n─── [3/5] JSON EXTRACTIONS ───"
if [[ "$ctype" == *"json"* ]] || [[ "$(head -c 1 "$tmpf")" == "{" ]] || [[ "$(head -c 1 "$tmpf")" == "[" ]]; then
  echo "  [!] TARGET returns JSON directly ($ctype)"
  jq_fields=$(jq -r 'keys[]' "$tmpf" 2>/dev/null | tr '\n' ',' | sed 's/,$//')
  [ -n "$jq_fields" ] && echo "      Fields: $jq_fields"
fi

# Extract JS files referenced by the page
grep -oE 'src=["'"'"'][^"'"'"']+\.js[^"'"'"']*' "$tmpf" 2>/dev/null | sed 's/src=["'"'"']//' | sort -u | while read -r js; do
  case "$js" in /*) js_url="$(echo "$TARGET" | grep -oE 'https?://[^/]+')$js" ;; http*) js_url="$js" ;; *) js_url="${TARGET%/*}/$js" ;; esac
  curl -skL --max-time 10 -H "Cookie: $COOKIE" "$js_url" -o "$TMP_DIR/$(echo "$js" | md5sum | cut -d' ' -f1).js" 2>/dev/null
done

# Mine JS for endpoint call sites and surrounding field names
endpoints=$(grep -rhoE '(fetch|axios\.[a-z]+|\$\.(ajax|post|get)|XMLHttpRequest)\s*\(\s*[`"'"'"'][^`"'"'"']+' "$TMP_DIR"/*.js 2>/dev/null | sed -E 's/.*[`"'"'"']//' | grep -E '^/' | awk '!seen[$0]++')

if [ -n "$endpoints" ]; then
  echo "  [i] JS Endpoints found:"
  while read -r ep; do
    esc=$(printf '%s' "$ep" | sed 's/[][\.^$*+?(){}|]/\\&/g')
    ctx=$(grep -rhoE ".{0,300}[\"']${esc}[\"'].{0,600}" "$TMP_DIR"/*.js 2>/dev/null | head -50)
    ep_fields=$(printf '%s' "$ctx" | grep -oE '["'"'"']?[A-Za-z_][A-Za-z0-9_]*["'"'"']?\s*:' | sed -E 's/["'"'"']//g; s/[[:space:]]*:$//' | sort -u | tr '\n' ',' | sed 's/,$//')

    printf '      %s\n      └─ %s\n' "$ep" "$ep_fields"

    # Persist for stage 5: URL|FIELDS
    echo "${ep}|${ep_fields}" >> "$JS_ENDPOINTS"
  done <<< "$endpoints"
fi

# JSON Flip Test — does the form endpoint accept application/json?
if [ -n "$fields" ] && [ -n "$action" ]; then
  echo "  [i] JSON Flip Test against $action..."
  flat_json="{"
  IFS=',' read -ra arr <<< "$fields"
  for f in "${arr[@]}"; do flat_json+="\"$f\":\"x\","; done
  flat_json="${flat_json%,}}"

  code=$(curl -sk -o /dev/null -w '%{http_code}' -X POST \
    -H "Content-Type: application/json" \
    -H "Cookie: $COOKIE" \
    -d "$flat_json" --max-time 5 "$action" 2>/dev/null)
  case "$code" in
    415|404|501|000) echo "      [-] Rejected (HTTP $code)" ;;
    *) echo "      [+] ACCEPTED (HTTP $code)! JSON Flip works." ;;
  esac
fi

# ═══════════════════════════════════════════════════════════════
# 4. HIDDEN PARAMETER FUZZING (GET, POST)
# ═══════════════════════════════════════════════════════════════
echo -e "\n─── [4/5] HIDDEN FUZZING (GET, POST) ───"
if [ -f "$WORDLIST" ]; then
  echo "  [i] x8 GET Fuzz..."
  hits=$(x8 -u "$TARGET" -w "$WORDLIST" -H "Cookie: $COOKIE" --progress-bar-len 0 -c 20 --delay 30 --timeout 5 2>/dev/null | grep -E '\{|\[')
  if [ -n "$hits" ]; then echo "$hits" | awk '{print "\n• " $0}'; else echo "      (none)"; fi

  echo -e "\n  [i] x8 POST Form-Body Fuzz..."
  hits=$(x8 -u "$TARGET" --method POST -w "$WORDLIST" -H "Cookie: $COOKIE" --progress-bar-len 0 -c 20 --delay 30 --timeout 5 2>/dev/null | grep -E '\{|\[')
  if [ -n "$hits" ]; then echo "$hits" | awk '{print "\n• " $0}'; else echo "      (none)"; fi

  echo -e "\n  [i] ffuf POST Query-String Fuzz..."
  base_sz=$(curl -sk -o /dev/null -w '%{size_download}' -X POST -H "Cookie: $COOKIE" "$TARGET" 2>/dev/null); [ -z "$base_sz" ] && base_sz=0
  hits=$(ffuf -w "$WORDLIST" -X POST -u "${TARGET}?FUZZ=test" -H "Cookie: $COOKIE" -fs "$base_sz" -mc all -s 2>/dev/null)
  if [ -n "$hits" ]; then echo "$hits" | awk '{print "\n• " $0}'; else echo "      (none)"; fi
else
  echo "  [-] Wordlist missing: $WORDLIST"
fi

# ═══════════════════════════════════════════════════════════════
# 5. HIDDEN PARAMETER FUZZING (JSON - LOOPING ALL ENDPOINTS)
# ═══════════════════════════════════════════════════════════════
echo -e "\n─── [5/5] HIDDEN FUZZING (JSON) ───"
if [ -s "$JS_ENDPOINTS" ]; then
  while IFS='|' read -r ep ep_fields; do
    [ -z "$ep_fields" ] && continue

    # Resolve relative endpoint to absolute URL
    case "$ep" in /*) ep_url="$(echo "$TARGET" | grep -oE 'https?://[^/]+')$ep" ;; *) ep_url="${TARGET%/*}/$ep" ;; esac

    # Build template: {"field1":"x",...,{%s}}
    template="{"
    IFS=',' read -ra arr <<< "$ep_fields"
    for f in "${arr[@]}"; do template+="\"$f\":\"x\","; done
    template+="{%s}}"

    echo "  [i] x8 JSON Fuzz -> $ep_url"
    echo "      Template: $template"

    hits=$(x8 -u "$ep_url" --method POST --data-type json -b "$template" -w "$WORDLIST" -H "Cookie: $COOKIE" --progress-bar-len 0 -c 20 --delay 30 --timeout 5 2>/dev/null | grep -E '\{|\[')
    if [ -n "$hits" ]; then echo "$hits" | awk '{print "\n• " $0}'; else echo "      (none)"; fi
    echo ""
  done < "$JS_ENDPOINTS"
else
  echo "  (Skipping: no JSON endpoints/fields found to build a template)"
fi

echo -e "\n═══════════════════════════════════════════════════════════════"
echo " [+] Scan Complete."
BASH
