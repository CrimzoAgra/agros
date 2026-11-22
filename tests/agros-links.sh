#!/usr/bin/env bash
# agros-links: a config file, launcher entry, LibreWolf setting or wallpaper new in /etc/skel reaches an existing home once (inside a folder the user already has too),
# never over the user's own, and one the user deleted doesn't come back. One an update changed replaces the user's while
# it's a version AgrOS shipped (never edited), else is put beside it as .agros-new and said once (again if that
# notification failed); the user's own
# settings (not in skel-versions) are never touched
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
s=$t/skel/.config h=$t/home/.config
mkdir -p "$t/lib/bin" "$t/lib/share" "$s/fetch" "$s/foot" "$s/librewolf/librewolf" "$h/foot" "$h/librewolf/librewolf/x.default"
echo agros >"$s/fetch/config"; echo agros >"$s/foot/foot.ini"; echo agros >"$s/librewolf/librewolf/librewolf.overrides.cfg"
echo mine >"$h/foot/foot.ini"
# (| cat: waits for its notification in the background too, which writes to the same output. Run from $t/lib/bin: its
# dots-warn is the one beside it)
cp "$here/.local/bin/agros-links" "$t/lib/bin/"
run() {
    HOME=$t/home XDG_STATE_HOME=$t/home/.local/state XDG_CACHE_HOME=$t/home/.cache AGROS_PACMAN_DB=$t/pacman \
        AGROS_LIB=$t/lib AGROS_SKEL=$t/skel AGROS_SKEL_VERSIONS=$t/versions "$t/lib/bin/agros-links" | cat
}

run
[[ $(cat "$h/fetch/config") == agros ]] || fail "a new config not copied in"
[[ $(cat "$h/librewolf/librewolf/librewolf.overrides.cfg") == agros ]] || fail "a new file in a folder the user has not copied in"
[[ $(cat "$h/foot/foot.ini") == mine ]] || fail "the user's own config overwritten"

# A launcher entry new in skel reaches the home too, once; Lutris's covers in skel's .local/share don't (lutris-library's)
mkdir -p "$t/skel/.local/share/applications" "$t/skel/.local/share/lutris/coverart"
echo agros >"$t/skel/.local/share/applications/new.desktop"; echo cover >"$t/skel/.local/share/lutris/coverart/x.jpg"
run
[[ $(cat "$t/home/.local/share/applications/new.desktop") == agros ]] || fail "a new launcher entry not copied in"
[[ ! -e $t/home/.local/share/lutris ]] || fail "Lutris's covers copied in by agros-links"
rm "$t/home/.local/share/applications/new.desktop"

# An account not made from /etc/skel: LibreWolf's settings (agros-welcome applies them, or counts the step done with
# nothing applied) and Caelestia's wallpaper (a link) come in too; yours left as they are
mkdir -p "$t/skel/.local/share/firefox" "$t/skel/Pictures/Wallpapers" "$t/home/Pictures/Wallpapers"
echo agros >"$t/skel/.local/share/firefox/settings.js"; ln -s /etc/xdg/wallpaper.webp "$t/skel/Pictures/Wallpapers/caelestia.webp"
echo agros >"$t/skel/Pictures/Wallpapers/mine.jpg"; echo mine >"$t/home/Pictures/Wallpapers/mine.jpg"
run
[[ $(cat "$t/home/.local/share/firefox/settings.js") == agros ]] || fail "LibreWolf's settings not copied in"
[[ $(readlink "$t/home/Pictures/Wallpapers/caelestia.webp") == /etc/xdg/wallpaper.webp ]] || fail "Caelestia's wallpaper not linked in"
[[ $(cat "$t/home/Pictures/Wallpapers/mine.jpg") == mine ]] || fail "a wallpaper of yours replaced"
rm "$t/home/.local/share/firefox/settings.js"; run
[[ ! -e $t/home/.local/share/firefox/settings.js ]] || fail "LibreWolf's settings, deleted, came back"

