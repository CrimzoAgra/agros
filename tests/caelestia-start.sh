#!/usr/bin/env bash
# caelestia-start: builds the overlay only when it's missing, sets the wallpaper and colours the first time (before the
# shell), starts the shell either way (even after a failed build), and logs them
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
[[ $(tail -1 "$t/home/started") == "caelestia shell -d" ]] || fail "first login: the shell wasn't started last"
grep -q '^caelestia scheme set -n dynamic$' "$t/home/started" || fail "first login: the colours weren't set"
[[ -e $t/home/.local/state/agros/wallpaper-set ]] || fail "first login: the wallpaper's mark isn't there"
grep -q 'overlay built: exit 0' "$log" || fail "first login: the build isn't logged"

run
[[ $(wc -l <"$t/home/overlay-runs") -eq 1 ]] || fail "next login: the overlay was built again"
[[ $(grep -c 'shell -d' "$t/home/started") -eq 2 ]] || fail "next login: the shell wasn't started"
[[ $(grep -c '^caelestia wallpaper' "$t/home/started") -eq 1 ]] || fail "next login: the wallpaper was set again"
grep -q 'overlay there' "$log" || fail "next login: not logged"

rm -rf "$t/home/.config/quickshell/caelestia"
FAIL=1 run
[[ $(grep -c 'shell -d' "$t/home/started") -eq 3 ]] || fail "a failed build: the shell wasn't started anyway"
grep -q 'overlay built: exit 1' "$log" || fail "a failed build: its exit code isn't logged"

# An install from before the mark, with a wallpaper picked since (Caelestia's path.txt): not replaced
rm "$t/home/.local/state/agros/wallpaper-set"; : >"$t/home/started"
mkdir -p "$t/home/.local/state/caelestia/wallpaper"; echo /pics/mine.jpg >"$t/home/.local/state/caelestia/wallpaper/path.txt"
run
grep -q '^caelestia wallpaper' "$t/home/started" && fail "an existing install: its wallpaper replaced"
[[ -e $t/home/.local/state/agros/wallpaper-set ]] || fail "an existing install: no mark"
echo "ok caelestia-start"
