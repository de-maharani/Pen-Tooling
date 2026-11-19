GTFObuddy.sh — quickly and easily cross-references SUID and capability findings against GTFOBins

Loads a local GTFOBins-derived database (one binary:contexts line per entry), then parses suids.txt and caps.txt from the current directory and classifies every binary into one of six buckets: SUID exploitable (the binary is in GTFOBins and has a suid context), CAP exploitable (in GTFOBins and has a cap context that isn't on the "useless caps" list), OTHER SUID / OTHER CAPS (in the DB but not exploitable for that context — worth knowing, not worth burning time on), and MISSING SUID / MISSING CAPS (not in GTFOBins at all — the interesting bucket, because an unusual binary with SUID or caps is exactly where custom exploitation lives).

This again reduces what is usually a 5–10 minute task into one that takes ~30 seconds, and helps avoid human error by clearly identifying potentially abnormal binary names that are not even part of the GTFObins database.

What to tweak in-code:

• DB_FILE — path to your local GTFOBins dump; must be binary:contexts format (curl, python, etc. on the left, space-separated contexts on the right); make your own, or use the "GTFOdb.txt" one in the repo

• suids.txt / caps.txt — expected in the CWD; generate with find / -perm -4000 -type f 2>/dev/null > suids.txt and getcap -r / 2>/dev/null > caps.txt

• USELESS_CAPS — the capabilities regex you consider non-exploitable; extend with any caps you've already ruled out for your environment
