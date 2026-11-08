#!/usr/bin/env bash
# Bluetooth on at boot: enable the service and let BlueZ power the adapter on by itself.
# Run with: sudo bash system/bluetooth-setup.sh
# (The rest of the fix is in the user config: ~/.config/caelestia/user/desktop.lua unblocks + powers on at login,
#  and the Caelestia overlay's "bluetooth pairing" patch lets the bar popout pair new devices.)
set -e
[[ $EUID -eq 0 ]] || { echo "Run with sudo"; exit 1; }
conf=/etc/bluetooth/main.conf
[[ -f $conf ]] || { echo "$conf not found (is bluez installed?)"; exit 1; }
if grep -qE '^#?\s*AutoEnable=' "$conf"; then
    sed -i -E 's/^#?\s*AutoEnable=.*/AutoEnable=true/' "$conf"
else
    printf '\n[Policy]\nAutoEnable=true\n' >>"$conf"
fi
systemctl enable --now bluetooth.service
rfkill unblock bluetooth
# After sleep: back on if it was on (waking resets the adapter, which comes back off)
install -m 755 "$(dirname "$0")/bluetooth-resume" /usr/lib/systemd/system-sleep/bluetooth-resume
echo "Bluetooth enabled."
