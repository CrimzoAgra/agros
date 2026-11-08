# shellcheck shell=bash disable=SC2154  # $repo, $yes and $capri come from setup.sh
# about: Capri, the Edgerunners 2 desktop companion (my fork of CapriDesktop merged with its releases, updated from the Updates app)
# scope: system

module_capri() {
    $capri || { echo "Left out (--no-capri)."; return 0; }
    ask "Install Capri (Edgerunners 2 desktop companion; her chat can run on your Claude Code)?" || return 0
    # The boot's update runs capri-update too (two at once in her folder), and npm's install is a package
    wait_boot_update
    command -v npm >/dev/null || pkg_install nodejs npm
    # Her fork is private: a fresh install has no GitHub login, so it's asked for here (with a terminal) rather than
    # capri-update failing on it
    command -v gh >/dev/null || pkg_install github-cli
    if ! gh auth status >/dev/null 2>&1 && [[ -t 0 ]]; then
        gh auth login --git-protocol https --web && gh auth setup-git || true
    fi
    # Asked for here, so tried again: capri-update remembers a release that didn't merge, build or pass her check and
    # doesn't try it on its own again (a failed download it does retry)
    rm -f "${XDG_STATE_HOME:-$HOME/.local/state}/capri-update-failed" "${XDG_STATE_HOME:-$HOME/.local/state}/capri-update-failed-retries"
    # From the repo (the files step may not have copied it yet); it installs her, or updates her when she's in. (Failing
    # also when she's in, on an older release than the newest, which doesn't fit my changes: said above)
    "$repo/.local/bin/capri-update" || echo "!! Capri isn't on her newest version (see above); ./setup.sh --only capri tries again."
}
