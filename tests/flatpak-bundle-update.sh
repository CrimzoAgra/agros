#!/usr/bin/env bash
# flatpak-bundle-update's version check: a release over the pre-release of the same number is newer, the same or an
# older one isn't. Its repo: the metainfo's source or home page link only, written down and kept; the file installed
# only when it's that app; a system-wide one only from a release with checksums
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
# shellcheck source=/dev/null  # (a function cut out of flatpak-bundle-update)
source <(sed -n '/^newer() {/,/^}/p' "$here/.local/bin/flatpak-bundle-update")
newer 0.1.34 0.1.33 || fail "0.1.34 not newer than 0.1.33"
newer 0.1.33 0.1.33-alpha || fail "0.1.33 not newer than 0.1.33-alpha"
newer 0.1.33-beta 0.1.33-alpha || fail "0.1.33-beta not newer than 0.1.33-alpha"
newer 0.1.34-alpha 0.1.33 || fail "0.1.34-alpha not newer than 0.1.33"
! newer 0.1.33 0.1.33 || fail "the same version counted as newer"
! newer 0.1.33-alpha 0.1.33 || fail "a pre-release counted as newer than its release"
! newer 0.1.9 0.1.10 || fail "0.1.9 counted as newer than 0.1.10"
# (the repos written down: the test's own list, not your home's)
export AGROS_FLATPAK_BUNDLES=$t/bundles
fbu() { HOME=$t/home PATH=$t/bin:$PATH "$here/.local/bin/flatpak-bundle-update" "$@"; }
# A release with no Linux .flatpak (yet: its files still uploading, or none for Linux) isn't announced as an update
# that then fails to install (flatpak and curl stubbed: a bundle on 1.0, its repo's latest release 1.1, Windows only)
mkdir -p "$t/bin" "$t/app/files/share/metainfo"
echo '<url type="homepage">https://github.com/o/app</url>' >"$t/app/files/share/metainfo/a.xml"
cat >"$t/bin/flatpak" <<F
#!/bin/bash
case "\$*" in
    list*) printf 'com.x.App\tapp-origin\tuser\n' ;;
    *--show-location*) echo "$t/app" ;;
    info*) echo '  Version: 1.0' ;;
esac
F
printf '#!/bin/sh\necho "$*" >>%s/asked\ncat %s/release\n' "$t" "$t" >"$t/bin/curl"
chmod +x "$t/bin/flatpak" "$t/bin/curl"
release() {  # release <asset name>...: the latest release, 1.1, with those files
    printf '%s\n' "$@" | jq -R '{name: ., browser_download_url: ("https://x/" + .)}' | jq -s '{tag_name: "v1.1", assets: .}' >"$t/release"
}
release App-x64.exe
out=$(fbu --check) || true
[[ $out == *"no Linux .flatpak"* && $out != *"update available"* ]] || fail "a release without a .flatpak announced as an update: $out"
# (the same release with one: announced)
release App-x86_64.flatpak
out=$(fbu --check) || true
[[ $out == *"update available (1.0 -> 1.1)"* ]] || fail "a release with a .flatpak not announced: $out"
# Its repo from the app's own metainfo, by its home page, not the first github.com link in it (a library's)
rm -f "$AGROS_FLATPAK_BUNDLES"
printf '%s\n' '<a href="https://github.com/lib/other">lib</a>' '<url type="homepage">https://github.com/o/app</url>' \
    >"$t/app/files/share/metainfo/com.x.App.metainfo.xml"
