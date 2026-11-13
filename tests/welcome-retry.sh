#!/usr/bin/env bash
# agros-welcome: a step that failed at the first login (no network: the Flatpaks) is tried again at the next one, as its
# own comment says. The service used to stop at done-vscodium (ConditionPathExists, now "done": all steps), and the vscodium step
# succeeds offline (an extension failing is only said), so once it's marked the service never runs again
set -euo pipefail
. "$(dirname "$0")/lib.sh"
h=$t/home sb=$t/bin; mkdir -p "$h/.local/bin" "$h/.config/VSCodium" "$sb"
for c in qs caelestia hyprctl gsettings notify-send systemctl pacman foot; do
    printf '#!/bin/sh\n[ "$1 $2" = "list --all" ] && echo /x/quickshell/caelestia/shell.qml\nexit 0\n' >"$sb/$c"
done
printf '#!/bin/sh\nexit 1\n' >"$sb/flatpak"                  # (offline)
printf '#!/bin/sh\nexit 1\n' >"$h/.local/bin/flatpak-bundle-update"
printf '#!/bin/sh\nexit 0\n' >"$h/.local/bin/caelestia-overlay"
printf '#!/bin/sh\n[ "$1" = --install-extension ] && exit 1\nexit 0\n' >"$sb/codium"  # (offline)
printf '#!/bin/sh\nexit 1\n' >"$sb/librewolf"; printf '#!/bin/sh\nexit 1\n' >"$sb/spicetify"
echo some.extension >"$h/.config/VSCodium/extensions.txt"
chmod +x "$sb"/* "$h"/.local/bin/*
env -i HOME="$h" PATH="$sb:/usr/bin" bash "$here/.local/bin/agros-welcome" >/dev/null 2>&1 </dev/null || true
st=$h/.local/state/agros
ls "$st" | grep '^done-' | tr '\n' ' '; echo
[[ -e $st/done-flatpaks ]] && fail "test setup: the Flatpaks step didn't fail"
cond=$(sed -n 's/^ConditionPathExists=!%S\///p' "$here/packages/agros-welcome/agros-welcome.service")
[[ -e $h/.local/state/$cond ]] && fail "the Flatpaks step failed, but $cond is there: agros-welcome.service never starts again to retry it"
echo "ok welcome-retry"
