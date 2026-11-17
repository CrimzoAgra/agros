#!/usr/bin/env bash
# appimage-open installs an AppImage whose launcher entry and icon at its top are links into usr/share (linuxdeploy
# makes them so): extracting a link extracts only the link, so the entry couldn't be read (a crash, nothing installed)
# and the icon was lost. A fake AppImage extracts as the real runtime does (a pattern per path part, links as links)
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
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
cp "$t/Demo-x86_64.AppImage" "$t/stick.AppImage"  # (and one on a drive that won't run it, below)
export NOTIFY_WHEN_UP_TRIES=1  # (its notifications in the background: not tried for a minute after the test)
for c in pacman notify-send update-desktop-database sudo pkexec; do printf '#!/bin/sh\nexit 1\n' >"$t/bin/$c"; done
# (zenity: asked to run a file opened, noted; "Run" unless $NO)
printf '#!/bin/sh\necho asked >>"%s/asked"\n[ -z "$NO" ]\n' "$t" >"$t/bin/zenity"
# (only the system's launcher entries the test makes)
export XDG_DATA_DIRS=$t/sys
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
# On a drive that won't run it (a USB stick's FAT, a noexec or read-only mount: not made executable, nor runnable):
# a copy installed, not a traceback; the stick's own file left as it is
HOME=$t/stick-home PATH=$t/bin:$PATH python3 -I - "$here/.local/bin/appimage-open" "$t/stick.AppImage" <<'P' ||
import importlib.machinery, importlib.util, os, sys
script, stick = sys.argv[1:]
loader = importlib.machinery.SourceFileLoader("appimage_open", script)
mod = importlib.util.module_from_spec(importlib.util.spec_from_loader("appimage_open", loader))
loader.exec_module(mod)
access, chmod = os.access, os.chmod
os.access = lambda p, m, **k: False if p == stick else access(p, m, **k)
def no_chmod(p, *a, **k):
    if p == stick:
        raise PermissionError(1, "Operation not permitted", p)
    return chmod(p, *a, **k)
os.chmod = no_chmod
sys.argv = ["appimage-open", "--install", stick]
mod.main()
P
    fail "an AppImage on a drive that won't run it not installed"
[[ -x $t/stick-home/Applications/demo.AppImage && -f $t/stick.AppImage ]] ||
    fail "not installed from a copy, or the stick's file taken: $(ls "$t/stick-home/Applications" "$t")"
[[ -z $(compgen -G "$t/stick-home/Applications/*.new") ]] || fail "a copy's temporary file left"
# The system package with the same launcher entry (demo-bin owns /usr/share/applications/demo.desktop): removed with
# --install (appimage-update), sudo without asking when it can; never for an AppImage only opened (any file could
# name a package's entry), nor when no package owns it. sudo and pkexec log what they'd run
# shellcheck disable=SC2016  # (expanded by the stand-ins)
printf '#!/bin/sh\n[ "$1 $2" = "-Qqo /usr/share/applications/demo.desktop" ] && [ -n "$OWNER" ] && echo "$OWNER"\n' >"$t/bin/pacman"
for c in sudo pkexec; do printf '#!/bin/sh\necho "%s $*" >>"%s/ran"\n' "$c" "$t" >"$t/bin/$c"; done
remove() {  # <home> [--install]
    rm -f "$t/ran"; cp "$t/home/Applications/demo.AppImage" "$t/pkg.AppImage"
    HOME=$1 PATH=$t/bin:$PATH python3 "$here/.local/bin/appimage-open" ${2:+"$2"} "$t/pkg.AppImage" >/dev/null 2>&1
}
OWNER=demo-bin remove "$t/pkg-home" --install || fail "not installed over a package's copy"
grep -qx "sudo -n pacman -R --noconfirm demo-bin" "$t/ran" || fail "the package's copy not removed with --install: $(cat "$t/ran" 2>/dev/null)"
OWNER=demo-bin remove "$t/open-home" || fail "an opened AppImage not installed"
grep -q pacman "$t/ran" 2>/dev/null && fail "a package removed for an AppImage only opened: $(cat "$t/ran")"
OWNER='' remove "$t/none-home" --install || fail "not installed with no package's copy"
grep -q pacman "$t/ran" 2>/dev/null && fail "a package removed with none owning the entry: $(cat "$t/ran")"
# A file you open is asked about before anything (made runnable, read, run): no, and nothing's done; an installed one
# (in ~/Applications) or --install isn't asked
rm -f "$t/asked"; cp "$t/home/Applications/demo.AppImage" "$t/ask.AppImage"; chmod 644 "$t/ask.AppImage"
NO=1 HOME=$t/ask-home PATH=$t/bin:$PATH python3 "$here/.local/bin/appimage-open" "$t/ask.AppImage" || fail "a refused run failed"
[[ -s $t/asked && ! -e $t/ask-home/Applications && ! -x $t/ask.AppImage ]] ||
    fail "a file opened not asked about, or made runnable or installed after a no: $(ls -l "$t/ask.AppImage")"
