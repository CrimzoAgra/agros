# shellcheck shell=bash disable=SC2154  # $repo and $yes come from setup.sh
# about: Keyboard layout (asked, the current one by default): text consoles, login screen and Hyprland
# scope: system

module_keyboard() {
    local current layout
    # As Hyprland, the login screen and scroll-lock read it (localectl prints "(unset)" for none)
    current=$(grep -oP '"XkbLayout"\s+"\K[^"]+' /etc/X11/xorg.conf.d/00-keyboard.conf 2>/dev/null | head -1) || true  # none set
    # --yes with no layout set: left alone (not reset to us)
    $yes && [[ -z $current ]] && { echo "Keyboard left as it is."; return 0; }
    if $yes; then
        layout=$current
    # Nothing to read (no terminal, run from a script): left as it is, as ask answers no (set -e would stop setup here)
    elif ! read -rp "Keyboard layout (us, pt, de, fr...) [${current:-us}] " layout; then
        echo; echo "Keyboard left as it is."; return 0
    fi
    layout=${layout:-${current:-us}}
    if [[ $layout == "$current" ]]; then echo "Keyboard stays $layout."; return 0; fi
    # (the text consoles' keymap follows when one matches. One localectl doesn't know, a typo: said, setup goes on)
    sudo localectl set-x11-keymap "$layout" || { echo "!! \"$layout\" isn't a layout: keyboard left as it is."; return 0; }
    echo "Keyboard set to $layout."
}
