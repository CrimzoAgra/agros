#!/usr/bin/env bash
# caelestia-start: builds the overlay only when it's missing, starts the shell either way (even after a failed build),
# and logs both
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
mkdir -p "$t/home/.local/bin" "$t/bin"
cat >"$t/home/.local/bin/caelestia-overlay" <<'S'
#!/usr/bin/env bash
echo built >>"$HOME/overlay-runs"
mkdir -p "$HOME/.config/quickshell/caelestia" && touch "$HOME/.config/quickshell/caelestia/shell.qml"
exit "${FAIL:-0}"
S
printf '#!/usr/bin/env bash\necho "caelestia $*" >>"$HOME/started"\n' >"$t/bin/caelestia"
chmod +x "$t/home/.local/bin/caelestia-overlay" "$t/bin/caelestia"
run() { HOME=$t/home XDG_STATE_HOME= PATH=$t/bin:$PATH "$here/.local/bin/caelestia-start"; }
log=$t/home/.local/state/agros/caelestia-start.log
fail() { echo "FAIL caelestia-start: $1"; exit 1; }

run
[[ $(cat "$t/home/overlay-runs") == built ]] || fail "first login: the overlay wasn't built"
[[ $(cat "$t/home/started") == "caelestia shell -d" ]] || fail "first login: the shell wasn't started"
grep -q 'overlay built: exit 0' "$log" || fail "first login: the build isn't logged"

run
[[ $(wc -l <"$t/home/overlay-runs") -eq 1 ]] || fail "next login: the overlay was built again"
[[ $(wc -l <"$t/home/started") -eq 2 ]] || fail "next login: the shell wasn't started"
grep -q 'overlay there' "$log" || fail "next login: not logged"

rm -rf "$t/home/.config/quickshell/caelestia"
FAIL=1 run
[[ $(wc -l <"$t/home/started") -eq 3 ]] || fail "a failed build: the shell wasn't started anyway"
grep -q 'overlay built: exit 1' "$log" || fail "a failed build: its exit code isn't logged"
echo "ok caelestia-start"