rm -f "$t/asked"
HOME=$t/home PATH=$t/bin:$PATH python3 "$here/.local/bin/appimage-open" --install "$t/ask.AppImage" >/dev/null 2>&1 || fail "--install failed"
[[ ! -e $t/asked ]] || fail "--install (appimage-update) asked"
# A launcher entry that's another app's: an installed one's (an AppImage naming itself as LibreWolf), or a file of yours
# (written over before), not installed, said; nothing moved into ~/Applications
mkdir -p "$t/sys/applications"; echo '[Desktop Entry]' >"$t/sys/applications/demo.desktop"
cp "$t/home/Applications/demo.AppImage" "$t/clash.AppImage"
out=$(HOME=$t/clash-home PATH=$t/bin:$PATH python3 "$here/.local/bin/appimage-open" "$t/clash.AppImage" 2>&1) &&
    fail "an AppImage installed over an installed app's launcher entry"
[[ $out == *"already another app's ($t/sys/applications/demo.desktop)"* && ! -e $t/clash-home/Applications/demo.AppImage &&
    ! -e $t/clash-home/.local/share/applications/demo.desktop ]] || fail "an installed app's launcher entry taken over, or not said: $out"
rm "$t/sys/applications/demo.desktop"
mkdir -p "$t/clash-home/.local/share/applications"; echo '[Desktop Entry]' >"$t/clash-home/.local/share/applications/demo.desktop"
out=$(HOME=$t/clash-home PATH=$t/bin:$PATH python3 "$here/.local/bin/appimage-open" --install "$t/clash.AppImage" 2>&1) &&
    fail "an AppImage installed over your own launcher entry"
[[ $(cat "$t/clash-home/.local/share/applications/demo.desktop") == '[Desktop Entry]' ]] || fail "your own launcher entry written over: $out"
# Read without running it: a real AppImage's layout (an ELF, here one that does nothing, then a squashfs image of its
# files) installed through unsquashfs; its own --appimage-extract would have extracted nothing
if command -v mksquashfs >/dev/null && command -v unsquashfs >/dev/null; then
    mkdir -p "$t/sq/usr/share/applications"
    cp "$t/img/usr/share/applications/demo.desktop" "$t/sq/usr/share/applications/"
    ln -s usr/share/applications/demo.desktop "$t/sq/demo.desktop"; echo png >"$t/sq/demo.png"
    mksquashfs "$t/sq" "$t/sq.img" -quiet -noappend >/dev/null
    cat "$(command -v true)" "$t/sq.img" >"$t/real.AppImage"; chmod +x "$t/real.AppImage"
    HOME=$t/real-home PATH=$t/bin:$PATH python3 "$here/.local/bin/appimage-open" --install "$t/real.AppImage" >/dev/null 2>&1 ||
        fail "an AppImage not read with unsquashfs"
    grep -qx "Exec=$t/real-home/Applications/demo.AppImage %U" "$t/real-home/.local/share/applications/demo.desktop" &&
        [[ $(cat "$t/real-home/.local/share/icons/demo-appimage.png") == png ]] || fail "an AppImage's entry or icon not read with unsquashfs"
else
    skipped "no squashfs-tools here: an AppImage read without running it not checked"
fi
echo "ok appimage-open"
