#!/usr/bin/env bash
# timezone-auto: nothing while it's off; on, the zone for the weather location ("lat,lon" or a town) or the IP set only
# when it differs from the system's; no network, no answer or a bad one: nothing set, and no error
set -euo pipefail
. "$(dirname "$0")/lib.sh"
mkdir -p "$t/bin" "$t/home/.config/caelestia"
# (the network faked: each service answers what $ANSWER says; the URL asked for kept in $t/asked)
cat >"$t/bin/curl" <<EOF
#!/bin/sh
echo "\$*" >>"$t/asked"
[ -n "\$ANSWER" ] || exit 7
echo "\$ANSWER"
EOF
cat >"$t/bin/timedatectl" <<EOF
#!/bin/sh
case \$1 in show) echo Europe/Lisbon ;; --no-ask-password) echo "\$3" >>"$t/set" ;; *) exit 1 ;; esac
EOF
printf '#!/bin/sh\nexit 0\n' >"$t/bin/nm-online"
chmod +x "$t"/bin/*
place() { printf '{"services": {"weatherLocation": "%s"}}\n' "$1" >"$t/home/.config/caelestia/shell.json"; }
run() { rm -f "$t/set" "$t/asked"; HOME=$t/home PATH=$t/bin:$PATH ANSWER=${ANSWER-} timeout 10 "$here/.local/bin/timezone-auto" "$@"; }
set_to() { [[ $(cat "$t/set" 2>/dev/null) == "$1" ]]; }

place ""
ANSWER='{"timezone": "Europe/Madrid"}' run || fail "off: it failed"
[[ ! -e $t/set && ! -e $t/asked ]] || fail "off: it looked up or set the zone"
ANSWER='{"timezone": "Europe/Madrid"}' run on || fail "on: it failed"
set_to Europe/Madrid || fail "on, automatic location: the IP's zone wasn't set"
grep -q ip-api.com "$t/asked" || fail "automatic location: not looked up by IP"
ANSWER='{"timezone": "Europe/Lisbon"}' run
[[ ! -e $t/set ]] || fail "the zone it already is was set again"
ANSWER= run || fail "no network: it failed"
[[ ! -e $t/set ]] || fail "no network: a zone was set"
ANSWER='not json' run || fail "a bad answer: it failed"
[[ ! -e $t/set ]] || fail "a bad answer: a zone was set"
ANSWER='{"timezone": "x; rm -rf /"}' run
[[ ! -e $t/set ]] || fail "something not a zone name went to timedatectl"

place "40.42,-3.70"
ANSWER='{"timezone": "Europe/Madrid"}' run
set_to Europe/Madrid && grep -q 'latitude=40.42&longitude=-3.70&timezone=auto' "$t/asked" ||
    fail "a \"lat,lon\" weather location: its zone wasn't looked up and set"
place "New York"
ANSWER='{"results": [{"timezone": "America/New_York"}]}' run
set_to America/New_York && grep -q 'name=New York' "$t/asked" || fail "a town: its zone wasn't looked up and set"

run off
ANSWER='{"timezone": "Europe/Madrid"}' run
[[ ! -e $t/set ]] || fail "turned off: it still set the zone"
echo "ok timezone-auto"
