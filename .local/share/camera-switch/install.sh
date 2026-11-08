#!/usr/bin/env bash
# Installs the camera switch service. Run with: sudo bash ~/.local/share/camera-switch/install.sh
# Remove: sudo systemctl disable --now camera-switch && sudo rm /etc/systemd/system/camera-switch.service /usr/local/bin/camera-switchd
#   /etc/udev/rules.d/90-camera-switch.rules
set -e
[[ $EUID -eq 0 ]] || { echo "Run with sudo"; exit 1; }
src=$(dirname "$(readlink -f "$0")")

install -m 755 "$src/camera-switchd" /usr/local/bin/camera-switchd
cat >/etc/systemd/system/camera-switch.service <<'EOF'
[Unit]
Description=Physical camera switch (turns the camera off/on like on Windows)
After=systemd-udevd.service

[Service]
ExecStart=/usr/local/bin/camera-switchd
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF
# The camera found again on the USB bus (after suspend, a USB reset) comes back enabled: switched off again unless the
# switch's position saved is on (the service only applies it at boot and when the switch moves; an empty or missing
# state is off, as the service reads it)
cat >/etc/udev/rules.d/90-camera-switch.rules <<'EOF'
# Installed by dotfiles/.local/share/camera-switch/install.sh
ACTION=="add", SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", ATTR{idVendor}=="04f2", ATTR{idProduct}=="b83e", RUN+="/bin/sh -c 'grep -qx on /var/lib/camera-switch/state || echo 0 >/sys%p/authorized'"
EOF
udevadm control --reload
systemctl daemon-reload
# Start from "on" (camera connected); the next flip of the switch sets the real position. Run again: the switch's
# position kept (an "on" there would let the camera back in with the switch off)
mkdir -p /var/lib/camera-switch && { [[ -f /var/lib/camera-switch/state ]] || echo on >/var/lib/camera-switch/state; }
systemctl enable camera-switch.service
systemctl restart camera-switch.service
sleep 1
systemctl --no-pager --lines=3 status camera-switch.service | head -8
echo
echo "Done. Flip the camera switch: you should see 'Camera off' / 'Camera on'."
