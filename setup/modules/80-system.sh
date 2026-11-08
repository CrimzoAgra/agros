# shellcheck shell=bash disable=SC2154  # $repo and $yes come from setup.sh
# about: System parts (sudo): pacman hook, ananicy rule, Bluetooth, boot-time updates, boot menu, video mode, NVIDIA early, login screen, keyring
# scope: system

module_system() {
    echo "(asks for your password)"
    # Its scripts install packages (os-prober, v4l-utils, cage...): not while the boot's update fetches them
    wait_boot_update
    pacman_hook
    # The shell at normal CPU priority (CachyOS's process rules lower it): system/ananicy/dotfiles.rules
    if [[ -d /etc/ananicy.d ]]; then
        sudo install -Dm644 "$repo/system/ananicy/dotfiles.rules" /etc/ananicy.d/99-dotfiles/dotfiles.rules
        systemctl is-active -q ananicy-cpp && sudo systemctl restart ananicy-cpp
    fi
    # Only with an adapter (a desktop may have none: plug a dongle in, then ./setup.sh --only system)
    if ! compgen -G "${SYSFS:-/sys}/class/bluetooth/hci*" >/dev/null; then
        echo "No Bluetooth adapter: its setup skipped."
    elif ask "Bluetooth on at boot and after sleep?"; then
        sudo bash "$repo/system/bluetooth-setup.sh"
    fi
    if ask "Update the system (drivers, gaming packages, apps) automatically at every boot?"; then
        sudo bash "$repo/system/auto-update-setup.sh"
    fi
    if ask "Hide the boot menu (GRUB or Limine; Esc shows it; Windows and snapshots listed)?"; then
        sudo bash "$repo/system/boot-menu.sh"
    fi
    if ask "Screens in their best mode from boot on (no \"no video\" between the login screen and the desktop)?"; then
        sudo bash "$repo/system/boot-video-mode.sh"
    fi
    if nvidia_gpu && nvidia_driver && ask "Load the NVIDIA driver early in the boot (about 2 s sooner, the boot splash on it)?"; then
        sudo bash "$repo/system/nvidia-early.sh"
    fi
    local splash=/usr/share/plymouth/themes/cachyos-bootanimation
    if ask "Caelestia-style login screen (greetd)$([[ -d $splash ]] && echo " and faster boot splash")?"; then
        login_screen
    fi
    # After the login screen: it needs greetd's login settings
    if [[ -f /etc/pam.d/greetd ]] && ask "Unlock the passwords keyring at login (no keyring password prompts)?"; then
        sudo bash "$repo/system/keyring-setup.sh"
        # Use the keyring started at login, not a second one started on demand
        systemctl --user mask gnome-keyring-daemon.service gnome-keyring-daemon.socket 2>/dev/null || true
    fi
}

# nvidia_gpu: whether an NVIDIA graphics card is in (PCI vendor 10de, display class 03): the driver alone may be left
# from another machine (a disk moved over)
nvidia_gpu() {
    local d
    for d in "${SYSFS:-/sys}"/bus/pci/devices/*; do
        [[ $(cat "$d/vendor" 2>/dev/null) == 0x10de && $(cat "$d/class" 2>/dev/null) == 0x03* ]] && return 0
    done
    return 1
}

# nvidia_driver: whether an NVIDIA driver is installed for any kernel: a kernel updated in this run (the packages step)
# took the running one's modules away, where a bare modinfo looks
nvidia_driver() {
    local k
    for k in "${MODULES_DIR:-/usr/lib/modules}"/*/; do
        k=${k%/}
        modinfo -k "${k##*/}" nvidia >/dev/null 2>&1 && return 0
    done
    return 1
}

# The pacman hooks (system/pacman-hooks/*.hook.in, your user and home filled in by system/render.sh, as dotfiles-check
# renders them to compare): the Caelestia overlay rebuilt after every caelestia-shell update, my hyprbars built for
# each new Hyprland as it's installed (ready at the next login), and the Hyprland config checked against it (its errors
# said by dotfiles-check)
pacman_hook() {
    [[ -x $HOME/.local/bin/caelestia-overlay ]] || { echo "Caelestia's pacman hook skipped: run the files step first."; return 0; }
    # shellcheck source=/dev/null  # (system/render.sh)
    source "$repo/system/render.sh"
    local in
    sudo install -d /etc/pacman.d/hooks
    for in in "$repo"/system/pacman-hooks/*.hook.in; do
        render_hook "$in" "$USER" "$HOME" | sudo tee "/etc/pacman.d/hooks/$(basename "$in" .in)" >/dev/null
    done
    echo "Caelestia updates will keep your changes to it (the overlay is rebuilt after each one)."
}

# The faster CachyOS splash (only where that theme exists; it installs the login screen too), else just the login screen
login_screen() {
    if [[ -d /usr/share/plymouth/themes/cachyos-bootanimation ]]; then
        sudo bash "$repo/.local/share/boot-tweaks/install.sh"
    else
        sudo bash "$repo/.local/share/caelestia-greeter/install.sh"
    fi
    # greetd as the login manager (replaces sddm/gdm/etc.)
    if [[ $(readlink /etc/systemd/system/display-manager.service 2>/dev/null) != */greetd.service ]]; then
        sudo systemctl enable -f greetd.service
    fi
}