printf '#!/bin/sh\ncase "$*" in *repos/o/app/*) cat %s/release ;; *) exit 22 ;; esac\n' "$t" >"$t/bin/curl"
out=$(fbu --check) || true
[[ $out == *"update available (1.0 -> 1.1)"* ]] || fail "the repo taken from another link than the app's home page: $out"
# ...written down, and kept: a later metainfo pointing elsewhere doesn't move its updates there
[[ $(cat "$AGROS_FLATPAK_BUNDLES") == $'user\tcom.x.App\to/app' ]] || fail "the repo not written down: $(cat "$AGROS_FLATPAK_BUNDLES" 2>/dev/null)"
echo '<url type="homepage">https://github.com/evil/app</url>' >"$t/app/files/share/metainfo/com.x.App.metainfo.xml"
out=$(fbu --check) || true
[[ $out == *"update available (1.0 -> 1.1)"* ]] || fail "a changed metainfo moved the app's updates to another repo: $out"
# ...and no source or home page link (only another github.com one): no repo, said, nothing asked of GitHub
rm -f "$AGROS_FLATPAK_BUNDLES" "$t/asked"
echo '<a href="https://github.com/lib/other">lib</a>' >"$t/app/files/share/metainfo/com.x.App.metainfo.xml"
printf '#!/bin/sh\necho "$*" >>%s/asked\ncat %s/release\n' "$t" "$t" >"$t/bin/curl"
out=$(fbu --check) || true
[[ $out == *"com.x.App: no GitHub repo"* && ! -e $t/asked ]] || fail "a repo guessed from any github.com link: $out / $(cat "$t/asked" 2>/dev/null)"
# ...but its own bug tracker's is its own (ArtCraft's: its home page is its website)
printf '%s\n' '<url type="homepage">https://example.com/app</url>' '<url type="bugtracker">https://github.com/o/app/issues</url>' \
    >"$t/app/files/share/metainfo/com.x.App.metainfo.xml"
