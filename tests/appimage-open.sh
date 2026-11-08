#!/usr/bin/env bash
# appimage-open installs an AppImage whose launcher entry and icon at its top are links into usr/share (linuxdeploy
# makes them so): extracting a link extracts only the link, so the entry couldn't be read (a crash, nothing installed)
# and the icon was lost. A fake AppImage extracts as the real runtime does (a pattern per path part, links as links)
set -euo pipefail
. "$(dirname "$0")/lib.sh"
mkdir -p "$t/home" "$t/bin" "$t/img/usr/share/applications" "$t/img/usr/share/icons/hicolor/256x256/apps"
printf '[Desktop Entry]\nName=Demo\nExec=demo %%U\nIcon=demo\nType=Application\n' >"$t/img/usr/share/applications/demo.desktop"
echo png >"$t/img/usr/share/icons/hicolor/256x256/apps/demo.png"
ln -s usr/share/applications/demo.desktop "$t/img/demo.desktop"
ln -s usr/share/icons/hicolor/256x256/apps/demo.png "$t/img/demo.png"
cat >"$t/Demo-x86_64.AppImage" <<EOF
#!/usr/bin/python3
import fnmatch, os, shutil, sys
img, pat = "$t/img", sys.argv[2].split("/")
for d, dirs, files in os.walk(img):
    for f in dirs + files:
        rel = os.path.relpath(os.path.join(d, f), img).split("/")
        # FNM_FILE_NAME | FNM_LEADING_DIR: "*" stays within a part; a match of the leading parts takes what's under them
        if len(rel) >= len(pat) and all(fnmatch.fnmatchcase(r, p) for r, p in zip(rel, pat)):
            src, dst = os.path.join(d, f), os.path.join("squashfs-root", *rel)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            if os.path.islink(src):
                os.symlink(os.readlink(src), dst)
            elif os.path.isfile(src):
                shutil.copy(src, dst)
EOF
chmod +x "$t/Demo-x86_64.AppImage"
cp "$t/Demo-x86_64.AppImage" "$t/again.AppImage"  # (installing moves it: a copy for the second home below)
for c in pacman notify-send update-desktop-database sudo pkexec; do printf '#!/bin/sh\nexit 1\n' >"$t/bin/$c"; done
chmod +x "$t"/bin/*
HOME=$t/home PATH=$t/bin:$PATH python3 "$here/.local/bin/appimage-open" --install "$t/Demo-x86_64.AppImage" ||
    fail "not installed"
entry=$t/home/.local/share/applications/demo.desktop
[[ -f $entry ]] || fail "no launcher entry"
grep -qx "Exec=$t/home/Applications/demo.AppImage %U" "$entry" || fail "the entry doesn't run the installed file: $(grep ^Exec "$entry")"
grep -qx "Icon=$t/home/.local/share/icons/demo-appimage.png" "$entry" || fail "the icon not taken from the AppImage: $(grep ^Icon "$entry")"
[[ $(cat "$t/home/.local/share/icons/demo-appimage.png") == png ]] || fail "the icon file isn't the AppImage's"
# A home with a space in it: the program quoted in the entry (unquoted it ran ".../ho" with "me/..." as an argument)
mkdir -p "$t/ho me"
HOME="$t/ho me" PATH=$t/bin:$PATH python3 "$here/.local/bin/appimage-open" --install "$t/again.AppImage" || fail "not installed"
grep -qxF "Exec=\"$t/ho me/Applications/demo.AppImage\" %U" "$t/ho me/.local/share/applications/demo.desktop" ||
    fail "the program not quoted: $(grep ^Exec "$t/ho me/.local/share/applications/demo.desktop")"
# Not an AppImage that runs here (a file of another kind): said, not a traceback
printf 'not a program' >"$t/broken.AppImage"
out=$(HOME=$t/home PATH=$t/bin:$PATH python3 "$here/.local/bin/appimage-open" --install "$t/broken.AppImage" 2>&1) &&
    fail "a broken AppImage installed"
[[ $out == *"no launcher entry inside"* && $out != *Traceback* ]] || fail "a broken AppImage not said: $out"
echo "ok appimage-open"
