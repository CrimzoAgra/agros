#!/usr/bin/env bash
# agros-thunar-usage: the Thunar plugin builds as its PKGBUILD builds it (every symbol it uses found: linked with
# -z defs) and has the three functions Thunar looks for, without which Thunar refuses to load it
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
pkg-config --exists thunarx-3 || { echo "skip thunar-usage (no Thunar headers)"; exit 0; }
cp "$here/packages/agros-thunar-usage/thunar-usage.c" "$t/"
# shellcheck disable=SC1091  # (the PKGBUILD's build(), run where its source is)
(cd "$t" && . "$here/packages/agros-thunar-usage/PKGBUILD" && CFLAGS="-Wall -Werror" LDFLAGS='' build) >"$t/out" 2>&1 ||
    fail "doesn't build: $(tail -3 "$t/out")"
for s in thunar_extension_initialize thunar_extension_shutdown thunar_extension_list_types; do
    grep -qw "$s" <<<"$(nm -D --defined-only "$t/agros-thunar-usage.so")" || fail "$s not exported"
done
echo "ok thunar-usage"
