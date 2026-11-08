#!/usr/bin/env bash
# agros-personal: the restore and save commands it runs setup.sh with (the repo found where setup recorded it)
set -uo pipefail
. "$(dirname "$0")/lib.sh"
export HOME=$t/home XDG_STATE_HOME=
mkdir -p "$HOME/.local/state" "$t/repo"
echo "$t/repo" >"$HOME/.local/state/dotfiles-repo"
printf '#!/bin/sh\necho "$*"\n' >"$t/repo/setup.sh"; chmod +x "$t/repo/setup.sh"
p=$here/.local/bin/agros-personal
[[ $("$p") == "--only personal" ]] || fail "restore: $("$p")"
[[ $("$p" /run/media/usb) == "--personal /run/media/usb --only personal" ]] || fail "restore from a folder: $("$p" /run/media/usb)"
[[ $("$p" --save) == "--save-personal" ]] || fail "save: $("$p" --save)"
[[ $("$p" --save /mnt/x) == "--save-personal /mnt/x" ]] || fail "save to a folder: $("$p" --save /mnt/x)"
rm "$HOME/.local/state/dotfiles-repo"
"$p" >/dev/null 2>&1 && fail "ran with no repo"
echo "ok agros-personal"
