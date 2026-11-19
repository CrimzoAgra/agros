#!/usr/bin/env bash
# Each file of Caelestia's installed shell that AgrOS names by its path (/etc/xdg/quickshell/caelestia/...: its
# wallpaper, which agros-hyprland-settings links into every new home's wallpaper folder and caelestia-start and
# agros-welcome set at a first login) is there in the caelestia-shell installed. A Caelestia release that moved or
# dropped one fails here, so CI holds that build back (ci/test-passes.sh) rather than putting out a shell whose first
# login has no wallpaper, its colours left on the fixed teal scheme, and a dead link in the wallpaper folder
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
src=/etc/xdg/quickshell/caelestia
[[ -d $src ]] || { skipped "Caelestia not installed: its paths not checked"; echo "skip caelestia-paths"; exit 0; }
# (every place AgrOS's own files name one: the programs, the settings, the packages, the system files; not the tests)
mapfile -t paths < <(cd "$here" && grep -rhoE "$src(/[A-Za-z0-9_.-]+)+" .local .config packages system 2>/dev/null |
    sed 's/[.]$//' | LC_ALL=C sort -u)
((${#paths[@]})) || fail "no path of Caelestia's found in AgrOS's files (this test's search broken?)"
for p in "${paths[@]}"; do
    [[ -e $p ]] || fail "$p, which AgrOS's files name ($(cd "$here" && grep -rlF "$p" .local .config packages system | paste -sd' ')), isn't in Caelestia $(pacman -Q caelestia-shell 2>/dev/null | cut -d' ' -f2)"
done
echo "ok caelestia-paths"
