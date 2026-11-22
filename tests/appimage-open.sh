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
img, pat = os.environ.get("IMG", "$t/img"), sys.argv[2].split("/")
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
cp "$t/Demo-x86_64.AppImage" "$t/orig.AppImage"  # (and one kept as it is, for the later cases)
export NOTIFY_WHEN_UP_TRIES=1  # (its notifications in the background: not tried for a minute after the test)
for c in pacman notify-send update-desktop-database sudo pkexec; do printf '#!/bin/sh\nexit 1\n' >"$t/bin/$c"; done
# (zenity: asked to run a file opened, noted with what it asked; "Run" unless $NO)
printf '#!/bin/sh\necho "asked $*" >>"%s/asked"\n[ -z "$NO" ]\n' "$t" >"$t/bin/zenity"
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
stick() {  # stick <home> <file> [env...]: the file installed (--install) from a drive that won't run it
    env "${@:3}" HOME="$1" PATH=$t/bin:$PATH python3 -I - "$here/.local/bin/appimage-open" "$2" <<'P'
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
}
stick "$t/stick-home" "$t/stick.AppImage" || fail "an AppImage on a drive that won't run it not installed"
[[ -x $t/stick-home/Applications/demo.AppImage && -f $t/stick.AppImage ]] ||
    fail "not installed from a copy, or the stick's file taken: $(ls "$t/stick-home/Applications" "$t")"
[[ $(ls -A "$t/stick-home/Applications") == demo.AppImage ]] || fail "a copy left: $(ls -A "$t/stick-home/Applications")"
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
# Opened from an installed AppImage (its APPIMAGE, which a download it opens or a terminal's shell inherits): asked all
# the same; that app's own new version too, as an update (read without running it: below, with unsquashfs)
cp "$t/home/Applications/demo.AppImage" "$t/from-app.AppImage"; chmod 644 "$t/from-app.AppImage"
NO=1 APPIMAGE=$t/home/Applications/demo.AppImage HOME=$t/from-home PATH=$t/bin:$PATH \
    python3 "$here/.local/bin/appimage-open" "$t/from-app.AppImage" || fail "a refused run from an installed app failed"
[[ -s $t/asked && ! -e $t/from-home/Applications && ! -x $t/from-app.AppImage ]] ||
    fail "a file opened from an installed AppImage run without asking: $(ls -l "$t/from-app.AppImage")"
rm -f "$t/asked"
# ...read for its launcher entry without running it, before you're asked: one that runs (here no squashfs in it, so
# nothing to read it with) isn't run to find out it's that app's (it said so, and was installed unasked)
cp "$t/orig.AppImage" "$t/same-id.AppImage"; chmod 755 "$t/same-id.AppImage"
NO=1 APPIMAGE=$t/home/Applications/demo.AppImage HOME=$t/home PATH=$t/bin:$PATH \
    python3 "$here/.local/bin/appimage-open" "$t/same-id.AppImage" || fail "a refused run from an installed app failed"
