# shellcheck shell=bash
# Sourced first by every test: $here (the repo), $t (a throwaway folder, removed on exit) and fail
# shellcheck disable=SC2034  # (used by the tests that source this)
here=$(cd "$(dirname "$0")/.." && pwd)
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
# The caller's XDG folders (a desktop session sets XDG_CONFIG_HOME to the real ~/.config) never reach a test: with them
# a test's throwaway HOME still wrote into the real home
unset XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME XDG_CACHE_HOME
# Nor the live desktop: no session bus (a test's made-up failure reached the real notifications), no Hyprland, no
# Wayland, no user manager. A test that needs one stubs it. (A bus address that doesn't exist: unset, libdbus would
# look in XDG_RUNTIME_DIR or start one)
mkdir -m700 "$t/.xdg-run"
export XDG_RUNTIME_DIR=$t/.xdg-run DBUS_SESSION_BUS_ADDRESS=unix:path=$t/.xdg-run/no-bus
unset HYPRLAND_INSTANCE_SIGNATURE WAYLAND_DISPLAY DISPLAY
# No __pycache__ left in the checkout by the Python a test loads: a python3 first on PATH, with -B (the tests'
# python3 -I ignores the variable)
export PYTHONDONTWRITEBYTECODE=1
mkdir "$t/.py" && printf '#!/bin/sh\nexec %s -B "$@"\n' "$(command -v python3)" >"$t/.py/python3" && chmod +x "$t/.py/python3"
export PATH=$t/.py:$PATH
fail() { echo "FAIL: $*"; exit 1; }
