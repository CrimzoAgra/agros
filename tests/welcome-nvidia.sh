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
# How the system part went, its terminal's last line: VMware's build failing (sudo refused here) isn't "Done.", which
# read as all of it in with the failure scrolled away above; everything in is
out=$(SUDO_USER=me SYSFS=$t/sys PATH=$t/bin:$PATH bash -c 'source "$1"; system_part' _ "$here/.local/bin/agros-welcome" 2>&1) &&
    fail "the system part exited 0 with VMware not installed"
[[ $(tail -1 <<<"$out") == "Not all of it installed"* ]] || fail "a failed install's last line: $(tail -1 <<<"$out")"
# (VMware built: sudo, its modules and services stubbed working)
for c in sudo modprobe systemctl; do printf '#!/bin/sh\nexit 0\n' >"$t/bin/$c"; chmod +x "$t/bin/$c"; done
out=$(SUDO_USER=me SYSFS=$t/sys PATH=$t/bin:$PATH bash -c 'source "$1"; system_part' _ "$here/.local/bin/agros-welcome" 2>&1) ||
    fail "the system part failed with everything installed: $out"
[[ $(tail -1 <<<"$out") == Done. ]] || fail "everything installed, not said done: $(tail -1 <<<"$out")"
echo "ok welcome-nvidia"
