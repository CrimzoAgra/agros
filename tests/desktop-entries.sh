#!/usr/bin/env bash
# The launcher entries in .local/share/applications: valid desktop entries (desktop-file-validate, its errors, not its
# hints), and every Exec quoted as the spec has it: an argument quoted whole ("--window-title=Phone Link"), not in part
# (--window-title="Phone Link": some launchers take the quotes as part of it)
set -euo pipefail
. "$(dirname "$0")/lib.sh"
for f in "$here"/.local/share/applications/*.desktop; do
    if command -v desktop-file-validate >/dev/null; then
        out=$(desktop-file-validate "$f" 2>&1) || fail "${f##*/} isn't a valid desktop entry: $out"
        if grep -v ': hint: ' <<<"$out" | grep -q .; then fail "${f##*/}: $out"; fi
    fi
    while IFS= read -r exec; do
        # (each argument: a run of anything but spaces and quotes, or a quoted string; a quote inside one is wrong)
        rest=$(sed -E 's/"([^"\\]|\\.)*"//g' <<<"$exec")
        if [[ $rest == *'"'* ]]; then fail "${f##*/}: an unclosed quote in Exec=$exec"; fi
        if grep -qE '[^ ]"([^"\\]|\\.)*"|"([^"\\]|\\.)*"[^ ]' <<<"$exec"; then
            fail "${f##*/}: an argument quoted in part in Exec=$exec"
        fi
    done < <(sed -n 's/^Exec=//p' "$f")
done
grep -qx 'Exec=scrcpy "--window-title=Phone Link" .*' "$here/.local/share/applications/phone-link.desktop" ||
    fail "Phone Link's window title not one argument"
echo "ok desktop-entries"
