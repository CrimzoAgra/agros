# shellcheck shell=bash
# Sourced first by every test: $here (the repo), $t (a throwaway folder, removed on exit) and fail
# shellcheck disable=SC2034  # (used by the tests that source this)
here=$(cd "$(dirname "$0")/.." && pwd)
t=$(mktemp -d)
# A test's own cleanup (stand-ins to stop) registered with on_exit '<commands>', not a trap of its own (it replaced this
# one, and $t stayed): run at exit with errexit off (a kill of one already gone failed a test that had passed), then
# $t removed, the test's own status kept
cleanups=()
on_exit() { cleanups+=("$1"); }
_on_exit() {
    local rc=$? c
    set +e
    for c in "${cleanups[@]}"; do eval "$c"; done 2>/dev/null
    rm -rf "$t"
    exit "$rc"
}
trap _on_exit EXIT
# The caller's XDG folders (a desktop session sets XDG_CONFIG_HOME to the real ~/.config) never reach a test: with them
# a test's throwaway HOME still wrote into the real home
unset XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME XDG_CACHE_HOME
# Nor the live desktop: no session bus (a test's made-up failure reached the real notifications), no Hyprland, no
# Wayland, no user manager. A test that needs one stubs it. (A bus address that doesn't exist: unset, libdbus would
# look in XDG_RUNTIME_DIR or start one)
mkdir -m700 "$t/.xdg-run"
export XDG_RUNTIME_DIR=$t/.xdg-run DBUS_SESSION_BUS_ADDRESS=unix:path=$t/.xdg-run/no-bus
unset HYPRLAND_INSTANCE_SIGNATURE WAYLAND_DISPLAY DISPLAY
# Nor the machine's upstream gate (update-gate): its gated list and approved versions the test's own, none unless it
# makes them (on an AgrOS machine a test read /etc/pacman.d/agros-gate.conf and fetched the real approved list)
export AGROS_GATE=$t/agros-gate.conf AGROS_GATE_CACHE=$t/agros-approved
# No __pycache__ left in the checkout by the Python a test loads: a python3 first on PATH, with -B (the tests'
# python3 -I ignores the variable)
export PYTHONDONTWRITEBYTECODE=1
mkdir "$t/.py" && printf '#!/bin/sh\nexec %s -B "$@"\n' "$(command -v python3)" >"$t/.py/python3" && chmod +x "$t/.py/python3"
export PATH=$t/.py:$PATH
fail() { echo "FAIL: $*"; exit 1; }
# A part of a test this machine can't run, said; on CI a failure (CI has all a test needs, and its pass approves that
# Hyprland for AgrOS's machines: the upstream gate)
skipped() { [[ -z ${CI:-} ]] || fail "skipped on CI: $*"; echo "($*)"; }
# Upstream's next release (its main branch: Caelestia's, Lutris's, Hyprland's): a check against it that doesn't fit, or
# couldn't be fetched, said with ahead, never a failure. Neither the published [agros] nor an older Arch undoes a change
# on main, so ci/test-passes.sh read one as AgrOS's own code and nothing went out; the release itself is checked as
# installed, and held back alone. Said on the test's last line by ok_line, "ok <test> (AHEAD: ...)", which CI's held
# issue lists (ci/report.sh: nothing held, AgrOS's change to adapt before that release)
ahead=()
ahead() { ahead+=("$*"); }
# ok_line <test> [<note>]: the test's last line, with what doesn't fit upstream's next release
ok_line() {
    local l="ok $1${2:+ ($2)}"
    ((${#ahead[@]} == 0)) || l+=" (AHEAD: $(printf '%s; ' "${ahead[@]}" | sed 's/; $//'))"
    echo "$l"
}