rm -rf "$h/fetch"; run
[[ ! -e $h/fetch ]] || fail "a config the user deleted came back"
[[ ! -e $t/home/.local/share/applications/new.desktop ]] || fail "a launcher entry the user deleted came back"

# A copy that failed (its folder couldn't be made: a file in its place, as a full disk fails it) isn't marked as
# offered: it comes at the next login, once it can
mkdir -p "$s/blocked"; echo agros >"$s/blocked/x.conf"; echo file >"$h/blocked"
run 2>/dev/null
rm "$h/blocked"; run
[[ $(cat "$h/blocked/x.conf" 2>/dev/null) == agros ]] || fail "a config whose copy failed never offered again"
[[ ! -L $t/home/.local/share/'*' ]] || fail "an empty share folder linked as a folder named '*'"

# Updates: "old" and "agros" shipped before; the user edited mine.lua; shell.json is the user's (left out of the list)
mkdir -p "$s/caelestia" "$h/caelestia" "$t/skel/.local/share/applications" "$t/home/.local/share/applications"
printf '#!/bin/sh\necho "warned: $*" >>%q\n' "$t/warned" >"$t/lib/bin/dots-warn" && chmod +x "$t/lib/bin/dots-warn"
for f in caelestia/old.lua caelestia/mine.lua caelestia/shell.json; do echo new >"$s/$f"; done
echo new >"$t/skel/.local/share/applications/x.desktop"
echo old >"$h/caelestia/old.lua"; chmod 600 "$h/caelestia/old.lua"; echo old >"$t/home/.local/share/applications/x.desktop"
# (one an earlier run had wrongly offered: gone with the update)
echo stale >"$h/caelestia/old.lua.agros-new"
echo edited >"$h/caelestia/mine.lua"; echo edited >"$h/caelestia/shell.json"
sha() { sha256sum <"$1" | cut -d' ' -f1; }
for v in old agros new; do
    for f in .config/caelestia/old.lua .config/caelestia/mine.lua .local/share/applications/x.desktop; do
        echo "$(echo $v | sha256sum | cut -d' ' -f1)  $f"
    done
done >"$t/versions"
run
[[ $(cat "$h/caelestia/old.lua") == new ]] || fail "a never-edited setting not updated"
[[ $(stat -c %a "$h/caelestia/old.lua") == 600 ]] || fail "an updated setting's mode not kept"
[[ $(cat "$t/home/.local/share/applications/x.desktop") == new ]] || fail "a never-edited launcher entry not updated"
[[ $(cat "$h/caelestia/mine.lua") == edited ]] || fail "an edited setting overwritten"
[[ $(cat "$h/caelestia/mine.lua.agros-new") == new ]] || fail "an edited setting's new version not put beside it"
[[ $(cat "$h/caelestia/shell.json") == edited && ! -e $h/caelestia/shell.json.agros-new ]] || fail "the user's own setting touched"
[[ ! -e $h/caelestia/old.lua.agros-new && ! -e $h/caelestia/old.lua.agros-tmp ]] || fail "an update left a file beside it"
[[ $(grep -c . "$t/warned") == 1 && $(grep -c mine.lua "$t/warned") == 1 ]] || fail "not one notification of the edited setting"

a=$(find "$t/home" -type f -printf '%p %s %T@\n' | sort)
rm "$h/caelestia/mine.lua.agros-new"; run
[[ ! -e $h/caelestia/mine.lua.agros-new && $(grep -c . "$t/warned") == 1 ]] || fail "an edited setting said again"
[[ $(find "$t/home" -type f -printf '%p %s %T@\n' | sort) == "$(grep -v agros-new <<<"$a")" ]] || fail "a second run changed something"

# A notification that never got through (Caelestia never came up): said again at the next login
echo newest >"$s/caelestia/mine.lua"
printf '#!/bin/sh\nexit 1\n' >"$t/lib/bin/dots-warn"; run
printf '#!/bin/sh\necho "warned: $*" >>%q\n' "$t/warned" >"$t/lib/bin/dots-warn"; run
[[ $(grep -c . "$t/warned") == 2 ]] || fail "a notification that failed marked as said"
echo newer >"$s/caelestia/mine.lua"; run
[[ $(cat "$h/caelestia/mine.lua.agros-new") == newer && $(grep -c . "$t/warned") == 3 ]] || fail "a newer version not offered"

