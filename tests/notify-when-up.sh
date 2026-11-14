#!/usr/bin/env bash
# notify-when-up (and dots-warn, its warning): tried again while the notification server doesn't take it (notify-send
# failing), sent once it does, the action picked printed; given up after its limit; dots-warn's defaults, overridable
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
mkdir -p "$t/bin"
# notify-send failing until $t/up is there ($t/fails counts its tries); each sleep a step, not half a second
cat >"$t/bin/notify-send" <<S
#!/bin/sh
[ -e "$t/up" ] || { echo x >>"$t/fails"; exit 1; }
printf '%s\n' "\$*" >"$t/sent"; echo restore
S
printf '#!/bin/sh\n[ "$(wc -l <"%s/fails" 2>/dev/null)" -ge 3 ] && touch "%s/up"\nexit 0\n' "$t" "$t" >"$t/bin/sleep"
chmod +x "$t/bin/"*
nwu() { PATH=$t/bin:$PATH NOTIFY_WHEN_UP_TRIES=${tries:-120} "$here/.local/bin/notify-when-up" "$@"; }
out=$(nwu -A restore=Restore "Title" "Text") || fail "not sent once the server was up"
[[ $out == restore && $(cat "$t/sent") == "-A restore=Restore Title Text" && $(wc -l <"$t/fails") == 3 ]] ||
    fail "sent: $(cat "$t/sent" 2>/dev/null), printed: $out, tries: $(wc -l <"$t/fails")"
# Never up: given up after the limit
rm -f "$t/up" "$t/fails" "$t/sent"; printf '#!/bin/sh\nexit 0\n' >"$t/bin/sleep"
tries=4 nwu "Title" "Text" && fail "reported sent with no server"
[[ $(wc -l <"$t/fails") == 4 ]] || fail "not given up after 4 tries: $(wc -l <"$t/fails")"
# dots-warn: critical, from Dotfiles, a warning icon; options given override those
touch "$t/up"
PATH=$t/bin:$PATH "$here/.local/bin/dots-warn" -u normal "Title" "Text" >/dev/null || fail "dots-warn"
[[ $(cat "$t/sent") == "-u critical -a Dotfiles -i dialog-warning -u normal Title Text" ]] || fail "dots-warn sent: $(cat "$t/sent")"
echo "ok notify-when-up"
