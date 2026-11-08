# shellcheck shell=bash disable=SC2154  # $repo and $yes come from setup.sh
# about: Your files into your home (over Caelestia's defaults; replaced ones backed up to ~/.dotfiles-backup/<date>/)
# scope: user

module_files() {
    local backup f
    backup="$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)"
    git -C "$repo" rev-parse --git-dir &>/dev/null || { echo "No git history in $repo: clone the repo with git (a ZIP download can't list its files)"; return 1; }
    # Where the repo is, for dotfiles-sync, dotfiles-check and the bookmarks export (it may not be ~/Projects/dotfiles)
    mkdir -p "$HOME/.local/state" && echo "$repo" >"$HOME/.local/state/dotfiles-repo"
    # Tracked files only: not caches or this machine's generated files. The Settings app's list of settings first:
    # Hyprland reloads its config as each file of it lands (a setup run from the desktop), and the config reads its
    # settings by that list, new ones nil until it's there
    while IFS= read -r -d '' f; do
        # Claude Code's own installer put its link there: keep it (the wrapper is for the editor extension's copy)
        [[ $f == .local/bin/claude && -L $HOME/$f ]] && continue
        # A launcher entry for an app that isn't installed (its TryExec): left out, as Caelestia's launcher would show it
        # anyway (it doesn't read TryExec). Install the app and run the files step again for it
        if [[ $f == .local/share/applications/*.desktop ]]; then
            local try fp
            try=$(sed -n 's/^TryExec=//p' "$repo/$f" | head -1)
            [[ -z $try ]] || command -v "$try" >/dev/null || { echo "Skipped (its app isn't installed): $f"; continue; }
            # (a Flatpak's: its X-Flatpak id, the Spotify one)
            fp=$(sed -n 's/^X-Flatpak=//p' "$repo/$f" | head -1)
            [[ -z $fp ]] || flatpak info "$fp" &>/dev/null || { echo "Skipped (its app isn't installed): $f"; continue; }
        fi
        # Caelestia's settings: the weather location is this machine's own (the repo's is empty: found by IP), so yours
        # stays (dotfiles-sync leaves it out of the repo)
        local loc=""
        [[ $f == .config/caelestia/shell.json && -f $HOME/$f ]] &&
            loc=$(jq -r '.services.weatherLocation // empty' "$HOME/$f" 2>/dev/null) || true  # empty or broken: none kept
        if [[ -e $HOME/$f ]] && ! cmp -s "$repo/$f" "$HOME/$f" &&
            ! { [[ -n $loc ]] && jq --indent 4 '.services.weatherLocation = ""' "$HOME/$f" | cmp -s "$repo/$f" -; }; then
            mkdir -p "$backup/$(dirname "$f")"
            cp -a "$HOME/$f" "$backup/$f"
        fi
        mkdir -p "$HOME/$(dirname "$f")"
        # Written beside it, then renamed over it: never half there (Hyprland reloads its config the moment a file of it
        # changes, and an empty one read then left the desktop without its settings); a link there is replaced, not
        # written through
        if [[ -n $loc ]]; then
            jq --indent 4 --arg l "$loc" '.services.weatherLocation = $l' "$repo/$f" >"$HOME/$f.dotfiles-new"
        else
            cp "$repo/$f" "$HOME/$f.dotfiles-new"
        fi
        mv -f "$HOME/$f.dotfiles-new" "$HOME/$f"
    done < <(git -C "$repo" ls-files -z .local/share/dots-settings
        git -C "$repo" ls-files -z .config .local Pictures | grep -zv '^\.local/share/dots-settings/')
    # Files an earlier run installed that the repo has since removed: out of your home too (into the backup), but only
    # while they're still as the repo last had them (one you or an app changed stays). Only what this step itself
    # installed (listed below): the repo once held files other tools own now (Caelestia's hypr, capri-overlay)
    local list="$HOME/.local/state/dotfiles-files" last
    if [[ -f $list ]]; then
        while IFS= read -r -d '' f; do
            [[ -f $HOME/$f ]] || continue
            git -C "$repo" ls-files --error-unmatch -- "$f" &>/dev/null && continue
            last=$(git -C "$repo" log -1 --no-renames --diff-filter=D --format=%H -- "$f")
            [[ -n $last ]] && git -C "$repo" show "$last^:$f" 2>/dev/null | cmp -s - "$HOME/$f" || continue
            mkdir -p "$backup/$(dirname "$f")"
            mv "$HOME/$f" "$backup/$f"
            echo "Removed (no longer in the repo): $f"
        done <"$list"
    fi
    # The wallpaper was a PNG (removed just above): Caelestia, still pointed at it, gets the same picture as a JPEG (its
    # path, and the link the switcher and workspace previews read). Not while the PNG is still there (changed by you)
    local cw="$HOME/.local/state/caelestia/wallpaper"
    if [[ ! -e $HOME/Pictures/Wallpapers/wallpaper-rotated.png ]]; then
        sed -i 's#/Pictures/Wallpapers/wallpaper-rotated\.png$#/Pictures/Wallpapers/wallpaper.jpg#' "$cw/path.txt" 2>/dev/null || true
        [[ $(readlink "$cw/current" 2>/dev/null) != */Pictures/Wallpapers/wallpaper-rotated.png ]] ||
            ln -sfn "$HOME/Pictures/Wallpapers/wallpaper.jpg" "$cw/current"
    fi
    mkdir -p "${list%/*}"
    git -C "$repo" ls-files -z .config .local Pictures >"$list"
    chmod +x "$HOME"/.local/bin/* "$HOME"/.local/share/*/install.sh "$HOME/.local/share/camera-switch/camera-switchd" \
        "$HOME/.local/share/caelestia-greeter/make-theme.sh" 2>/dev/null || true
    # Changed user services take effect at their next restart, not the next login
    systemctl --user daemon-reload 2>/dev/null || true
    # An icon cache some app left in your icons folder hides icons added since (VSCodium's logo): made again
    if [[ -f $HOME/.local/share/icons/hicolor/icon-theme.cache ]]; then
        gtk-update-icon-cache -f -t -q "$HOME/.local/share/icons/hicolor" || true
    fi
    [[ -d $backup ]] && echo "Replaced files backed up to $backup"
    echo "Files copied."
}