# One version offered once: run again, not said a second time
run
[[ $(grep -c . "$t/warned") == 3 ]] || fail "the same new version said twice"
# A newer version still: offered again
echo newest-still >"$s/caelestia/mine.lua"; run
[[ $(cat "$h/caelestia/mine.lua.agros-new") == newest-still && $(grep -c . "$t/warned") == 4 ]] ||
    fail "a newer version not offered again"
# A home with AgrOS's own repo (its settings made there, dotfiles-sync's): a file of yours that is a version committed
# there (copied in ahead of the package) left as it is and not said; one that isn't, offered as before
d=$t/home/Projects/agros
mkdir -p "$d/packages/agros-hyprland-settings" "$d/.config/caelestia" && : >"$d/packages/agros-hyprland-settings/PKGBUILD"
echo ahead >"$d/.config/caelestia/mine.lua"
git -C "$d" init -q && git -C "$d" add -A && git -C "$d" -c user.name=t -c user.email=t@t commit -qm ahead
echo ahead >"$h/caelestia/mine.lua"; rm -f "$h/caelestia/mine.lua.agros-new"
echo from-the-package >"$s/caelestia/mine.lua"; was=$(grep -c . "$t/warned"); run
[[ $(cat "$h/caelestia/mine.lua") == ahead && ! -e $h/caelestia/mine.lua.agros-new && $(grep -c . "$t/warned") == "$was" ]] ||
    fail "a file that is AgrOS's own repo's version offered or said as one you changed"
echo mine-really >"$h/caelestia/mine.lua"; run
[[ $(cat "$h/caelestia/mine.lua.agros-new") == from-the-package && $(grep -c . "$t/warned") == $((was + 1)) ]] ||
    fail "an edit of yours not in AgrOS's repo no longer offered"
rm -rf "$d"
# The bar's status icons (the sound one): an install from before AgrOS listed them gets /etc/skel's list in its own
# shell.json, once, its other settings kept; a list of its own left alone; no shell.json left with none (json-edit, beside
# it, starts a missing one as {})
cp "$here/.local/bin/json-edit" "$t/lib/bin/"
echo '{"bar": {"statusIcons": [{"enabled": true, "id": "audio"}], "x": 1}}' >"$s/caelestia/shell.json"
mark=$t/home/.local/state/agros/bar-status-icons
echo '{"bar": {"statusIcons": []}}' >"$h/caelestia/shell.json"; run
[[ $(jq -c .bar.statusIcons "$h/caelestia/shell.json") == '[]' ]] || fail "a list of the user's own replaced: $(cat "$h/caelestia/shell.json")"
rm -f "$mark"; echo '{"bar": {"y": 2}, "z": 3}' >"$h/caelestia/shell.json"; run
[[ $(jq -c '[.bar.statusIcons, .bar.y, .z]' "$h/caelestia/shell.json") == '[[{"enabled":true,"id":"audio"}],2,3]' ]] ||
    fail "AgrOS's status icons not added to a shell.json without them, or its settings lost: $(cat "$h/caelestia/shell.json")"
# ...once: taken out by the user, it stays out
echo '{"bar": {"y": 2}}' >"$h/caelestia/shell.json"; run
[[ $(jq -c . "$h/caelestia/shell.json") == '{"bar":{"y":2}}' ]] || fail "the status icons added again after the user took them out"
rm -f "$mark" "$h/caelestia/shell.json"; run
[[ ! -e $h/caelestia/shell.json ]] || fail "a missing shell.json made, for the status icons: $(cat "$h/caelestia/shell.json")"
# The lock screen's notifications hidden (lock.hideNotifs): a shell.json from before gets it once, its other settings
# kept; one of the user's own kept; turned off later, it stays off
mark=$t/home/.local/state/agros/lock-hide-notifs
rm -f "$mark"; echo '{"lock": {"useWallpaper": true}, "z": 3}' >"$h/caelestia/shell.json"; run
[[ $(jq -c '[.lock.hideNotifs, .lock.useWallpaper, .z]' "$h/caelestia/shell.json") == '[true,true,3]' ]] ||
    fail "lock.hideNotifs not added to a shell.json without it, or its settings lost: $(cat "$h/caelestia/shell.json")"