[[ -s $t/asked && -e $t/same-id.AppImage ]] || fail "a file opened from an installed AppImage run to read its entry, then not asked"
rm -f "$t/asked" "$t/same-id.AppImage"
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
    cat "$(type -P true)" "$t/sq.img" >"$t/real.AppImage"; chmod +x "$t/real.AppImage"
    HOME=$t/real-home PATH=$t/bin:$PATH python3 "$here/.local/bin/appimage-open" --install "$t/real.AppImage" >/dev/null 2>&1 ||
        fail "an AppImage not read with unsquashfs"
    grep -qx "Exec=$t/real-home/Applications/demo.AppImage %U" "$t/real-home/.local/share/applications/demo.desktop" &&
        [[ $(cat "$t/real-home/.local/share/icons/demo-appimage.png") == png ]] || fail "an AppImage's entry or icon not read with unsquashfs"
    # That app's own new version, opened by its Update button (its APPIMAGE the installed file): asked all the same
    # (APPIMAGE is inherited by all the app starts: a site's download naming itself as the app would take its place),
    # as an update; no, and the installed app stays as it is
    cp "$t/real-home/Applications/demo.AppImage" "$t/real-new.AppImage"; echo '# new' >>"$t/real-new.AppImage"; rm -f "$t/asked"
    NO=1 APPIMAGE=$t/real-home/Applications/demo.AppImage HOME=$t/real-home PATH=$t/bin:$PATH \
        python3 "$here/.local/bin/appimage-open" "$t/real-new.AppImage" >/dev/null 2>&1 || fail "a refused update failed"
    [[ $(cat "$t/asked" 2>/dev/null) == *"--title=Update Demo?"*"--ok-label=Update"* && -e $t/real-new.AppImage ]] &&
        ! cmp -s "$t/real-new.AppImage" "$t/real-home/Applications/demo.AppImage" ||
        fail "an app's own update (its APPIMAGE) not asked as an update, or installed after a no: $(cat "$t/asked" 2>/dev/null)"
    # ...yes, and it's installed
    rm -f "$t/asked"
    APPIMAGE=$t/real-home/Applications/demo.AppImage HOME=$t/real-home PATH=$t/bin:$PATH \
        python3 "$here/.local/bin/appimage-open" "$t/real-new.AppImage" >/dev/null 2>&1 || fail "an app's own update not installed"
    [[ $(cat "$t/asked" 2>/dev/null) == *"--title=Update Demo?"* && ! -e $t/real-new.AppImage ]] ||
        fail "an app's own update not installed after a yes: $(cat "$t/asked" 2>/dev/null)"
    # A launcher entry over 1 MB (one compressed to nearly nothing filled /tmp, which is memory, before you were
    # asked): its size listed first (unsquashfs -lls), never extracted; so no launcher entry, not installed
    mkdir -p "$t/sq-big"
    { printf '[Desktop Entry]\nName=Big\nExec=big\nType=Application\n'; head -c 2097152 /dev/zero | tr '\0' '#'; } >"$t/sq-big/demo.desktop"
    mksquashfs "$t/sq-big" "$t/sq-big.img" -quiet -noappend >/dev/null
    cat "$(type -P true)" "$t/sq-big.img" >"$t/big.AppImage"; chmod +x "$t/big.AppImage"
    # shellcheck disable=SC2016  # (expanded by the stand-in)
    printf '#!/bin/sh\necho "unsquashfs $*" >>%s/unsquashfs\nexec %s "$@"\n' "$t" "$(type -P unsquashfs)" >"$t/bin/unsquashfs"
    chmod +x "$t/bin/unsquashfs"
    out=$(HOME=$t/big-home PATH=$t/bin:$PATH python3 "$here/.local/bin/appimage-open" --install "$t/big.AppImage" 2>&1) &&
        fail "an AppImage with a launcher entry over 1 MB installed"
    [[ $out == *"no launcher entry inside"* ]] && grep -q -- '-lls ' "$t/unsquashfs" && ! grep -q -- ' -d ' "$t/unsquashfs" ||
        fail "a launcher entry over 1 MB extracted: $out / $(cat "$t/unsquashfs")"
    rm "$t/bin/unsquashfs"
else
    skipped "no squashfs-tools here: an AppImage read without running it not checked"
fi
# Nothing read from outside the AppImage: a launcher entry that's a link out of it (to a path of its own, or up out of
# it) not read, so not installed; an icon named as a path out of it (Icon=../../...) or as a pattern (which extracted
# more of it) not taken
mkdir -p "$t/esc-img" "$t/up-img" "$t/icon-img"
printf '[Desktop Entry]\nName=Outside\nExec=outside\nType=Application\n' >"$t/outside.desktop"
ln -s "$t/outside.desktop" "$t/esc-img/demo.desktop"
ln -s ../../../../../../../../../../../../../.."$t/outside.desktop" "$t/up-img/demo.desktop"
for img in esc-img up-img; do
    cp "$t/orig.AppImage" "$t/$img.AppImage"
    out=$(IMG=$t/$img HOME=$t/$img-home PATH=$t/bin:$PATH python3 "$here/.local/bin/appimage-open" --install "$t/$img.AppImage" 2>&1) &&
        fail "a launcher entry linked out of the AppImage ($img) installed: $out"
    [[ $out == *"no launcher entry inside"* && ! -e $t/$img-home/.local/share/applications/demo.desktop ]] ||
        fail "a launcher entry linked out of the AppImage ($img) read: $out"
