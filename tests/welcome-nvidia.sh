#!/usr/bin/env bash
# agros-welcome --system installs agros-nvidia (the NVIDIA driver loaded early in the boot) with an NVIDIA graphics card
# (PCI vendor 10de, a display controller: VGA or 3D), as it does the Legion's camera switch; not for an NVIDIA card's
# sound part alone, nor for another vendor's graphics
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
mkdir -p "$t/bin"
# (pacman's installs written down, nothing installed; VMware's build refused: sudo fails)
printf '#!/bin/sh\necho "pacman $*" >>"%s/ran"\n' "$t" >"$t/bin/pacman"
printf '#!/bin/sh\nexit 1\n' >"$t/bin/sudo"
chmod +x "$t/bin/pacman" "$t/bin/sudo"
pci() {  # <address> <vendor> <class>
    mkdir -p "$t/sys/bus/pci/devices/$1"
    echo "$2" >"$t/sys/bus/pci/devices/$1/vendor"; echo "$3" >"$t/sys/bus/pci/devices/$1/class"
}
# installs: whether the system's part installed agros-nvidia
installs() {
    rm -f "$t/ran"
    SUDO_USER=me SYSFS=$t/sys PATH=$t/bin:$PATH bash -c 'source "$1"; system_part' _ "$here/.local/bin/agros-welcome" \
        >/dev/null 2>&1 || true
    grep -q '^pacman -S --needed --noconfirm .*agros-nvidia' "$t/ran" 2>/dev/null
}
pci 0000:00:02.0 0x8086 0x030000  # Intel graphics
pci 0000:01:00.1 0x10de 0x040300  # an NVIDIA card's sound
installs && fail "agros-nvidia installed with no NVIDIA graphics"
pci 0000:01:00.0 0x10de 0x030000  # NVIDIA, VGA
installs || fail "agros-nvidia not installed with an NVIDIA card"
rm -r "$t/sys/bus/pci/devices/0000:01:00.0"; pci 0000:01:00.0 0x10de 0x030200  # NVIDIA, 3D (a laptop's second GPU)
installs || fail "agros-nvidia not installed with an NVIDIA 3D controller"
echo "ok welcome-nvidia"
