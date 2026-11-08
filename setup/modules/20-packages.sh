# shellcheck shell=bash disable=SC2154  # $repo and $yes come from setup.sh
# about: Desktop packages: Hyprland, Caelestia, Quickshell, fonts, tools (pacman, AUR via paru)
# scope: system

PACKAGES=(
    pipewire pipewire-pulse pipewire-jack wireplumber # first: PipeWire as the JACK provider (mpv would pull jack2, which
    # blocks Caelestia's installer; stock CachyOS comes with jack2 instead, swapped in module_packages)
    hyprland uwsm greetd cage plymouth fish git python jq libnotify mpv flatpak nodejs pacman-contrib
    zenity bluez bluez-utils gnome-keyring libsecret python-secretstorage python-gobject python-numpy python-xlib
    foot thunar gnome-text-editor qview qt6-wayland wl-clipboard cliphist grim slurp swappy brightnessctl ddcutil libqalculate
    starship eza zoxide direnv fastfetch btop micro
    adw-gtk-theme papirus-icon-theme noto-fonts noto-fonts-emoji
    ttf-jetbrains-mono-nerd ttf-cascadia-code-nerd ttf-material-symbols-variable
    caelestia-cli caelestia-shell ttf-rubik-vf
)

module_packages() {
    ask "Install the desktop packages (Hyprland, Caelestia, Quickshell, fonts, tools)?" || return 0
    command -v pacman >/dev/null || { echo "This needs an Arch-based system (pacman)."; exit 1; }
    wait_boot_update
    # Up to date first: installing from an old package list fetches versions the mirrors no longer have. A new Qt then
    # needs Quickshell and Caelestia rebuilt for it, as the Updates app does (update-apps: the same check and rebuild)
    "$repo/.local/bin/update-apps" --qt-mark
    sudo pacman -Syu --noconfirm
    install_aur_helper
    "$repo/.local/bin/update-apps" --qt-rebuild || echo "!! Quickshell and Caelestia weren't rebuilt for the new Qt: run Updates"
    install_quickshell
    # Stock CachyOS now comes with jack2 (ffmpeg's JACK), which pipewire-jack conflicts with: --noconfirm alone
    # answers "remove jack2?" no and the whole install fails. --ask=4: yes to that conflict only (one transaction)
    if installed jack2 && ! installed pipewire-jack; then
        sudo pacman -S --noconfirm --ask=4 pipewire-jack
    fi
    # CachyOS's name and logo (/etc/os-release: Caelestia's logo, fastfetch) come from cachyos-hooks rewriting Arch's
    # files; a CachyOS not put in by its installer (made from the running one) lacked it and called itself Arch. The
    # packages owning those files installed again, so the hooks run on them now
    if pacman -Si cachyos-hooks >/dev/null 2>&1 && ! installed cachyos-hooks; then
        { sudo pacman -S --noconfirm cachyos-hooks && sudo pacman -S --noconfirm filesystem $(installed lsb-release && echo lsb-release); } ||
            echo "!! CachyOS's branding didn't go in: the system still calls itself Arch"
    fi
    pkg_install "${PACKAGES[@]}"
    # Qt written down again where it wasn't installed before (a plain Arch: "none"), now that Quickshell and Caelestia
    # were built with it; else the apps step's check took it for a new Qt and rebuilt them, and dotfiles-check said so
    "$repo/.local/bin/update-apps" --qt-mark
    # The stock title bar plugin: what hyprbars-build falls back to (and runs meanwhile at the first login, while it
    # builds the patched one). Not fatal: an AUR build that lags a Hyprland update fails for a day or two
    pkg_install hyprland-plugin-hyprbars ||
        echo "!! The stock title bar plugin didn't build: title bars come once hyprbars-build has built its own (at login)"
}

# paru, also next to yay: the updater (update-apps) uses paru
install_aur_helper() {
    # The build tools first: AUR packages (Quickshell, next) and the title bar plugin (hyprbars-build) need them (stock
    # CachyOS has them; Arch not)
    sudo pacman -S --needed --noconfirm base-devel git
    command -v paru >/dev/null && return 0
    if pacman -Si paru >/dev/null 2>&1; then
        sudo pacman -S --needed --noconfirm paru
    else
        local tmp
        tmp=$(mktemp -d)
        # (failed: its folder taken away all the same)
        { git clone https://aur.archlinux.org/paru-bin.git "$tmp/paru-bin" && (cd "$tmp/paru-bin" && makepkg -si --noconfirm); } ||
            { rm -rf "${tmp:?}"; return 1; }
        rm -rf "${tmp:?}"
    fi
}

# The real Quickshell from the AUR. CachyOS ships noctalia-qs, a fork that claims to be quickshell-git (Provides:
# quickshell quickshell-git), so "-S quickshell-git" keeps or installs that instead, and pacman -Q quickshell-git
# answers with it (installed: the package itself only); it can't run Caelestia (unknown pragmas, built for older Qt).
# Built first, noctalia-qs still there (an interruption in the minutes that takes leaves the shell you had), then
# swapped in by one pacman transaction: noctalia-qs declares Conflicts: quickshell-git, which --noconfirm answers "no"
# to; --ask=4 answers yes to taking it out. Arch's own quickshell package (extra) is taken out the same way
install_quickshell() {
    installed quickshell-git && return 0
    local had=false
    installed noctalia-qs && had=true
    if $had; then
        local tmp pkg
        tmp=$(mktemp -d)
        if git clone -q https://aur.archlinux.org/quickshell-git.git "$tmp/qs" && (cd "$tmp/qs" && makepkg -s --noconfirm --needed) &&
            pkg=$(cd "$tmp/qs" && makepkg --packagelist | grep -v -- '-debug-' | head -1) && [[ -f $pkg ]]; then
            # (that refused all the same: noctalia-qs out, the build in, at once)
            sudo pacman -U --noconfirm --ask=4 "$pkg" ||
                { installed noctalia-qs && sudo pacman -Rdd --noconfirm noctalia-qs && sudo pacman -U --noconfirm "$pkg"; } || true
        fi
        rm -rf "${tmp:?}"
        installed quickshell-git && return 0
    elif "$(aur_helper)" -S --noconfirm --ask=4 aur/quickshell-git; then
        return 0
    fi
    # Failed with no noctalia-qs before: none put in (it isn't the shell you had)
    if ! $had; then
        echo "!! Quickshell didn't build. Run ./setup.sh --only packages again."
        return 1
    fi
    # Failed: noctalia-qs back (if the swap took it out): without any Quickshell, no shell starts at all
    if installed noctalia-qs || sudo pacman -S --noconfirm noctalia-qs; then
        echo "Quickshell didn't build; the shell you had is back. Run ./setup.sh --only packages again."
    else
        echo "!! Quickshell didn't build, and the shell you had (noctalia-qs) couldn't be put back: no desktop shell"
        echo "   will start until one is installed. Run ./setup.sh --only packages again (or: sudo pacman -S noctalia-qs)."
    fi
    return 1
}
