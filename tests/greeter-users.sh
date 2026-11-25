#!/usr/bin/env bash
# The login screen's person pill: shown with more than one account, and with one when the last account to log in (the
# theme's) is gone (deleted or renamed: its name kept, every login failed, and nothing to pick the one left). Its
# visible expression run by node
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
qml=$here/.local/share/caelestia-greeter/shell.qml
command -v node >/dev/null || { echo "ok greeter-users (SKIPPED: no node)"; exit 0; }
expr=$(sed -n '/^                id: userPill$/,/^            }$/p' "$qml" | sed -n 's/^ *visible: //p')
[[ -n $expr ]] || fail "the person pill's visible not found in shell.qml"
out=$(node -e "const shown = (users, user) => { const root = { users, user }; return $expr; };
console.log([shown([], 'a'), shown(['a'], 'a'), shown(['a', 'b'], 'a'), shown(['b'], 'a'), shown(['b'], '')].join(' '))")
[[ $out == "false false true true true" ]] || fail "the person pill shown (none; one, its own; two; one, another's; one, none's): $out"
echo "ok greeter-users"
