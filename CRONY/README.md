CRONY.sh — finds non-default cron scripts and checks inside for writable referenced paths

Probably my personal favorite, CRONY walks the five cron directories (/etc/cron.d, cron.daily, cron.hourly, cron.weekly, cron.monthly) of default Linux setups, skips .placeholder and a curated list of Debian/Ubuntu default scripts, then—for each remaining script—prints its perms/owner/size and full contents, extracts every absolute path the script references, and "stats" each one, ultimately flagging any path the current user can write to with ⚠ YES.

This completely streamlines one branch of the entire privilege escalation due diligence checks into a single command pass — plus DEFAULT_CRONS skip list cuts ~90% of the noise before you read a single line.
