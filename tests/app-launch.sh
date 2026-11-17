#!/usr/bin/env bash
# app-launch: in a uwsm session, the app started in a unit of its own (uwsm app --), its arguments as given (a space
# in one kept); outside one, run as it is (uwsm stubbed: never the desktop's own)
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
mkdir -p "$t/bin"
cat >"$t/bin/uwsm" <<'EOF'
#!/bin/sh
case $1 in
    check) exit "$ACTIVE" ;;
    app) shift; [ "$1" = -- ] && shift; printf 'unit:%s\n' "$@" ;;
esac
EOF
chmod +x "$t/bin/uwsm"
out=$(ACTIVE=0 PATH=$t/bin:$PATH "$here/.local/bin/app-launch" printf '%s|' "a b" c)
[[ $out == $'unit:printf\nunit:%s|\nunit:a b\nunit:c' ]] || fail "not started in a unit of its own, as given: $out"
out=$(ACTIVE=1 PATH=$t/bin:$PATH "$here/.local/bin/app-launch" printf '%s|' "a b" c)
[[ $out == 'a b|c|' ]] || fail "outside a uwsm session, not run as it is: $out"
echo "ok app-launch"
