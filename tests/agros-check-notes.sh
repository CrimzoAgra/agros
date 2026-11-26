#!/usr/bin/env bash
# agros-check --notify's notes: a .pacnew in /etc is said in its own notification, never as "Caelestia's Hyprland
# config has an update" when Caelestia's config has none (one said for an earlier version had left its mark, and any
# other note then sent that notification again, its mark wiped)
set -uo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
export HOME=$t/home XDG_STATE_HOME=$t/home/.local/state
mkdir -p "$XDG_STATE_HOME" "$t/etc/pacman.d"
# (Hyprland's config check and the shells: stand-ins, all fine; notifications written down)
printf '#!/bin/sh\nprintf "======== Config parsing result:\\n\\nconfig ok\\n"\n' >"$t/Hyprland"
printf '#!/bin/sh\nexit 0\n' >"$t/qs"
# shellcheck disable=SC2016  # (expanded by the stand-in)
printf '#!/bin/sh\nprintf "%%s|" "$@" >>"%s"; echo >>"%s"\n' "$t/notified" "$t/notified" >"$t/notify-send"
chmod +x "$t/Hyprland" "$t/qs" "$t/notify-send"
# (an earlier version's update said before: its mark left)
echo 0123abc >"$XDG_STATE_HOME/dotfiles-check-hypr-notified"
: >"$t/etc/pacman.d/mirrorlist.pacnew"
PATH=$t:$PATH NOTIFY_WHEN_UP_TRIES=1 "$here/.local/bin/agros-check" --notify >/dev/null 2>&1
grep -q "Config files to look at after an update" "$t/notified" 2>/dev/null || fail "a .pacnew not said: $(cat "$t/notified" 2>/dev/null)"
grep -q "Caelestia's Hyprland config has an update" "$t/notified" &&
    fail "Caelestia's Hyprland config said to have an update it hasn't (another note there)"
[[ $(cat "$XDG_STATE_HOME/dotfiles-check-hypr-notified") == 0123abc ]] || fail "the Hyprland update's mark wiped"
ok_line agros-check-notes
