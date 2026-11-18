#!/usr/bin/env bash
# The commands you might type (agros-*, agros-check): --help and -h print what the command does and exit 0; an
# option it doesn't know is refused (exit 2), with nothing run. agros-welcome --help ran the first login's part,
# agros-links --help linked and copied, agros-check --help ran the check, agros-each-user --help looked for a
# command named --help in every home
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
mkdir -p "$t/home" "$t/lib/bin"
# (anything a command runs past its options: a mark that it ran)
for c in hyprctl systemctl notify-send getent pacman flatpak qs caelestia flock; do stub "$c" "touch '$t/ran-$c'"; done
# agros-check's old name (a home's copy of desktop.lua from before still runs it): agros-check itself
out=$(env -i HOME="$t/home" PATH="$t/bin:/usr/bin:/bin" AGROS_LIB="$t/lib" bash "$here/.local/bin/dotfiles-check" --help 2>&1) ||
    fail "dotfiles-check --help failed: $out"
[[ $out == *"agros-check --notify"* ]] || fail "dotfiles-check isn't agros-check: $out"
for c in agros-links agros-each-user agros-welcome agros-check agros-personal; do
    for h in --help -h; do
        out=$(env -i HOME="$t/home" PATH="$t/bin:/usr/bin:/bin" AGROS_LIB="$t/lib" bash "$here/.local/bin/$c" "$h" 2>&1) ||
            fail "$c $h failed: $out"
        [[ $out == *"$c"* ]] || fail "$c $h didn't say how it's used: $out"
    done
    rc=0
    out=$(env -i HOME="$t/home" PATH="$t/bin:/usr/bin:/bin" AGROS_LIB="$t/lib" bash "$here/.local/bin/$c" --no-such-option 2>&1) || rc=$?
    ((rc == 2)) || fail "$c took an option it doesn't know (exit $rc): $out"
    [[ $out == *"--no-such-option"* ]] || fail "$c didn't say which option: $out"
done
ran=$(cd "$t" && echo ran-*)
[[ $ran == "ran-*" ]] || fail "a command ran for --help or an unknown option: $ran"
[[ -z $(ls -A "$t/home") ]] || fail "a command wrote into the home for --help or an unknown option: $(find "$t/home")"
echo "ok agros-help"
