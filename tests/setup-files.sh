#!/usr/bin/env bash
# setup/modules/50-files.sh in a throwaway repo and home: backups, links, ZIP downloads
set -euo pipefail
. "$(dirname "$0")/lib.sh"

repo=$t/repo HOME=$t/home
mkdir -p "$repo/.local/bin" "$repo/.config/app" "$HOME/.config/app" "$HOME/.local/bin" "$t/native"
echo wrapper >"$repo/.local/bin/claude"; echo new >"$repo/.config/app/conf"; echo same >"$repo/.config/app/same"
git -C "$repo" init -q && git -C "$repo" add -A
c() { git -C "$repo" -c user.name=t -c user.email=t@t commit -qm "$1"; }
# Dropped from the repo before this step kept its list (another tool owns it now): never touched
echo theirs >"$repo/.config/app/old"; git -C "$repo" add -A; c old; git -C "$repo" rm -q .config/app/old; c drop-old
echo theirs >"$HOME/.config/app/old"
echo gone >"$repo/.config/app/gone"; echo kept >"$repo/.config/app/kept"; git -C "$repo" add -A
echo old >"$HOME/.config/app/conf"; echo same >"$HOME/.config/app/same"
echo real-binary >"$t/native/claude"; ln -s "$t/native/claude" "$HOME/.local/bin/claude"   # Claude Code's native install
echo target >"$t/native/linked"; echo linked >"$repo/.config/app/linked"; git -C "$repo" add -A
ln -s "$t/native/linked" "$HOME/.config/app/linked"                                         # someone's own link
mkdir -p "$repo/.local/share/applications"                                                   # entries by TryExec
printf '[Desktop Entry]\nExec=x\nTryExec=/nonexistent/app\n' >"$repo/.local/share/applications/missing.desktop"
printf '[Desktop Entry]\nExec=x\nTryExec=sh\n' >"$repo/.local/share/applications/there.desktop"
git -C "$repo" add -A

# Caelestia pointed at the old PNG wallpaper: moved to the JPEG
mkdir -p "$HOME/.local/state/caelestia/wallpaper"
echo "$HOME/Pictures/Wallpapers/wallpaper-rotated.png" >"$HOME/.local/state/caelestia/wallpaper/path.txt"
ln -s "$HOME/Pictures/Wallpapers/wallpaper-rotated.png" "$HOME/.local/state/caelestia/wallpaper/current"

source "$here/setup/modules/50-files.sh"
systemctl() { :; }  # not your own systemd (a daemon-reload restarts timers' counts)
module_files >/dev/null

[[ $(cat "$HOME/.config/app/conf") == new ]] || fail "file not copied"
[[ $(cat "$HOME/.local/state/dotfiles-repo") == "$repo" ]] || fail "where the repo is wasn't recorded"
[[ $(cat "$HOME/.local/state/caelestia/wallpaper/path.txt") == "$HOME/Pictures/Wallpapers/wallpaper.jpg" ]] || fail "Caelestia left on the removed PNG wallpaper"
[[ $(readlink "$HOME/.local/state/caelestia/wallpaper/current") == "$HOME/Pictures/Wallpapers/wallpaper.jpg" ]] || fail "Caelestia's wallpaper link left on the removed PNG"
[[ ! -e $HOME/.local/share/applications/missing.desktop ]] || fail "an entry for an app not installed was copied"
[[ -e $HOME/.local/share/applications/there.desktop ]] || fail "an entry for an installed app was left out"
backup=$(echo "$HOME"/.dotfiles-backup/*)
[[ $(cat "$backup/.config/app/conf") == old ]] || fail "changed file not backed up"
[[ ! -e $backup/.config/app/same ]] || fail "identical file backed up"
[[ $(cat "$t/native/claude") == real-binary && -L $HOME/.local/bin/claude ]] || fail "Claude Code's own install overwritten"
[[ $(cat "$t/native/linked") == target ]] || fail "copy wrote through a link"
[[ ! -L $HOME/.config/app/linked && $(cat "$HOME/.config/app/linked") == linked ]] || fail "link not replaced"

# Removed from the repo since that run: out of home into the backup, unless changed at home
c files; git -C "$repo" rm -q .config/app/gone .config/app/kept; c removed
echo changed-at-home >"$HOME/.config/app/kept"
rm -rf "$HOME"/.dotfiles-backup; sleep 1
module_files >/dev/null
[[ ! -e $HOME/.config/app/gone ]] || fail "a file the repo removed stayed"
[[ $(cat "$HOME"/.dotfiles-backup/*/.config/app/gone) == gone ]] || fail "the removed file wasn't backed up"
[[ $(cat "$HOME/.config/app/kept") == changed-at-home ]] || fail "a removed file you changed was taken away"
[[ $(cat "$HOME/.config/app/old") == theirs ]] || fail "a file dropped before the list was kept was taken away"

# Caelestia's settings: the weather location at home is this machine's (the repo's is empty): kept, and the file not
# backed up when that's the only difference
mkdir -p "$repo/.config/caelestia" "$HOME/.config/caelestia"
echo '{"services": {"weatherLocation": ""}}' | jq --indent 4 . >"$repo/.config/caelestia/shell.json"; git -C "$repo" add -A; c shell-loc
jq --indent 4 '.services.weatherLocation = "Porto"' "$repo/.config/caelestia/shell.json" >"$HOME/.config/caelestia/shell.json"
rm -rf "$HOME"/.dotfiles-backup; sleep 1
module_files >/dev/null
[[ $(jq -r .services.weatherLocation "$HOME/.config/caelestia/shell.json") == Porto ]] || fail "the weather location wasn't kept"
[[ -z $(find "$HOME"/.dotfiles-backup -name shell.json 2>/dev/null) ]] || fail "shell.json backed up over its location alone"

# Caelestia's settings left half-written at home (a crash mid-save): copied, not the step stopped there (setup runs it set -e)
mkdir -p "$repo/.config/caelestia" "$HOME/.config/caelestia"
echo '{"services": {"weatherLocation": ""}}' >"$repo/.config/caelestia/shell.json"; git -C "$repo" add -A; c shell
echo '{"services": {"weatherLoc' >"$HOME/.config/caelestia/shell.json"
# (in a shell of its own with set -e on, as setup.sh runs it: "|| fail" here would turn set -e off inside)
repo=$repo HOME=$HOME bash -euo pipefail -c 'source "$1"; systemctl() { :; }; module_files' _ "$here/setup/modules/50-files.sh" \
    >/dev/null 2>&1 || fail "a broken shell.json at home stopped the files step"
jq -e . "$HOME/.config/caelestia/shell.json" >/dev/null || fail "the broken shell.json wasn't replaced"

# The Settings app's list of settings in place before the config that reads it (Hyprland reloads as each lands)
mkdir -p "$repo/.config/caelestia/user" "$repo/.local/share/dots-settings"
echo v2 >"$repo/.config/caelestia/hypr-user.lua"; echo v2 >"$repo/.config/caelestia/user/keys.lua"
echo '{}' >"$repo/.local/share/dots-settings/schema.json"; git -C "$repo" add -A
module_files >/dev/null 2>&1 || fail "the files step failed"
for f in hypr-user.lua user/keys.lua; do
    [[ $HOME/.local/share/dots-settings/schema.json -ot $HOME/.config/caelestia/$f ]] ||
        fail "the settings' list copied after the config that reads it ($f)"
done
rm -rf "$repo/.git"                                                                          # a ZIP download
if module_files >/dev/null 2>&1; then fail "ZIP download not refused"; fi
echo "ok setup-files"
