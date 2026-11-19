Paramecia.sh — a multi-stage web parameter discovery and hidden-param fuzzer

An incredibly extensive parameter fuzzing tool meant to throw everything and the kitchen sink at a suspicious endpoint.

Paramecia runs five sequential discovery passes against a single URL: (1) extracts visible GET parameters from the target's query string; (2) fetches the target with curl, parses any HTML <form> for its action and named <input> fields, and resolves the action to an absolute URL; (3) mines inline JS for fetch/axios/$.ajax/XMLHttpRequest call sites, pulls candidate field names from the surrounding 300/600-char context, and probes whether the form endpoint accepts JSON with a "flip test" (application/json POST of the discovered fields); (4) fuzzes for hidden parameters three ways — x8 GET, x8 POST form-body, and ffuf POST query-string with a -fs baseline; (5) re-uses every JSON endpoint discovered in stage 3 as an x8 JSON template and fuzzes each one individually.
The value here is closing the loop between JS mining and JSON fuzzing: most tools typically stop at "here are some endpoints," this one auto-builds the field template from each endpoint's surrounding source and immediately fuzzes it, so you (might) get spray-ready parameter lists without manual template construction.

What to tweak in-code:

• TARGET — the URL to probe; set on the invocation line (TARGET="..." bash <<'BASH' ...), not inside the script

• COOKIE — session cookie if the target requires auth; leave empty if unauthenticated (Cookie: header with an empty value is harmless)

• WORDLIST — parameter-name wordlist; default is SecLists' burp-parameter-names.txt, which must exist on your system

• Dependencies — curl, jq, x8, ffuf. All five stages will still run without jq/x8/ffuf — they just silently produce no hits for the stages that need them.
