#!/usr/bin/env bash
# The setup steps on other hardware (a stand-in /sys): the Bluetooth setup only with an adapter, NVIDIA's early loading
# only with an NVIDIA graphics card (not its audio function, not the driver alone), the camera switch's USB check without
# lsusb; and packages from the AUR with no AUR helper said so, not "command not found"
set -euo pipefail
. "$(dirname "$0")/lib.sh"
export HOME=$t/home log=$t/calls SYSFS=$t/sys MODULES_DIR=$t/modules
mkdir -p "$HOME" "$t/bin" "$SYSFS/bus/pci/devices/0000:01:00.1" "$SYSFS/bus/usb/devices/1-1" "$SYSFS/class/bluetooth"
# Stand-ins noting each call: nothing installed or changed. modinfo: an NVIDIA driver only for the kernel updated since
# boot (the packages step's update took the running one's modules away: a bare modinfo finds none)
mkdir -p "$MODULES_DIR/1.0-running" "$MODULES_DIR/2.0-updated"
printf '#!/bin/sh\necho "sudo $*" >>"$log"\n' >"$t/bin/sudo"
printf '#!/bin/sh\n[ "$1 $2" = "-k 2.0-updated" ]\n' >"$t/bin/modinfo"
printf '#!/bin/sh\n[ "$1" != is-active ] || exit 1\n' >"$t/bin/systemctl"
chmod +x "$t/bin/"*
export PATH=$t/bin:$PATH
echo 0x10de >"$SYSFS/bus/pci/devices/0000:01:00.1/vendor"; echo 0x040300 >"$SYSFS/bus/pci/devices/0000:01:00.1/class"
echo 04f2 >"$SYSFS/bus/usb/devices/1-1/idVendor"; echo b83e >"$SYSFS/bus/usb/devices/1-1/idProduct"
system() {
    : >"$log"
    repo=$here yes=true bash -c 'source "$1/setup/lib.sh"; source "$1/setup/modules/80-system.sh"; module_system' _ "$here" \
        >"$t/out" 2>&1 || fail "the system step failed: $(cat "$t/out")"
}

# No adapter, only an NVIDIA card's audio function: neither set up
system
grep -q "bluetooth-setup" "$log" && fail "Bluetooth set up with no adapter"
grep -q "No Bluetooth adapter" "$t/out" || fail "no adapter not said: $(cat "$t/out")"
grep -q "nvidia-early" "$log" && fail "NVIDIA early loading with no NVIDIA graphics card"
# An adapter and an NVIDIA graphics card: both
mkdir -p "$SYSFS/class/bluetooth/hci0" "$SYSFS/bus/pci/devices/0000:01:00.0"
echo 0x10de >"$SYSFS/bus/pci/devices/0000:01:00.0/vendor"; echo 0x030000 >"$SYSFS/bus/pci/devices/0000:01:00.0/class"
system
grep -q "bluetooth-setup" "$log" || fail "Bluetooth not set up with an adapter: $(cat "$log")"
grep -q "nvidia-early" "$log" || fail "NVIDIA early loading not offered with an NVIDIA card: $(cat "$log")"
# The card with no NVIDIA driver installed (nouveau): not offered
printf '#!/bin/sh\nexit 1\n' >"$t/bin/modinfo"
system
grep -q "nvidia-early" "$log" && fail "NVIDIA early loading with no NVIDIA driver"

# The camera switch's camera, by vendor and product (not another of the vendor's devices)
(source "$here/setup/modules/90-hardware.sh"; usb_device 04f2 b83e) || fail "the plugged-in camera wasn't found"
(source "$here/setup/modules/90-hardware.sh"; usb_device 04f2 0001) && fail "another device taken for the camera"


# A VMware VM: its screen size passed on (VMware's tools' config changed) only once asked, as every system change is
printf '#!/bin/sh\necho vmware\n' >"$t/bin/systemd-detect-virt"; chmod +x "$t/bin/systemd-detect-virt"
: >"$t/kms.so"
hardware() {
    : >"$log"
    VMTOOLS_CONF=$t/tools.conf VMTOOLS_KMS_PLUGIN=$t/kms.so repo=$here yes=false \
        bash -c 'source "$1/setup/lib.sh"; source "$1/setup/modules/90-hardware.sh"; module_hardware' _ "$here" >"$t/out" 2>&1 ||
        fail "the hardware step failed: $(cat "$t/out")"
}
hardware <<<"n"
grep -q "tools.conf" "$log" && fail "VMware's tools' config changed when the answer was no: $(cat "$log")"
hardware </dev/null  # (no one to answer: no, as for every other change)
grep -q "tools.conf" "$log" && fail "VMware's tools' config changed when the answer was no: $(cat "$log")"
hardware <<<"y"
{ grep -q "sudo tee -a $t/tools.conf" "$log" && grep -q "sudo systemctl restart vmtoolsd" "$log"; } ||
    fail "VMware's screen setting not made when the answer was yes: $(cat "$log")"
# ...VMware's tools not restarting (or the config not writable): said, the step (and setup after it) not stopped
cat >"$t/bin/sudo" <<'S'
#!/bin/sh
echo "sudo $*" >>"$log"
[ "$*" != "systemctl restart vmtoolsd" ]
S
hardware <<<"y"
grep -q "tools not restarted" "$t/out" || fail "VMware's tools failing to restart not said: $(cat "$t/out")"
# AUR packages with no paru or yay: said, and failed
printf '#!/bin/sh\nexit 1\n' >"$t/bin/pacman"; chmod +x "$t/bin/pacman"
out=$(PATH=$t/bin repo=$here yes=true "$BASH" -c 'source "$1/setup/lib.sh"; pkg_install some-aur-pkg' _ "$here" 2>&1) &&
    fail "pkg_install with no AUR helper reported success"
grep -q "No AUR helper (paru/yay) for: some-aur-pkg" <<<"$out" || fail "no AUR helper not said: $out"
echo "ok setup-hardware"