out=$(fbu --check) || true
[[ $out == *"update available (1.0 -> 1.1)"* ]] && grep -q 'repos/o/app/' "$t/asked" || fail "the repo not taken from its bug tracker link: $out"
rm -f "$AGROS_FLATPAK_BUNDLES"
echo '<url type="homepage">https://github.com/o/app</url>' >"$t/app/files/share/metainfo/com.x.App.metainfo.xml"
# The boot's update's two steps: --fetch downloads an update's file into a folder (nothing installed: it holds nothing),
# --install-fetched then reinstalls from it (the boot's update holds sleep and power off as root around that alone).
# The file's app read as flatpak reads it (build-import-bundle into a repo of its own, ostree refs): here the folder it's
# fetched into names it ($REF: another app's file)
rm -f "$AGROS_FLATPAK_BUNDLES"
cat >"$t/bin/flatpak" <<F
#!/bin/bash
case "\$*" in
    list*) printf 'com.x.App\tapp-origin\tuser\ncom.x.Sys\tsys-origin\tsystem\n' ;;
    *--show-location*) echo "$t/app" ;;
    *--show-metadata*) cat "$t/oldmeta" ;;
    *--show-origin*) echo app-origin ;;
    info*runtime/*) exit 1 ;;
    info*) echo '  Version: 1.0' ;;
    install*) echo "flatpak \$*" >>"$t/installs" ;;
    remotes*) printf 'app-origin\thttps://example.com/repo\nflathub\thttps://dl.flathub.org/repo/\n' ;;
    remote-modify*) echo "flatpak \$*" >>"$t/modified"; [ -z "\${MODIFY_FAILS:-}" ] ;;
    build-import-bundle*) echo "\$2" >>"$t/imported"; echo "app/\${REF:-\$(basename "\$(dirname "\$2")")}/x86_64/stable" >"\$2/refs" ;;
    build-bundle*) echo "flatpak \$*" >>"$t/bundled"; echo bundle >"\$4" ;;
esac
F
# (the metadata of the version installed, oldmeta, and of the file's, newmeta: the same access here)
printf '[Application]\nname=com.x.App\nruntime=org.x.Platform/x86_64/1\n\n[Context]\nshared=network;\n' >"$t/oldmeta"
cp "$t/oldmeta" "$t/newmeta"
# shellcheck disable=SC2016  # (the stand-in's)
stub ostree 'case $1 in refs) cat "${2#--repo=}/refs" ;; cat) cat "'"$t"'/newmeta" ;; esac'
sum=$(echo bundle | sha256sum | cut -d' ' -f1)
cat >"$t/bin/curl" <<C
#!/bin/sh
o= prev=
for a; do [ "\$prev" = -o ] && o=\$a; prev=\$a; done
case "\$o:\$a" in
    :*) cat "$t/release" ;;
    *SHA256SUMS) echo "$sum  App-x86_64.flatpak" >"\$o" ;;
    *) echo bundle >"\$o" ;;
esac
C
chmod +x "$t/bin/flatpak" "$t/bin/curl"
mkdir -p "$t/fetched"
out=$(fbu --fetch "$t/fetched" 2>&1) || fail "--fetch failed: $out"
[[ ! -e $t/installs && $(cut -f1,3,4 "$t/fetched/fetched") == $'user\tcom.x.App\t1.1' && $(cat "$(cut -f2 "$t/fetched/fetched")") == bundle ]] ||
    fail "--fetch didn't only download the user's own update (a system-wide one is root's, done once): $out / $(cat "$t/fetched/fetched" 2>/dev/null) / $(cat "$t/installs" 2>/dev/null)"
# ...and the file made again from what flatpak read of it, with no repo URL nor runtime repo for flatpak to set on its
# remote (the file as downloaded gone): that file's the one installed
{ [[ $(cut -f2 "$t/fetched/fetched") == "$t/fetched/com.x.App/com.x.App.flatpak" && ! -e $t/fetched/com.x.App/App-x86_64.flatpak ]] &&
    grep -qx "flatpak build-bundle --arch=x86_64 $t/fetched/com.x.App/\.ref\.[A-Za-z0-9]* $t/fetched/com.x.App/com.x.App.flatpak com.x.App stable" "$t/bundled"; } ||
    fail "the file not made again with no URL in it: $(cat "$t/fetched/fetched") / $(cat "$t/bundled" 2>/dev/null)"
# An app installed from a file that carried a repo URL (its <name>-origin remote has it, so flatpak update took the app
# from there, past every check here): the URL emptied, as for a file without one, at the next run
grep -qx "flatpak remote-modify --user --url= app-origin" "$t/modified" || fail "an app's origin remote kept its URL: $(cat "$t/modified" 2>/dev/null)"
rm -f "$t/modified"
# --no-origin-urls (before every flatpak update: auto-update's, update-kinds'): every -origin remote's URL emptied in
# the installations given, no other remote's (Flathub's); one that couldn't be (a password prompt cancelled) fails
out=$(fbu --no-origin-urls user system 2>&1) || fail "--no-origin-urls failed: $out"
[[ $(cat "$t/modified") == $'flatpak remote-modify --user --url= app-origin\nflatpak remote-modify --system --url= app-origin' ]] ||
    fail "--no-origin-urls didn't empty the -origin remotes alone: $(cat "$t/modified")"
MODIFY_FAILS=1 fbu --no-origin-urls system >/dev/null 2>&1 && fail "--no-origin-urls succeeded with a URL left"
rm -f "$t/modified"
# Another app's file in the release: not taken
mkdir -p "$t/fetched-other"
out=$(REF=com.evil.App fbu --fetch "$t/fetched-other" 2>&1) && fail "--fetch took another app's file: $out"
[[ ! -s $t/fetched-other/fetched && $out == *"is com.evil.App, not com.x.App"* ]] || fail "another app's file not refused, said: $out"
# A new version asking for more access than the one installed (your whole home, Flatpak's own bus: out of its sandbox):
# not taken at boot (flatpak install -y would grant it unasked), said to be updated from Updates
printf '%s\n' '[Application]' 'name=com.x.App' 'runtime=org.x.Platform/x86_64/1' '[Context]' 'shared=network;' 'filesystems=host;' \
    '[Session Bus Policy]' 'org.freedesktop.Flatpak=talk' >"$t/newmeta"
mkdir -p "$t/fetched-more"
out=$(fbu --fetch "$t/fetched-more" 2>&1) && fail "--fetch took a version asking for more access: $out"
[[ ! -s $t/fetched-more/fetched && $out == *"com.x.App: its new version asks for more access ([Context]filesystems=host, [Session Bus Policy]org.freedesktop.Flatpak=talk): update it from Updates"* ]] ||
    fail "a version asking for more access fetched at boot, or not said: $out"
# ...read as flatpak reads it (GLib's GKeyFile): a group header with a space or tab after it, an indented one, CRLF
# line ends hide nothing; one GLib can't read counts as more
evade() {  # evade <name> <metadata printf format>: a new version so written, refused at boot
    # shellcheck disable=SC2059  # (the format is the case)
    printf "$2" >"$t/newmeta"
    mkdir -p "$t/fetched-$1"
    out=$(fbu --fetch "$t/fetched-$1" 2>&1) && fail "--fetch took a version asking for more access ($1): $out"
    [[ ! -s $t/fetched-$1/fetched && $out == *"com.x.App: its new version asks for more access ($3): update it from Updates"* ]] ||
        fail "a version asking for more access ($1) fetched at boot, or not said: $out"
}
evade space '[Application]\nname=com.x.App\n[Context] \nshared=network;\nfilesystems=host;\n' '[Context]filesystems=host'
evade indent '[Application]\nname=com.x.App\n  [Context]\nshared=network;\nfilesystems=host;\n' '[Context]filesystems=host'
evade tab '[Application]\nname=com.x.App\n[Session Bus Policy]\t\norg.freedesktop.Flatpak=talk\n[Context]\nshared=network;\n' \
    '[Session Bus Policy]org.freedesktop.Flatpak=talk'
evade crlf '[Application]\r\nname=com.x.App\r\n[Context]\r\nshared=network;\r\nfilesystems=host;\r\n' '[Context]filesystems=host'
evade unreadable '[Application]\nname=com.x.App\n[Context]\nshared=network;\nfilesystems=\377host;\n' "metadata that couldn't be read"
printf '%s\n' '[Application]' 'name=com.x.App' 'runtime=org.x.Platform/x86_64/1' '[Context]' 'shared=network;' 'filesystems=host;' \
    '[Session Bus Policy]' 'org.freedesktop.Flatpak=talk' >"$t/newmeta"
# ...from Updates (no --fetch: you started it), installed, what it adds said in its log
rm -f "$t/installs"
out=$(REF=com.x.App FLATPAK_BUNDLE_HELD=1 fbu 2>&1) || true  # (a temp folder here, not one named after the app)
[[ $out == *"com.x.App: its new version asks for more access: [Context]filesystems=host, [Session Bus Policy]org.freedesktop.Flatpak=talk"* &&
    $out == *"com.x.App: updated to 1.1"* ]] && grep -q -- '--user .*--bundle ' "$t/installs" ||
    fail "Updates didn't install a version asking for more access, or didn't say what it adds: $out / $(cat "$t/installs" 2>/dev/null)"
# ...its download and the repo it's read into in your cache, on disk (in /tmp they took memory), gone after
[[ $(tail -1 "$t/imported") == "$t/home/.cache/agros-flatpak."*/.ref.* && -z $(ls -A "$t/home/.cache") ]] ||
    fail "Updates' download not in the cache, or left there: $(tail -1 "$t/imported") / $(ls -A "$t/home/.cache")"
