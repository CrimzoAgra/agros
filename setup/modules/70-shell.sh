# shellcheck shell=bash disable=SC2154  # $repo and $yes come from setup.sh
# about: fish as your login shell
# scope: system

module_shell() {
    command -v fish >/dev/null || return 0
    [[ $(getent passwd "$USER" | cut -d: -f7) == */fish ]] && return 0
    ask "Make fish your shell?" || return 0
    # Through sudo like the other system steps: chsh alone asks for the password again (and fails with no terminal)
    sudo chsh -s "$(command -v fish)" "$USER"
}
