#!/usr/bin/env bash
# wait-online: any HTTP answer is online, an error (503) too: only no connection waits
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
python3 -I - "$t/port" <<'P' &
import http.server, sys
class H(http.server.BaseHTTPRequestHandler):
    def do_HEAD(self):
        self.send_response(503); self.end_headers()
    def log_message(self, *a):
        pass
s = http.server.HTTPServer(("127.0.0.1", 0), H)
open(sys.argv[1], "w").write(str(s.server_port))
s.serve_forever()
P
on_exit "kill $!"
for _ in $(seq 50); do [[ -s $t/port ]] && break; sleep 0.1; done
timeout 5 "$here/.local/bin/wait-online" "http://127.0.0.1:$(cat "$t/port")/" || fail "an HTTP 503 taken for offline"
echo "ok wait-online"
