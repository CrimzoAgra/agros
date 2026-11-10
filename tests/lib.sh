# shellcheck shell=bash
# Sourced first by every test: $here (the repo), $t (a throwaway folder, removed on exit) and fail
here=$(cd "$(dirname "$0")/.." && pwd)
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
# The caller's XDG folders (a desktop session sets XDG_CONFIG_HOME to the real ~/.config) never reach a test: with them
# a test's throwaway HOME still wrote into the real home
unset XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME XDG_CACHE_HOME
fail() { echo "FAIL: $*"; exit 1; }