echo '{"lock": {}}' >"$h/caelestia/shell.json"; run
[[ $(jq -c . "$h/caelestia/shell.json") == '{"lock":{}}' ]] || fail "lock.hideNotifs added again after the user took it out"
rm -f "$mark"; echo '{"lock": {"hideNotifs": false}}' >"$h/caelestia/shell.json"; run
[[ $(jq -c .lock.hideNotifs "$h/caelestia/shell.json") == false ]] || fail "the user's own lock.hideNotifs replaced"
rm -f "$mark" "$h/caelestia/shell.json"; run
[[ ! -e $h/caelestia/shell.json ]] || fail "a missing shell.json made, for lock.hideNotifs: $(cat "$h/caelestia/shell.json")"
# VSCodium's settings.json from before window.restoreWindows: gets it once, its other settings kept; a value of the
# user's own kept; one with comments (jq can't read it) left byte for byte; none made where there's none
code=$h/VSCodium/User/settings.json mark=$t/home/.local/state/agros/vscodium-restore-windows
mkdir -p "${code%/*}"; run
[[ ! -e $code && ! -e $mark ]] || fail "a missing VSCodium settings.json made"
printf '{\n    // mine\n    "a": 1\n}\n' >"$code"; cp "$code" "$t/commented"; run
cmp -s "$code" "$t/commented" && [[ ! -e $mark ]] || fail "a VSCodium settings.json with comments changed or marked done"
echo '{"window.restoreWindows": "all"}' >"$code"; run
[[ $(jq -r '."window.restoreWindows"' "$code") == all ]] || fail "the user's own window.restoreWindows replaced"
rm -f "$mark"; echo '{"a": 1}' >"$code"; run
[[ $(jq -c '."window.restoreWindows"' "$code") == '"folders"' && $(jq -c .a "$code") == 1 ]] ||
    fail "window.restoreWindows not added to VSCodium's settings, or its settings lost: $(cat "$code")"
# ...once: taken out by the user, it stays out
echo '{"a": 1}' >"$code"; run
[[ $(jq -c . "$code") == '{"a":1}' ]] || fail "window.restoreWindows added again after the user took it out"
# window.dialogStyle the same way (GTK's dialogs as wide as a long link): added once, the user's own value kept
code_mark=$t/home/.local/state/agros/vscodium-dialog-style
[[ -e $code_mark ]] || fail "window.dialogStyle not marked done"
rm -f "$code_mark"; echo '{"a": 1}' >"$code"; run
[[ $(jq -c . "$code") == '{"a":1,"window.dialogStyle":"custom"}' ]] ||
    fail "window.dialogStyle not added to VSCodium's settings, or its settings lost: $(cat "$code")"
rm -f "$code_mark"; echo '{"window.dialogStyle": "native"}' >"$code"; run
[[ $(jq -r '."window.dialogStyle"' "$code") == native ]] || fail "the user's own window.dialogStyle replaced"
echo '{"a": 1}' >"$code"; run
[[ $(jq -c . "$code") == '{"a":1}' ]] || fail "window.dialogStyle added again after the user took it out"
# Claude Code's sessions folder (the Usage extension's error without it): made once, and one deleted stays deleted
[[ -d $t/home/.claude/projects ]] || fail "Claude Code's projects folder not made"
rm -r "$t/home/.claude"; run
[[ ! -e $t/home/.claude ]] || fail "Claude Code's folder, deleted, made again"
# Run for each user right after an update of AgrOS's settings or programs, not only at the next login (swappy's new
# config waited for one): a pacman hook agros-system installs, on both packages' install and upgrade, after the
# transaction, through agros-each-user, and before AgrOS's other hooks for each user (pacman runs them by file name:
# the config hypr-config-check checks is the updated one)
sys=$here/packages/agros-system
hooks=$(cd "$sys" && eval "printf '%s\n' $(sed -n 's|.*install -Dm644 -t "$pkgdir/usr/share/libalpm/hooks" ||p' PKGBUILD)" | LC_ALL=C sort)
links=$(cd "$sys" && grep -lx 'Exec = /usr/lib/agros/bin/agros-each-user\( --limit [0-9]*\)\? agros-links' $hooks) || true
[[ -n $links ]] || fail "no pacman hook agros-system installs runs agros-links for each user: $hooks"
for l in 'Operation = Install' 'Operation = Upgrade' 'Target = agros-hyprland-settings' 'Target = agros-scripts' \
    'When = PostTransaction'; do
    grep -qxF "$l" "$sys/$links" || fail "$links: no \"$l\""
