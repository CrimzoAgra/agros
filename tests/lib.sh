# shellcheck shell=bash
# Sourced first by every test: $here (the repo), $t (a throwaway folder, removed on exit) and fail
here=$(cd "$(dirname "$0")/.." && pwd)
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
fail() { echo "FAIL: $*"; exit 1; }
