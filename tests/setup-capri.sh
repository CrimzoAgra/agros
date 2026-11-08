#!/usr/bin/env bash
# setup's capri step with stand-in repos and npm (as tests/capri-update.sh): it waits for the update started at boot
# (which runs capri-update too: two at once in the same folder), and run again after an install that failed (a
# release failing her check, which capri-update doesn't try again on its own) it tries again, not "failed before, not
# tried again" with Capri never installed
set -uo pipefail
. "$(dirname "$0")/lib.sh"
g() { git -C "$1" -c user.name=t -c user.email=t@t "${@:2}"; }
git init -q -b main "$t/up"
mkdir -p "$t/up/assets" "$t/up/src"; echo icon >"$t/up/assets/icon.png"; echo a >"$t/up/app.js"
g "$t/up" add -A; g "$t/up" commit -qm one; g "$t/up" tag v0.1.0
git clone -q "$t/up" "$t/fork"
export HOME=$t/home XDG_DATA_HOME= XDG_STATE_HOME= CAPRI_FORK=$t/fork CAPRI_UPSTREAM=$t/up log=$t/calls
mkdir -p "$HOME" "$t/bin"
# npm: "ci" fails while $t/offline is there, her check ("run typecheck") while $t/failtest is; systemctl: the boot's
# update not running; hyprctl: noted (her first install reloads the config: not your desktop's)
cat >"$t/bin/npm" <<'EOS'
#!/bin/sh
echo "npm $*" >>"$log"
case $1 in
    ci) [ ! -e "$(dirname "$log")/offline" ] && mkdir -p node_modules/.bin node_modules/electron && : >node_modules/electron/install.js && printf '#!/bin/sh\n' >node_modules/.bin/electron && chmod +x node_modules/.bin/electron ;;
    run) if [ "$3" = build ]; then mkdir -p out/main && : >out/main/index.js; else [ ! -e "$(dirname "$log")/failtest" ]; fi ;;
esac
EOS
printf '#!/bin/sh\necho "systemctl $*" >>"$log"\n[ "$1" != is-active ] || exit 1\n' >"$t/bin/systemctl"
printf '#!/bin/sh\necho "hyprctl $*" >>"$log"\n' >"$t/bin/hyprctl"
for c in node notify-send gh; do printf '#!/bin/sh\nexit 0\n' >"$t/bin/$c"; done
chmod +x "$t/bin/"*
export PATH=$t/bin:$PATH
step() { repo=$here yes=true capri=true bash -c 'set -e; source "$1/setup/lib.sh"; source "$1/setup/modules/45-capri.sh"; module_capri' _ "$here" 2>&1; }
touch "$t/offline"
out=$(step) || fail "the step stopped setup: $out"
[[ ! -e $HOME/.local/share/capri/current ]] || fail "installed with npm failing"
grep -nm1 '^systemctl is-active -q auto-update' "$log" | awk -F: -v f="$(grep -nm1 '^npm ' "$log" | cut -d: -f1)" '$1 < f {ok=1} END {exit !ok}' ||
    fail "capri-update ran without waiting for the boot's update: $(head -3 "$log")"
rm "$t/offline"; touch "$t/failtest"
out=$(step) || fail "the step stopped setup: $out"
[[ ! -e $HOME/.local/share/capri/current ]] || fail "installed with her check failing"
rm "$t/failtest"
out=$(step) || fail "the step stopped setup: $out"
[[ -x $HOME/.local/share/capri/current/node_modules/.bin/electron ]] || fail "run again, Capri still not installed: $out"
# (her first install's reload, in the background: done before this test's stand-ins go)
for _ in {1..50}; do grep -q '^hyprctl .*reload$' "$log" && break; sleep 0.1; done
grep -q '^hyprctl .*reload$' "$log" || fail "her first install didn't load the config again"
# Asked for again from setup, her downloads failing count from the start too (setup clears capri-update's count of
# runs in a row, not only what failed: else the third run, setup's or not, wrote the release down as failing)
echo b >"$t/up/app.js"; g "$t/up" commit -qam two; g "$t/up" tag v0.2.0
touch "$t/offline"
step >/dev/null; step >/dev/null
[[ $(cut -f2 "$HOME/.local/state/capri-update-failed-retries" 2>/dev/null) == 1 ]] ||
    fail "setup didn't clear the count of failed runs: $(cat "$HOME/.local/state/capri-update-failed-retries" 2>/dev/null)"
rm "$t/offline"
echo "ok setup-capri"
