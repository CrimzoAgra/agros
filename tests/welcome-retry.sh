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
chmod +x "$sb"/* "$h"/.local/bin/*
env -i HOME="$h" PATH="$sb:/usr/bin" bash "$h/.local/bin/agros-welcome" >/dev/null 2>&1 </dev/null || true
st=$h/.local/state/agros
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
cond=$(sed -n 's/^ConditionPathExists=!%S\///p' "$here/packages/agros-welcome/agros-welcome.service")
[[ -e $h/.local/state/$cond ]] && fail "the Flatpaks step failed, but $cond is there: agros-welcome.service never starts again to retry it"
# ...but not for good: an extension that's gone from its store failed the step at every login. The third login in a
# row it fails, it counts as done (the Flatpaks, offline, still not)
# (few tries for the offer that fails: not a minute's notify-when-up left running in the background after the test)
for _ in 2 3; do env -i HOME="$h" PATH="$sb:/usr/bin" NOTIFY_WHEN_UP_TRIES=2 bash "$h/.local/bin/agros-welcome" >/dev/null 2>&1 </dev/null || true; done
[[ -e $st/done-vscodium ]] || fail "the VSCodium step still tried again after failing three logins in a row"
[[ -e $st/done-flatpaks ]] && fail "the Flatpaks step marked done offline"
echo "ok welcome-retry"