done
for h in $hooks; do
    [[ $h == "$links" ]] && break
    ! grep -q 'agros-each-user' "$sys/$h" || fail "$h, run for each user, comes before $links"
done
# NVIDIA's shaders: Steam's games' from Lutris's folder moved into the driver's own (one already there kept), and a
# replaced driver's folders gone once its version changed, not on a same-version reinstall
c=$t/home/.cache g=37427d949c5fe9ac
mkdir -p "$c/lutris/shaders/steam/GLCache/new/$g" "$c/nvidia/GLCache/new/$g" "$c/nvidia/GLCache/old/$g" \
    "$c/lutris/shaders/wine/GLCache/old/$g" "$t/pacman/nvidia-utils-620.73.04-1"
for f in a.toc a.bin b.toc b.bin; do echo lutris >"$c/lutris/shaders/steam/GLCache/new/$g/$f"; done
echo mine >"$c/nvidia/GLCache/new/$g/b.toc"
echo old >"$c/nvidia/GLCache/old/$g/x.bin"; echo old >"$c/lutris/shaders/wine/GLCache/old/$g/y.bin"
touch -d '-2 days' "$c/nvidia/GLCache/old/$g/x.bin" "$c/lutris/shaders/wine/GLCache/old/$g/y.bin"
printf '%%NAME%%\nnvidia-utils\n\n%%VERSION%%\n620.73.04-1\n\n%%INSTALLDATE%%\n%s\n' "$(date -d '-1 day' +%s)" \
    >"$t/pacman/nvidia-utils-620.73.04-1/desc"
run >/dev/null
[[ $(cat "$c/nvidia/GLCache/new/$g/a.toc" "$c/nvidia/GLCache/new/$g/a.bin" 2>&1) == $'lutris\nlutris' ]] ||
    fail "Steam's shaders in Lutris's folder not moved into NVIDIA's"
[[ $(cat "$c/nvidia/GLCache/new/$g/b.toc") == mine && ! -e $c/nvidia/GLCache/new/$g/b.bin ]] ||
    fail "a game's shaders already in NVIDIA's folder replaced by Lutris's"
[[ ! -e $c/lutris/shaders/steam/GLCache ]] || fail "Lutris's Steam shader folder left behind"
[[ ! -e $c/nvidia/GLCache/old && ! -e $c/lutris/shaders/wine/GLCache/old ]] || fail "a replaced driver's shaders kept"
[[ -e $c/nvidia/GLCache/new ]] || fail "the installed driver's shaders deleted"
[[ $(cat "$t/home/.local/state/agros/nvidia-shaders-driver") == 620.73.04 ]] || fail "the driver's version not noted"
mkdir -p "$c/nvidia/GLCache/unused/$g"; echo x >"$c/nvidia/GLCache/unused/$g/z.bin"
touch -d '-2 days' "$c/nvidia/GLCache/unused/$g/z.bin"
sed -i 's/^620.73.04-1$/620.73.04-2/' "$t/pacman/nvidia-utils-620.73.04-1/desc"
run >/dev/null
[[ -e $c/nvidia/GLCache/unused ]] || fail "shaders deleted on a same-version reinstall of the driver"
echo "ok agros-links"
