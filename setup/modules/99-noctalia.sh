# shellcheck shell=bash disable=SC2154  # $repo and $yes come from setup.sh
# about: Last: remove Noctalia (CachyOS's default shell and login screen) and its leftover apps, once Caelestia's login screen is in
# scope: system

module_noctalia() {
    # (any one of them: pacman fails when some aren't installed)
    [[ -n $(pacman -Qq noctalia noctalia-greeter cachyos-hypr-noctalia 2>/dev/null) ]] || return 0
    ask "Remove Noctalia (CachyOS's default shell and login screen) and its leftover apps (Dolphin, kitty, Alacritty, nwg-look, kde-cli-tools, swash, xorg-xhost)?" || return 0
    remove_noctalia
}

remove_noctalia() {
    local pkgs=() keep=() leftovers=() p
    for p in cachyos-hypr-noctalia noctalia noctalia-greeter; do installed "$p" && pkgs+=("$p"); done
    ((${#pkgs[@]})) || { echo "Noctalia isn't installed."; return 0; }
    if sudo grep -qs noctalia /etc/greetd/config.toml; then
        echo "The login screen still uses Noctalia (the Caelestia one wasn't installed), so Noctalia stays."
        return 0
    fi
    # CachyOS's own Hyprland config starts Noctalia: still there when Caelestia's installer didn't replace it. By its main
    # file (CachyOS's loads its config/ folder, Caelestia's doesn't): Caelestia's installer leaves CachyOS's other files
    # there, config/autostart.lua naming Noctalia, unused
    if grep -qs 'require("config\.' "$HOME/.config/hypr/hyprland.lua"; then
        echo "Your Hyprland config still starts Noctalia (Caelestia's install didn't finish), so Noctalia stays."
        return 0
    fi
    # Keep the NVIDIA settings the Noctalia package had for Hyprland
    [[ -f /etc/profile.d/Hyprland.sh ]] && sudo cp /etc/profile.d/Hyprland.sh /etc/profile.d/hyprland-nvidia.sh
    sudo pacman -Rn --noconfirm "${pkgs[@]}"
    # Its settings into the backup folder, like every other file setup replaces
    if [[ -d $HOME/.config/noctalia ]]; then
        local backup
        backup="$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)/.config"
        mkdir -p "$backup" && mv "$HOME/.config/noctalia" "$backup/"
    fi
    # Its session settings point at kitty (removed below) and qt6ct (Caelestia sets its own Qt theme)
    sed -i '/^export TERM=xterm-kitty$/d; /^export QT_QPA_PLATFORMTHEME="qt6ct"$/d' "$HOME/.config/uwsm/env" 2>/dev/null || true
    # Its leftovers: keep what the desktop still uses (marked so cleanups don't take them), remove Dolphin (Thunar is the
    # file manager), kitty and Alacritty (foot) and Noctalia's tools
    for p in uwsm qt6-wayland gnome-keyring gnome-text-editor qview gnome-calculator adw-gtk-theme; do
        installed "$p" && keep+=("$p")
    done
    ((${#keep[@]} == 0)) || sudo pacman -D --asexplicit "${keep[@]}" >/dev/null
    for p in dolphin kde-cli-tools kitty alacritty cachyos-alacritty-config nwg-look swash xorg-xhost; do
        installed "$p" && leftovers+=("$p")
    done
    # One by one: one that something else needs (a KDE app needing kde-cli-tools) stays, the rest still go
    for p in "${leftovers[@]}"; do
        sudo pacman -Rns --noconfirm "$p" >/dev/null 2>&1 || echo "Kept $p (something else needs it)."
    done
    echo "Noctalia removed."
}