done
echo secret >"$t/secret.png"; echo png >"$t/icon-img/demo.png"
for icon in "$(printf '../%.0s' {1..20})${t#/}/secret" 'd?mo' 'dem[o]'; do
    printf '[Desktop Entry]\nName=Demo\nExec=demo\nIcon=%s\nType=Application\n' "$icon" >"$t/icon-img/demo.desktop"
    cp "$t/orig.AppImage" "$t/icon.AppImage"; rm -rf "$t/icon-home"
    IMG=$t/icon-img HOME=$t/icon-home PATH=$t/bin:$PATH python3 "$here/.local/bin/appimage-open" --install "$t/icon.AppImage" >/dev/null 2>&1 ||
        fail "an AppImage with Icon=$icon not installed"
    [[ -z $(ls -A "$t/icon-home/.local/share/icons" 2>/dev/null) ]] && grep -qxF "Icon=$icon" "$t/icon-home/.local/share/applications/demo.desktop" ||
        fail "an icon taken by Icon=$icon: $(ls "$t/icon-home/.local/share/icons" 2>/dev/null)"
done
# Read up to a size alone where its own extract wrote it (no squashfs to list first): a launcher entry over 1 MB isn't
# read (none, not installed), an icon over 4 MB isn't taken
mkdir -p "$t/big-img"
{ printf '[Desktop Entry]\nName=Demo\nExec=demo\nType=Application\n'; head -c 2097152 /dev/zero | tr '\0' '#'; } >"$t/big-img/demo.desktop"
cp "$t/orig.AppImage" "$t/big.AppImage"
out=$(IMG=$t/big-img HOME=$t/big-home PATH=$t/bin:$PATH python3 "$here/.local/bin/appimage-open" --install "$t/big.AppImage" 2>&1) &&
    fail "an AppImage with a launcher entry over 1 MB installed"
[[ $out == *"no launcher entry inside"* && $out != *Traceback* ]] || fail "a launcher entry over 1 MB read: $out"
printf '[Desktop Entry]\nName=Demo\nExec=demo\nIcon=demo\nType=Application\n' >"$t/big-img/demo.desktop"
head -c 5242880 /dev/zero >"$t/big-img/demo.png"
cp "$t/orig.AppImage" "$t/big.AppImage"
IMG=$t/big-img HOME=$t/big-home PATH=$t/bin:$PATH python3 "$here/.local/bin/appimage-open" --install "$t/big.AppImage" >/dev/null 2>&1 ||
    fail "an AppImage with an icon over 4 MB not installed"
[[ -z $(ls -A "$t/big-home/.local/share/icons" 2>/dev/null) ]] && grep -qx 'Icon=demo' "$t/big-home/.local/share/applications/demo.desktop" ||
    fail "an icon over 4 MB taken: $(ls -l "$t/big-home/.local/share/icons" 2>/dev/null)"
