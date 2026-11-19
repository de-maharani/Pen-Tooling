#!/usr/bin/env bash
# ==============================================================
# CRONY.sh — Enumerate non-default cron scripts + referenced paths
# ==============================================================
#
# Run as the target user (not root) to see what's actually writable.
# Running as root makes every path look writable and hides the signal.
#
# SCAN ROOTS:
#   /etc/cron.d  /etc/cron.daily  /etc/cron.hourly
#   /etc/cron.weekly  /etc/cron.monthly
#
# For each non-default script:
#   - perms / owner / size of the script itself
#   - full contents
#   - every absolute path it references (existing only),
#     with a WRITABLE? column — "⚠ YES" means YOU can write to it
#
# CONFIGURE:
#   DEFAULT_CRONS — skip list for known-safe distro defaults
# ==============================================================

# Standard Debian/Ubuntu cron scripts that are almost never privesc vectors
DEFAULT_CRONS="0anacron anacron apport apt-compat aptitude bsdmainutils cracklib-runtime dpkg e2scrub_all exim4-base fstrim imei logrotate man-db mlocate nginx-ee ntp passwd popularity-contest standard sysstat systemd-cron update-notifier-common upstart"

for f in /etc/cron.d/* /etc/cron.daily/* /etc/cron.hourly/* /etc/cron.weekly/* /etc/cron.monthly/*; do
  [ -f "$f" ] || continue
  name=$(basename "$f")

  # Skip placeholders and known default scripts
  [ "$name" = ".placeholder" ] && continue
  echo "$DEFAULT_CRONS" | grep -qw "$name" && continue

  echo "═══════════════════════════════════════════════════════════════"
  echo "  SCRIPT: $f"
  printf '  PERMS : %s\n' "$(stat -c '%A %U:%G %s bytes' "$f" 2>/dev/null)"
  echo "═══════════════════════════════════════════════════════════════"
  echo "  ─── contents ───"
  # If this is empty, the script is not readable by you — not an empty file
  sed 's/^/    /' "$f" 2>/dev/null

  # Extract absolute paths and check if they are writable by the current user
  refs=$(grep -oE '/[a-zA-Z0-9._/-]+' "$f" 2>/dev/null | sort -u)

  if [ -n "$refs" ]; then
    echo "  ─── referenced paths (existing) ───"
    printf '    %-11s %-16s %-8s %-40s %s\n' "PERMS" "OWNER" "SIZE" "PATH" "WRITABLE?"
    echo "$refs" | while read -r ref; do
      [ -e "$ref" ] || continue
      perms=$(stat -c '%A' "$ref" 2>/dev/null)
      owner=$(stat -c '%U:%G' "$ref" 2>/dev/null)
      size=$(stat -c '%s' "$ref" 2>/dev/null)
      [ -w "$ref" ] && w="⚠ YES" || w=""
      printf '    %-11s %-16s %-8s %-40s %s\n' "$perms" "$owner" "$size" "$ref" "$w"
    done
  fi
  echo
done
