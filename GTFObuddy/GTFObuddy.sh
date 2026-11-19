#!/usr/bin/env bash
# ==============================================================
# GTFObuddy.sh — Cross-reference SUID/caps against GTFOBins
# ==============================================================
#
# CONFIGURE BEFORE RUNNING:
#   DB_FILE      — path to your GTFOBins dump ("binary:contexts" per line)
#   USELESS_CAPS — regex of capabilities you consider non-exploitable
#
# INPUT FILES (generated on the target, then copied next to this script):
#   suids.txt    find / -perm -4000 -type f 2>/dev/null > suids.txt
#   caps.txt     getcap -r / 2>/dev/null > caps.txt
#
# OUTPUT BUCKETS:
#   SUID/CAP Exploitable     — in GTFOBins AND has a matching exploit context
#                              -> try these first, high-confidence
#   OTHER SUID/CAPS          — in GTFOBins but no matching context
#                              -> known-safe in this context, low priority
#   MISSING SUID/CAPS        — NOT in GTFOBins
#                              -> highest-value: unusual binary = custom exploit
#
# Handles two suids.txt formats:
#   "find -ls"  (perm links owner group size date time PATH)
#   plain paths (one absolute path per line)
# ==============================================================
DB_FILE="/path/to/GTFOdb.txt"        # CONFIGURE: your GTFOBins dump
[ -f "$DB_FILE" ] || { echo "[-] DB not found: $DB_FILE"; exit 1; }

# Capabilities that are (almost) never useful for privesc on their own.
# Extend this if you've already ruled out other caps for your target.
USELESS_CAPS="cap_net_bind_service|cap_chown|cap_fowner|cap_setfcap"

# 1. Load DB into associative array
declare -A GTFO_MAP
while IFS=: read -r bin ctx; do
  [[ -z "$bin" ]] && continue
  [[ "$bin" =~ ^[[:space:]]*# ]] && continue
  bin=$(echo "$bin" | xargs); ctx=$(echo "$ctx" | xargs)
  GTFO_MAP["$bin"]="$ctx"
done < "$DB_FILE"

# Arrays to hold findings
declare -a SUID_LIST OTHER_SUID_LIST MISSING_SUID_LIST
declare -a CAP_LIST OTHER_CAP_LIST MISSING_CAP_LIST

# 2. Parse SUID (find -perm -4000 output, or plain paths)
if [ -f "suids.txt" ]; then
    if grep -qE '^[[:space:]]*[0-9]+[[:space:]]+[0-9]+[[:space:]]+' suids.txt; then
        awk '{print $11}' suids.txt | grep '^/' > /tmp/_suid_paths.txt
    else
        grep '^/' suids.txt > /tmp/_suid_paths.txt
    fi
    sort -u /tmp/_suid_paths.txt -o /tmp/_suid_paths.txt

    while IFS= read -r path; do
        bin=$(basename "$path")
        # Strip version suffixes like .basic / .nox / .tiny
        clean_bin=$(echo "$bin" | sed -E 's/\.(basic|tiny|nox|huge|small)$//')

        if [[ -z "${GTFO_MAP[$clean_bin]}" ]]; then
            MISSING_SUID_LIST+=("$path")
        elif [[ "${GTFO_MAP[$clean_bin]}" == *"suid"* ]]; then
            SUID_LIST+=("$path")
        else
            OTHER_SUID_LIST+=("$path")
        fi
    done < /tmp/_suid_paths.txt
fi

# 3. Parse CAPS (getcap output)
if [ -f "caps.txt" ]; then
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        path=$(echo "$line" | awk '{print $1}')
        caps=$(echo "$line" | cut -d' ' -f2-)
        bin=$(basename "$path")

        if [[ -z "${GTFO_MAP[$bin]}" ]]; then
            MISSING_CAP_LIST+=("$path ($caps)")
        elif [[ "${GTFO_MAP[$bin]}" == *"cap"* ]] && [[ -n "$caps" ]] && [[ ! "$caps" =~ $USELESS_CAPS ]]; then
            CAP_LIST+=("$path ($caps)")
        else
            OTHER_CAP_LIST+=("$path ($caps)")
        fi
    done < "caps.txt"
fi

# 4. Print sections nicely
print_section() {
  local label="$1"; shift
  local -a items=("$@")
  echo "═══ $label ═══"
  if [ ${#items[@]} -eq 0 ]; then
    echo "  (none)"
  else
    for i in $(printf '%s\n' "${items[@]}" | sort -u); do
      printf '  %s\n' "$i"
    done
  fi
  echo ""
}

print_section "SUID Exploitable (GTFOBins)" "${SUID_LIST[@]}"
print_section "CAP Exploitable (GTFOBins)"  "${CAP_LIST[@]}"

echo "--- The following were checked, but are NOT exploitable for this context ---"
print_section "OTHER SUID (In GTFOBins, but no SUID exploit)" "${OTHER_SUID_LIST[@]}"
print_section "OTHER CAPS (In GTFOBins, but no CAP exploit, or only 'Useless' caps)" "${OTHER_CAP_LIST[@]}"

echo "--- Binaries that are NOT EVEN IN GTFOBins!!! ---"
print_section "WITH SUID but NOT in GTFOBins → any strange directories?)" "${MISSING_SUID_LIST[@]}"
print_section "MISSING CAPS (Not in GTFOBins at all)" "${MISSING_CAP_LIST[@]}"