# An update (appimage-update: --install with the repo's APPIMAGE_WEBSITE, its AppImage installed already) only as the
# same app: a release whose launcher entry is now firefox.desktop (an installed app's, its package's) not installed,
# nothing asked to be removed; the same app's update installed, its package's copy not asked about again (a first
# install's alone)
upd() {  # upd <image> [env...]: the repo's new release installed by appimage-update
    cp "$t/orig.AppImage" "$t/upd.AppImage"; rm -f "$t/ran"
    env IMG="$1" "${@:2}" APPIMAGE_WEBSITE=https://github.com/o/demo HOME=$t/upd-home PATH=$t/bin:$PATH \
        python3 "$here/.local/bin/appimage-open" --install "$t/upd.AppImage" 2>&1
}
upd "$t/img" OWNER= >/dev/null || fail "the first install from a repo failed"
mkdir -p "$t/ff-img"; printf '[Desktop Entry]\nName=Firefox\nExec=firefox\nType=Application\n' >"$t/ff-img/firefox.desktop"
echo '[Desktop Entry]' >"$t/sys/applications/firefox.desktop"
out=$(upd "$t/ff-img" OWNER=firefox) && fail "an update renaming its launcher entry to firefox.desktop installed: $out"
[[ $out == *"now firefox.desktop, not the installed app's (demo)"* && ! -e $t/upd-home/.local/share/applications/firefox.desktop &&
    ! -e $t/ran ]] || fail "an update taking another app's launcher entry not refused, or a package removal asked: $out / $(cat "$t/ran" 2>/dev/null)"
upd "$t/img" OWNER=demo-bin >/dev/null || fail "the same app's update not installed"
[[ ! -e $t/ran ]] || fail "an update asked to remove a package again: $(cat "$t/ran")"
# ...nor from a drive that won't run it, its file named as the installed one (demo.AppImage): the copy made to run it
# didn't write over the installed app before it was refused, and isn't left behind
{ cat "$t/orig.AppImage"; echo '# another build'; } >"$t/demo.AppImage"
out=$(stick "$t/upd-home" "$t/demo.AppImage" IMG="$t/ff-img" APPIMAGE_WEBSITE=https://github.com/o/demo 2>&1) &&
    fail "an update from a drive renaming its launcher entry installed: $out"
cmp -s "$t/orig.AppImage" "$t/upd-home/Applications/demo.AppImage" && [[ $(ls -A "$t/upd-home/Applications") == demo.AppImage ]] ||
    fail "a refused file from a drive wrote over the installed app, or its copy was left: $(ls -A "$t/upd-home/Applications")"
# A link to the installed file (a desktop shortcut) opened: that file, not the link moved over it (which deleted the app)
mkdir -p "$t/home/Desktop"; ln -sf "$t/home/Applications/demo.AppImage" "$t/home/Desktop/Demo"
HOME=$t/home PATH=$t/bin:$PATH python3 "$here/.local/bin/appimage-open" --install "$t/home/Desktop/Demo" >/dev/null 2>&1 ||
    fail "a link to the installed AppImage failed"
[[ -f $t/home/Applications/demo.AppImage && ! -L $t/home/Applications/demo.AppImage ]] ||
    fail "a link to the installed AppImage took its place: $(ls -l "$t/home/Applications")"
# Run from a drive that won't run it, with no launcher entry inside: its copy gone once it ends (exec skipped that)
mkdir -p "$t/noent-img"; cp "$t/orig.AppImage" "$t/noent.AppImage"
printf 'import sys\nsys.argv[1:] = ["--appimage-extract", "x"]\n' >/dev/null
stick_run() {
    env IMG="$t/noent-img" HOME="$1" PATH=$t/bin:$PATH python3 -I - "$here/.local/bin/appimage-open" "$2" <<'Q'
import importlib.machinery, importlib.util, os, sys
script, stick = sys.argv[1:]
loader = importlib.machinery.SourceFileLoader("appimage_open", script)
mod = importlib.util.module_from_spec(importlib.util.spec_from_loader("appimage_open", loader))
loader.exec_module(mod)
access, chmod = os.access, os.chmod
os.access = lambda p, m, **k: False if p == stick else access(p, m, **k)
os.chmod = lambda p, *a, **k: (_ for _ in ()).throw(PermissionError(1, "no", p)) if p == stick else chmod(p, *a, **k)
mod.ask_to_run = lambda src: True
sys.argv = ["appimage-open", stick]
mod.main()
Q
}
stick_run "$t/run-home" "$t/noent.AppImage" >/dev/null 2>&1 || true
[[ -z $(ls -A "$t/run-home/Applications" 2>/dev/null) ]] || fail "a run from a drive left its copy: $(ls -A "$t/run-home/Applications")"
echo "ok appimage-open"
