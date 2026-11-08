#!/usr/bin/env bash
# vm-screen-follow: nothing outside a VM; in one, a screen whose preferred mode changed (VMware's window resized, full
# screen) gets Hyprland's config reloaded, and only then
set -euo pipefail
. "$(dirname "$0")/lib.sh"
mkdir -p "$t/bin" "$t/sys/class/drm/card0-Virtual-1"
echo connected >"$t/sys/class/drm/card0-Virtual-1/status"
printf '#!/bin/sh\nexit "${VIRT:-0}"\n' >"$t/bin/systemd-detect-virt"
printf '#!/bin/sh\necho "UDEV  [12.3] change   /devices/pci0000:00/drm/card0 (drm)"\n' >"$t/bin/udevadm"
cat >"$t/bin/hyprctl" <<EOF
#!/bin/sh
case \$1 in monitors) echo '[{"name": "Virtual-1", "width": 2258, "height": 1359}]' ;; reload) echo reload >>"$t/reloads" ;; esac
EOF
chmod +x "$t"/bin/*
run() { SYSFS=$t/sys PATH=$t/bin:$PATH timeout 10 "$here/.local/bin/vm-screen-follow"; }

# (outside a VM with a screen whose preferred mode changed: still nothing)
printf '2560x1600\n2258x1359\n' >"$t/sys/class/drm/card0-Virtual-1/modes"
VIRT=1 run || fail "outside a VM it didn't just exit"
[[ ! -e $t/reloads ]] || fail "outside a VM it reloaded"
printf '2258x1359\n4096x2160\n' >"$t/sys/class/drm/card0-Virtual-1/modes"
run
[[ ! -e $t/reloads ]] || fail "reloaded with the screen already in its preferred mode"
printf '2560x1600\n2258x1359\n' >"$t/sys/class/drm/card0-Virtual-1/modes"
run
[[ $(cat "$t/reloads" 2>/dev/null) == reload ]] || fail "a new preferred mode (full screen) didn't reload Hyprland's config"
echo "ok vm-screen-follow"
