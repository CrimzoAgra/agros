# shellcheck shell=bash disable=SC2154  # $repo and $yes come from setup.sh
# about: Only on matching hardware: the Legion's camera switch, Legion Control (separate repo), a VMware VM's screen size
# scope: system

module_hardware() {
    # The camera switch is for the Legion's webcam (04f2:b83e) and its "Ideapad extra buttons"
    if grep -qs 'Name="Ideapad extra buttons"' /proc/bus/input/devices && usb_device 04f2 b83e &&
        ask "Make the physical camera switch work?"; then
        sudo bash "$repo/.local/share/camera-switch/install.sh"
    fi
    # Lenovo Legion: settings, lighting and firmware updates app
    if grep -qi legion /sys/class/dmi/id/product_version 2>/dev/null && ask "This is a Legion: install Legion Control?"; then
        local src=${LEGION_CONTROL_DIR:-$HOME/Projects/legion-control-linux}
        [[ -d $src ]] || git clone https://github.com/CrimzoAgra/legion-control-linux "$src" ||
            { echo "Couldn't download Legion Control (offline?): run ./setup.sh --only hardware later."; return 0; }
        # (a failure said, not the end of setup: set -e would stop it here, before the steps after this one)
        { bash "$src/install-user.sh" && sudo bash "$HOME/.local/share/legion-control/install.sh"; } ||
            echo "!! Legion Control didn't install: run ./setup.sh --only hardware again"
    fi
    # A VMware VM: its screen follows the window (and full screen). VMware's tools only pass the size on to a Wayland
    # desktop with resolutionKMS on (off by default); vm-screen-follow then has Hyprland take it. Asked, as every
    # change to the system is (the paths named by the tests only)
    local conf=${VMTOOLS_CONF:-/etc/vmware-tools/tools.conf}
    if [[ $(systemd-detect-virt 2>/dev/null) == vmware &&
        -e ${VMTOOLS_KMS_PLUGIN:-/usr/lib/open-vm-tools/plugins/vmsvc/libresolutionKMS.so} ]] &&
        ! grep -qs '^\[resolutionKMS\]' "$conf" &&
        ask "A VMware VM: have its screen follow the window's size (resolutionKMS on in $conf, VMware's tools restarted)?"; then
        printf '
[resolutionKMS]
enable=true
' | sudo tee -a "$conf" >/dev/null && sudo systemctl restart vmtoolsd &&
            echo "VMware: the screen follows the window from the next login." ||
            echo "!! VMware's tools' setting not made, or the tools not restarted: run ./setup.sh --only hardware again"
    fi
}

# usb_device <vendor> <product>: whether one is plugged in (from sysfs: lsusb's usbutils may not be installed)
usb_device() {
    local d
    for d in "${SYSFS:-/sys}"/bus/usb/devices/*; do
        [[ $(cat "$d/idVendor" 2>/dev/null):$(cat "$d/idProduct" 2>/dev/null) == "$1:$2" ]] && return 0
    done
    return 1
}
