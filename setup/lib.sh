# shellcheck shell=bash disable=SC2154  # $repo and $yes come from setup.sh
# Helpers shared by setup.sh and its modules (setup/modules/*.sh). Sourced, not run.
# Expects: $repo (the dotfiles folder) and $yes (true/false, from --yes).

say() { printf '\n\033[1;35m==> %s\033[0m\n' "$*"; }

# ask <question>: yes unless answered n/N (always yes with --yes). Nothing to read (run with no terminal, from a script):
# no, not yes to removing Noctalia; --yes is the way to run it unattended
ask() {
    $yes && return 0
    local r
    read -rp "$1 [Y/n] " r || { echo; return 1; }
    [[ ! $r =~ ^[Nn] ]]
}

# wait_boot_update: the update started at boot first (a step run right after boot: both fetching the same package at
# once would corrupt it)
wait_boot_update() {
    while systemctl is-active -q auto-update 2>/dev/null; do echo "Waiting for the boot's update to finish..."; sleep 5; done
}

aur_helper() { command -v paru || command -v yay; }

# sudo_keepalive: your password asked for once, now, and sudo kept fresh while setup runs (a run takes about 15 min:
# sudo's own timeout asked again, several times along the way). The refresher, in the background, ends with setup
# (its PID: $$) or when sudo can't be refreshed without asking; setup's exit kills it ($keepalive)
sudo_keepalive() {
    sudo -v || { echo "!! sudo not set up front: it may ask for your password along the way"; return 0; }
    (while kill -0 "$$" 2>/dev/null; do sleep "${SUDO_REFRESH:-60}"; sudo -n -v || exit 0; done) >/dev/null 2>&1 &
    # shellcheck disable=SC2034  # (setup.sh's, which kills it at its exit)
    keepalive=$!
}

# aur_reachable: whether the AUR answers (its package information service)
aur_reachable() { curl -fsS --max-time 15 -o /dev/null 'https://aur.archlinux.org/rpc/v5/info?arg[]=paru-bin'; }

# pkg_install <packages...>: from the official repos where they are, the rest from the AUR. A name in neither is said
# and left out (the helper refused the whole batch for one unknown name: the others weren't installed either)
pkg_install() {
    local repo_p=() aur_p=() found=() missing=() p ok=0 aur
    for p in "$@"; do
        if pacman -Si "$p" >/dev/null 2>&1; then repo_p+=("$p"); else aur_p+=("$p"); fi
    done
    ((${#repo_p[@]} == 0)) || sudo pacman -S --needed --noconfirm "${repo_p[@]}" || ok=1
    # (no helper yet: said so, not a bare "command not found")
    if ((${#aur_p[@]})); then
        aur=$(aur_helper) || { echo "!! No AUR helper (paru/yay) for: ${aur_p[*]}"; return 1; }
        for p in "${aur_p[@]}"; do
            if "$aur" -Si "$p" >/dev/null 2>&1; then found+=("$p"); else missing+=("$p"); fi
        done
        # (the AUR out of reach answers no for every name: said so, not that they don't exist)
        if ((${#missing[@]})); then
            ok=1
            if aur_reachable; then echo "!! Not in the repos nor the AUR: ${missing[*]}"
            else echo "!! Couldn't reach the AUR (offline?): not installed this time: ${missing[*]}"; fi
        fi
        ((${#found[@]} == 0)) || "$aur" -S --needed --noconfirm "${found[@]}" || ok=1
    fi
    return $ok
}

# installed <package>: whether pacman has that package itself. Not one that only provides its name (pacman -Q falls back
# to those: CachyOS's noctalia-qs, "Provides: quickshell-git", passed for Quickshell and it was never built)
installed() { [[ $(pacman -Qq "$1" 2>/dev/null) == "$1" ]]; }
