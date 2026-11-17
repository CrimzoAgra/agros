#!/usr/bin/env bash
# agros-welcome: a step that failed at the first login (no network: the Flatpaks, VSCodium's extensions) is tried again
# at the next one, the service starting again for it (its ConditionPathExists: "done", all steps); the VSCodium step
# failing three logins in a row counts as done (an extension gone from its store failed it at every login)
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
h=$t/home sb=$t/bin; mkdir -p "$h/.local/bin" "$h/.config/VSCodium" "$sb"
for c in qs caelestia hyprctl gsettings notify-send systemctl pacman foot; do
    printf '#!/bin/sh\n[ "$1 $2" = "list --all" ] && echo /x/quickshell/caelestia/shell.qml\nexit 0\n' >"$sb/$c"
done
printf '#!/bin/sh\nexit 1\n' >"$sb/flatpak"                  # (offline)
# (beside it: the programs it runs are the ones beside itself)
cp -r "$here/.local/bin/." "$h/.local/bin/"
printf '#!/bin/sh\nexit 1\n' >"$h/.local/bin/flatpak-bundle-update"; printf '#!/bin/sh\nexit 0\n' >"$h/.local/bin/lutris-library"
printf '#!/bin/sh\nexit 0\n' >"$h/.local/bin/caelestia-overlay"; cp "$h/.local/bin/caelestia-overlay" "$h/.local/bin/caelestia-restart"
printf '#!/bin/sh\n[ "$1" = --install-extension ] && exit 1\nexit 0\n' >"$sb/codium"  # (offline)
printf '#!/bin/sh\nexit 1\n' >"$sb/librewolf"; printf '#!/bin/sh\nexit 1\n' >"$sb/spicetify"
# (the offer: its text noted, the notification server up)
printf '#!/bin/sh\nprintf "%%s\\n" "$@" >>"%s"\n' "$t/offer" >"$sb/notify-send"
echo some.extension >"$h/.config/VSCodium/extensions.txt"
# (the shell up at its second look; the looks and the overlay's lock taken noted in order)
printf '#!/bin/sh\necho qs-running >>"%s/order"\n[ -e "%s/up" ] && exit 0\ntouch "%s/up"; exit 1\n' "$t" "$t" "$t" >"$h/.local/bin/qs-running"
printf '#!/bin/sh\necho flock >>"%s/order"\n' "$t" >"$sb/flock"
chmod +x "$sb"/* "$h"/.local/bin/*
env -i HOME="$h" PATH="$sb:/usr/bin" bash "$h/.local/bin/agros-welcome" >/dev/null 2>&1 </dev/null || true
st=$h/.local/state/agros
# The shell waited for before caelestia-start's lock: this unit starts beside Hyprland's start, and the lock taken
# first went through before caelestia-start took it (the first wallpaper and colours then set twice at once)
[[ $(head -3 "$t/order" | paste -sd' ') == "qs-running qs-running flock" ]] ||
    fail "caelestia-start's lock taken before the shell was waited for: $(paste -sd' ' "$t/order")"
# The offer (in the background), marked once sent, and not saying all is installed when a step failed
for _ in $(seq 50); do [[ -e $st/offered ]] && break; sleep 0.1; done
[[ -e $st/offered ]] || fail "the offer sent but not marked offered"
grep -q "didn't finish" "$t/offer" && ! grep -q "Everything is installed" "$t/offer" ||
    fail "a step failed, yet the offer said: $(cat "$t/offer")"
# ...and not marked when no notification server took it (sent to nobody): offered again at the next login
rm "$st/offered"; printf '#!/bin/sh\nexit 1\n' >"$sb/notify-send"
env -i HOME="$h" PATH="$sb:/usr/bin" NOTIFY_WHEN_UP_TRIES=2 bash "$h/.local/bin/agros-welcome" >/dev/null 2>&1 </dev/null || true
sleep 2
[[ ! -e $st/offered ]] || fail "an offer that reached no notification server marked offered"
[[ -e $st/done-flatpaks ]] && fail "test setup: the Flatpaks step didn't fail"
[[ -e $st/done-vscodium ]] && fail "the VSCodium step marked done with its extension's install failed (offline): never tried again"
# The service starts again at a login while any of its conditions holds (all "|!": a file missing), as systemd reads
# triggering conditions: a step not done yet, or the offer not answered yet
unit=$(cat "$here/packages/agros-welcome/agros-welcome.service")
mapfile -t conds < <(sed -n 's/^ConditionPathExists=//p' <<<"$unit")
for c in "${conds[@]}"; do [[ $c == '|!%S/'* ]] || fail "a condition that isn't one of either (|!): $c"; done
((${#conds[@]})) || fail "agros-welcome.service has no conditions: it runs at every login"
runs() { local c; for c in "${conds[@]}"; do [[ -e $h/.local/state/${c#|!%S/} ]] || return 0; done; return 1; }
runs || fail "the Flatpaks step failed, but agros-welcome.service never starts again to retry it (${conds[*]})"
saved=$(ls "$st")
touch "$st/done"
runs || fail "an offer not answered yet (no offered), but agros-welcome.service never starts again to make it"
touch "$st/offered"
runs && fail "all done and the offer answered, yet agros-welcome.service starts at every login"
rm "$st/done"
runs || fail "the offer answered but a step not done, yet agros-welcome.service never starts again to retry it"
rm "$st/offered"
[[ $(ls "$st") == "$saved" ]] || fail "test setup: the state not put back"
# Kept active once its script exits: the offer's notification waits for its answer in the background, in the unit, and
# a unit that ended killed it (its buttons did nothing, never marked offered); logging out still stops it (PartOf)
grep -qx 'RemainAfterExit=yes' <<<"$unit" && grep -qx 'PartOf=graphical-session.target' <<<"$unit" ||
    fail "agros-welcome.service ends when its script does (the offer's waiter killed with it), or outlives the session: $unit"
# ...but not for good: an extension that's gone from its store failed the step at every login. The third login in a
# row it fails, it counts as done (the Flatpaks, offline, still not)
# (few tries for the offer that fails: not a minute's notify-when-up left running in the background after the test)
for _ in 2 3; do env -i HOME="$h" PATH="$sb:/usr/bin" NOTIFY_WHEN_UP_TRIES=2 bash "$h/.local/bin/agros-welcome" >/dev/null 2>&1 </dev/null || true; done
[[ -e $st/done-vscodium ]] || fail "the VSCodium step still tried again after failing three logins in a row"
[[ -e $st/done-flatpaks ]] && fail "the Flatpaks step marked done offline"
# An account set up before the offer waited for its answer (done, never marked offered: the unit's end killed the
# offer, and none has the offer's own mark): not offered again, weeks later, now the unit starts while offered is
# missing. One this version offered and that wasn't answered is offered again
# (the offers above that failed, in the background, given up first: not one of them noted here)
sleep 2
touch "$st/done"; rm -f "$st/offered" "$st/offer-sent" "$t/offer"
printf '#!/bin/sh\nprintf "%%s\\n" "$@" >>"%s"\n' "$t/offer" >"$sb/notify-send"
env -i HOME="$h" PATH="$sb:/usr/bin" bash "$h/.local/bin/agros-welcome" >/dev/null 2>&1 </dev/null || true
sleep 1
[[ -e $st/offered && ! -e $t/offer ]] || fail "an account set up before this version offered again: $(cat "$t/offer" 2>/dev/null)"
rm "$st/offered"; touch "$st/offer-sent"
env -i HOME="$h" PATH="$sb:/usr/bin" bash "$h/.local/bin/agros-welcome" >/dev/null 2>&1 </dev/null || true
for _ in $(seq 50); do [[ -e $t/offer ]] && break; sleep 0.1; done
[[ -e $t/offer ]] || fail "an offer this version made, unanswered, not made again at the next login"
echo "ok welcome-retry"