rm -f "$t/installs"
# ...and less (a list's value gone, a "!" taking one away) isn't more: fetched at boot
printf '%s\n' '[Application]' 'name=com.x.App' '[Context]' 'filesystems=!home;' >"$t/newmeta"
mkdir -p "$t/fetched-less"
out=$(fbu --fetch "$t/fetched-less" 2>&1) || fail "--fetch refused a version asking for less access: $out"
[[ $(cut -f3 "$t/fetched-less/fetched") == com.x.App ]] || fail "a version asking for less access not fetched: $out"
cp "$t/oldmeta" "$t/newmeta"
# As root (the boot's own run: here in a user namespace, root in name only), the system-wide one is fetched too, but
# only from a release with checksums
if unshare -r true 2>/dev/null; then
    mkdir -p "$t/fetched-root"
    out=$(PATH=$t/bin:$PATH unshare -r "$here/.local/bin/flatpak-bundle-update" --fetch "$t/fetched-root" 2>&1) &&
        fail "--fetch as root took a system-wide one with no checksums"
    [[ $(cut -f1,3 "$t/fetched-root/fetched") == $'user\tcom.x.App' && $out == *"no checksums, not installed for every account"* ]] ||
        fail "--fetch as root: a system-wide one fetched with no checksums, or the user's not: $out / $(cat "$t/fetched-root/fetched" 2>/dev/null)"
    release App-x86_64.flatpak SHA256SUMS
    mkdir -p "$t/fetched-root2"
    out=$(PATH=$t/bin:$PATH unshare -r "$here/.local/bin/flatpak-bundle-update" --fetch "$t/fetched-root2" 2>&1) || fail "--fetch as root failed: $out"
    [[ $(cut -f1,3 "$t/fetched-root2/fetched" | sort | paste -sd' ') == $'system\tcom.x.Sys user\tcom.x.App' ]] ||
        fail "--fetch as root didn't take the system-wide one too: $out / $(cat "$t/fetched-root2/fetched" 2>/dev/null)"
else
    skipped "no user namespace to be root in: the root run's system-wide fetch not run"
fi
rm -f "$t/installs" "$t/modified"
out=$(fbu --install-fetched "$t/fetched" 2>&1) || fail "--install-fetched failed: $out"
{ grep -qx "flatpak install --user -y --noninteractive --no-deps --reinstall --bundle $t/fetched/com.x.App/com.x.App.flatpak" "$t/installs" &&
    [[ $out == *"com.x.App: updated to 1.1"* ]]; } || fail "--install-fetched didn't reinstall from the file: $out / $(cat "$t/installs")"
