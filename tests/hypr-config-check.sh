#!/usr/bin/env bash
# hypr-config-check: Hyprland --verify-config's errors written down (and gone once it's fine), against a stand-in Hyprland;
# run as the pacman hook runs it (no XDG_RUNTIME_DIR: Hyprland refuses to start) it gets a runtime folder of its own,
# and Hyprland refusing to run at all is "couldn't check", not the config's error; the config told it's only a check
set -uo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
fail() { echo "FAIL: $*"; exit 1; }
mkdir -p "$t/bin" "$t/home"
cat >"$t/bin/Hyprland" <<H
#!/bin/sh
[ "\$1" = --verify-config ] || exit 9
[ -z "\$HYPRLAND_INSTANCE_SIGNATURE" ] || { echo "asked the running one"; exit 8; }
# (as Hyprland 0.57 does, before reading any config)
if [ -n "\$REFUSE" ] || [ -z "\$XDG_RUNTIME_DIR" ] || [ ! -d "\$XDG_RUNTIME_DIR" ]; then
    printf '\033[1;31m[ ERROR ]\033[0m XDG_RUNTIME_DIR is not set. Make sure you are running on a real, properly set up user.\n'; exit 1
fi
echo "\$XDG_RUNTIME_DIR \${DOTS_VERIFY_CONFIG:-}" >"$t/env"
if [ -n "\$BROKEN" ]; then printf 'DEBUG noise\n\n======== Config parsing result:\n\nrequire("user.apps"): nil value (field x)\n'; exit 1; fi
printf '======== Config parsing result:\n\nconfig ok\n'
H
chmod +x "$t/bin/Hyprland"
mkdir -p "$t/run"
run() { HOME=$t/home XDG_STATE_HOME=$t/state PATH=$t/bin:$PATH HYPRLAND_INSTANCE_SIGNATURE=live XDG_RUNTIME_DIR=$t/run \
    "$here/.local/bin/hypr-config-check"; }
BROKEN=1 run >/dev/null && fail "a broken config passed"
grep -qx 'require("user.apps"): nil value (field x)' "$t/state/hypr-config-check" || fail "its error wasn't written down: $(cat "$t/state/hypr-config-check")"
run >/dev/null || fail "a good config failed"
[[ -e $t/state/hypr-config-check ]] && fail "the old errors stayed once it's fine"
[[ $(cat "$t/env") == "$t/run 1" ]] || fail "not told it's only a check (DOTS_VERIFY_CONFIG), or the session's runtime folder not used: $(cat "$t/env")"

# As from the pacman hook (runuser: no XDG_RUNTIME_DIR): a runtime folder of its own, removed after
BROKEN=1 run >/dev/null 2>&1  # (errors written down before: they stay until a real check says otherwise)
out=$(XDG_RUNTIME_DIR='' HOME=$t/home XDG_STATE_HOME=$t/state PATH=$t/bin:$PATH env -u XDG_RUNTIME_DIR \
    "$here/.local/bin/hypr-config-check") || fail "without XDG_RUNTIME_DIR the check failed: $out"
own=$(cut -d' ' -f1 "$t/env")
[[ -n $own && $own != "$t/run" && ! -e $own ]] || fail "no runtime folder of its own, or it was left behind: $own"
[[ ! -e $t/state/hypr-config-check ]] || fail "a good config's check without XDG_RUNTIME_DIR didn't clear the old errors"
# Hyprland refusing to run at all: couldn't check (2), not written down as the config's error
out=$(REFUSE=1 run 2>&1); rc=$?
((rc == 2)) || fail "Hyprland refusing to run not said as couldn't check (exit $rc): $out"
[[ ! -e $t/state/hypr-config-check ]] || fail "Hyprland's refusal written down as a config error: $(cat "$t/state/hypr-config-check")"
[[ $out == *"couldn't be checked"*"XDG_RUNTIME_DIR is not set"* && $out != *$'\033'* ]] || fail "the refusal not said: $out"
echo "ok hypr-config-check"
