#!/usr/bin/env bash
# agros-welcome's offer (restore your accounts, the system's part): marked offered on Later, or once the part picked has
# worked. A system part whose sudo was cancelled (the password prompt closed) or failed is offered again at the next
# login, and its terminal says why AgrOS asks for the password before sudo does
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
((EUID)) || fail "run as root: agros-welcome --system would run for real"
h=$t/home sb=$t/bin; mkdir -p "$h/.local/bin" "$sb"
for c in qs caelestia hyprctl gsettings systemctl pacman flatpak codium librewolf spicetify; do
    printf '#!/bin/sh\n[ "$1 $2" = "list --all" ] && echo /x/quickshell/caelestia/shell.qml\nexit 0\n' >"$sb/$c"
done
cp -r "$here/.local/bin/." "$h/.local/bin/"
for c in flatpak-bundle-update lutris-library caelestia-overlay caelestia-restart agros-personal; do
    printf '#!/bin/sh\nexit 0\n' >"$h/.local/bin/$c"
done
# (the button picked: $t/pick; the buttons offered: $t/actions; sudo's answer: $t/sudo-rc; the terminal runs its
# command, its output kept, then "end")
printf '#!/bin/sh\nfor a; do case $a in *=*) echo "$a" ;; esac; done >"%s/actions"\ncat "%s/pick"\n' "$t" "$t" >"$sb/notify-send"
printf '#!/bin/sh\nexit "$(cat "%s/sudo-rc")"\n' "$t" >"$sb/sudo"
printf '#!/bin/sh\nshift 2\n"$@" >>"%s/term" 2>&1 </dev/null\necho end >>"%s/term"\n' "$t" "$t" >"$sb/foot"
chmod +x "$sb"/* "$h"/.local/bin/*
st=$h/.local/state/agros
# login <button> [sudo's status]: a login with that button picked, waited for until its terminal is done (Later: until
# it's marked), so none of it is left running into the next one
login() {
    echo "$1" >"$t/pick"; echo "${2:-0}" >"$t/sudo-rc"; rm -f "$t/term" "$st/offered"
    env -i HOME="$h" PATH="$sb:/usr/bin:/bin" bash "$h/.local/bin/agros-welcome" >/dev/null 2>&1 </dev/null || true
    for _ in $(seq 100); do
        if [[ $1 == later ]]; then [[ -e $st/offered ]] && break; else [[ $(cat "$t/term" 2>/dev/null) == *end ]] && break; fi
        sleep 0.1
    done
}
login system 1
[[ $(cat "$t/term" 2>/dev/null) == *end ]] || fail "the system part's terminal never ran"
[[ -e $st/offered ]] && fail "sudo cancelled, yet marked offered: the hardware apps never offered again"
grep -q "password" "$t/term" || fail "the terminal doesn't say why AgrOS asks for the password: $(cat "$t/term")"
login system 0
[[ -e $st/offered ]] || fail "the system part worked, but not marked offered"
login restore
[[ -e $st/offered ]] || fail "the accounts restored, but not marked offered"
printf '#!/bin/sh\nexit 1\n' >"$h/.local/bin/agros-personal"
login restore
[[ -e $st/offered ]] && fail "the restore failed, yet marked offered"
login later
[[ -e $st/offered ]] || fail "Later picked, but not marked offered"
# The buttons' labels short enough for the notification centre to show them all: "Restore my accounts" was cut off,
# and the buttons after it not shown
[[ $(grep -c . "$t/actions") -ge 2 ]] || fail "the buttons not read: $(cat "$t/actions")"
while IFS= read -r a; do
    ((${#a} <= 16)) || fail "a button's label too long to show: $a"
done < <(sed 's/^[a-z]*=//' "$t/actions")
# Caelestia restarted while the offer waits (a Settings change at the first login): it numbers its notifications from 1
# again, and another one closed under the offer's number reached the offer's wait as its close (nothing printed), which
# marked it offered with nothing picked. Given up on as the server goes (gdbus: "does not have an owner", once), and sent
# again: its second showing's answer is the one taken
printf '#!/bin/sh\nexit 0\n' >"$h/.local/bin/agros-personal"
printf '#!/bin/sh\n[ -e %s/restarted ] && exec sleep 30\ntouch %s/restarted; sleep 1\necho "The name org.freedesktop.Notifications does not have an owner"\nexec sleep 30\n' \
    "$t" "$t" >"$sb/gdbus"
# shellcheck disable=SC2016  # (expanded by the stand-in)
printf '#!/bin/sh\necho x >>%s/sent\n[ "$(grep -c . %s/sent)" -gt 1 ] && exec cat %s/pick\nsleep 3\n' "$t" "$t" "$t" >"$sb/notify-send"
chmod +x "$sb/gdbus" "$sb/notify-send"
login restore
[[ $(cat "$t/term" 2>/dev/null) == *end && -e $st/offered && $(grep -c . "$t/sent") == 2 ]] ||
    fail "the offer, waiting as Caelestia restarted, not sent again, or another notification's close taken for its answer (sent $(grep -c . "$t/sent" 2>/dev/null) times)"
echo "ok welcome-offer"
