# shellcheck shell=bash disable=SC2154  # $repo and $yes come from setup.sh
# about: Caelestia's own installer: the shell and its default configs
# scope: system

module_caelestia() {
    ask "Run the Caelestia installer (shell + its default configs)?" || return 0
    # The shell plus its configs (Hyprland, fish, foot, btop, GTK/Qt themes...). Your files are copied over these
    # afterwards (module files), so they win
    aur_helper >/dev/null || { echo "!! No AUR helper (paru/yay): install the desktop packages first."; return 0; }
    wait_boot_update  # (it installs packages: not while the boot's update fetches them)
    command -v caelestia >/dev/null || "$(aur_helper)" -S --needed --noconfirm caelestia-cli
    # Not its spotify/vscode parts: they'd add native Spotify and Code - OSS next to the Flatpak Spotify and VSCodium
    caelestia install --aur-helper "$(basename "$(aur_helper)")" --disable-components spotify,vscode,firefox --noconfirm ||
        echo "!! The Caelestia installer reported a problem; carrying on."
    # Its session's browser is Firefox, left out above: LibreWolf (the apps step) instead
    if [[ -f $HOME/.config/uwsm/env ]]; then
        sed -i 's/^export BROWSER=firefox$/export BROWSER=librewolf/' "$HOME/.config/uwsm/env"
    fi
}
