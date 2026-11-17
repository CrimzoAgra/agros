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
    HOME=$t/home XDG_STATE_HOME=$t/home/.local/state AGROS_LIB=$t/lib AGROS_SKEL=$t/skel \
        AGROS_SKEL_VERSIONS=$t/versions "$t/lib/bin/agros-links" | cat
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
echo "ok agros-links"