# ...its runtime (not installed here) from Flathub first, never a repo the file names (flatpak install -y added that
# as a remote unasked), and its origin remote's URL, if the file gave it one, emptied after
[[ $(sed -n 1p "$t/installs") == "flatpak install --user -y --noninteractive flathub runtime/org.x.Platform/x86_64/1" ]] ||
    fail "the runtime not installed from Flathub before the file: $(cat "$t/installs")"
grep -qx "flatpak remote-modify --user --url= app-origin" "$t/modified" || fail "the origin remote's URL not emptied after the install: $(cat "$t/modified" 2>/dev/null)"
# Two apps fetched: both reinstalled, flatpak install (which may read its stdin) not eating the list's next line
printf '%s\n' '#!/bin/bash' "case \"\$*\" in install*) cat >/dev/null; echo \"flatpak \$*\" >>'$t/installs2' ;; esac" >"$t/bin/flatpak"
printf 'user\t%s\tcom.x.A\t2\nsystem\t%s\tcom.x.B\t3\n' "$t/a.flatpak" "$t/b.flatpak" >"$t/fetched/fetched"
cp "$t/oldmeta" "$t/.metadata"  # (theirs, bundle_app's copy beside the file)
out=$(fbu --install-fetched "$t/fetched" 2>&1) || fail "--install-fetched (two apps) failed: $out"
{ [[ $(grep -c -- '--reinstall --bundle' "$t/installs2") == 2 && $out == *"com.x.A: updated to 2"* && $out == *"com.x.B: updated to 3"* ]] &&
    grep -q -- "--system -y --noninteractive --no-deps --reinstall --bundle $t/b.flatpak" "$t/installs2"; } ||
    fail "--install-fetched didn't reinstall both apps: $out / $(cat "$t/installs2" 2>/dev/null)"
# --install: found already installed as the update finds an app's repo, among the ones installed from a file only: one
# whose metainfo names a repo with the same start (o/app-other), or a Flathub app's that links to it, isn't it; its
# own is, whatever the case and a .git
rm -f "$AGROS_FLATPAK_BUNDLES"
cat >"$t/bin/flatpak" <<F
#!/bin/bash
case "\$*" in
    list*) cat "$t/list" ;;
    *--show-location*) echo "$t/loc/\${*: -1}" ;;
    install*) echo "flatpak \$*" >>"$t/installs3" ;;
    build-import-bundle*) echo "app/com.x.New/x86_64/stable" >"\$2/refs" ;;
esac
F
meta() { mkdir -p "$t/loc/$1/files/share/metainfo"; echo "<url type=\"homepage\">https://github.com/$2</url>" >"$t/loc/$1/files/share/metainfo/$1.metainfo.xml"; }
meta com.x.Other o/app-other; meta com.x.Flathub o/app
printf 'com.x.Other\tother-origin\tuser\ncom.x.Flathub\tflathub\tsystem\n' >"$t/list"
# (no hold on sleep here: this machine's logind isn't asked)
out=$(FLATPAK_BUNDLE_HELD=1 fbu --install o/app 2>&1) || true
[[ $out != *"already installed"* ]] || fail "--install o/app found o/app-other or a Flathub app installed"
# ...installed then (the release's file, for the user), its repo written down for its updates
[[ $out == *"o/app: installed v1.1"* ]] && grep -q -- "--user -y --noninteractive --no-deps --reinstall --bundle " "$t/installs3" &&
    grep -qx $'user\tcom.x.New\to/app' "$AGROS_FLATPAK_BUNDLES" ||
    fail "--install o/app: not installed, or its repo not written down: $out / $(cat "$AGROS_FLATPAK_BUNDLES" 2>/dev/null)"
rm -f "$AGROS_FLATPAK_BUNDLES"
meta com.x.App O/App.git; printf 'com.x.App\tapp-origin\tuser\n' >>"$t/list"
out=$(fbu --install o/app 2>&1) || true
[[ $out == "o/app: already installed" ]] || fail "--install o/app didn't find it installed: $out"
out=$(fbu --install o/app.git 2>&1) || true
[[ $out == "o/app.git: already installed" ]] || fail "--install o/app.git didn't find it installed: $out"
echo "ok flatpak-bundle-update"
