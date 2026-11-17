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
fbu() { PATH=$t/bin:$PATH "$here/.local/bin/flatpak-bundle-update" "$@"; }
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
    info*) echo '  Version: 1.0' ;;
    install*) echo "flatpak \$*" >>"$t/installs" ;;
    build-import-bundle*) echo "app/\${REF:-\$(basename "\$(dirname "\$2")")}/x86_64/stable" >"\$2/refs" ;;
esac
F
# shellcheck disable=SC2016  # (the stand-in's)
stub ostree 'case $1 in refs) cat "${2#--repo=}/refs" ;; esac'
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
# Another app's file in the release: not taken
mkdir -p "$t/fetched-other"
out=$(REF=com.evil.App fbu --fetch "$t/fetched-other" 2>&1) && fail "--fetch took another app's file: $out"
[[ ! -s $t/fetched-other/fetched && $out == *"is com.evil.App, not com.x.App"* ]] || fail "another app's file not refused, said: $out"
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
out=$(fbu --install-fetched "$t/fetched" 2>&1) || fail "--install-fetched failed: $out"
{ grep -qx "flatpak install --user -y --noninteractive --reinstall --bundle $t/fetched/com.x.App/App-x86_64.flatpak" "$t/installs" &&
    [[ $out == *"com.x.App: updated to 1.1"* ]]; } || fail "--install-fetched didn't reinstall from the file: $out / $(cat "$t/installs")"
# Two apps fetched: both reinstalled, flatpak install (which may read its stdin) not eating the list's next line
printf '%s\n' '#!/bin/bash' "case \"\$*\" in install*) cat >/dev/null; echo \"flatpak \$*\" >>'$t/installs2' ;; esac" >"$t/bin/flatpak"
printf 'user\t%s\tcom.x.A\t2\nsystem\t%s\tcom.x.B\t3\n' "$t/a.flatpak" "$t/b.flatpak" >"$t/fetched/fetched"
out=$(fbu --install-fetched "$t/fetched" 2>&1) || fail "--install-fetched (two apps) failed: $out"
{ [[ $(grep -c -- '--reinstall --bundle' "$t/installs2") == 2 && $out == *"com.x.A: updated to 2"* && $out == *"com.x.B: updated to 3"* ]] &&
    grep -q -- "--system -y --noninteractive --reinstall --bundle $t/b.flatpak" "$t/installs2"; } ||
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
[[ $out == *"o/app: installed v1.1"* ]] && grep -q -- "--user -y --noninteractive --reinstall --bundle " "$t/installs3" &&
    grep -qx $'user\tcom.x.New\to/app' "$AGROS_FLATPAK_BUNDLES" ||
    fail "--install o/app: not installed, or its repo not written down: $out / $(cat "$AGROS_FLATPAK_BUNDLES" 2>/dev/null)"
rm -f "$AGROS_FLATPAK_BUNDLES"
meta com.x.App O/App.git; printf 'com.x.App\tapp-origin\tuser\n' >>"$t/list"
out=$(fbu --install o/app 2>&1) || true
[[ $out == "o/app: already installed" ]] || fail "--install o/app didn't find it installed: $out"
out=$(fbu --install o/app.git 2>&1) || true
[[ $out == "o/app.git: already installed" ]] || fail "--install o/app.git didn't find it installed: $out"
echo "ok flatpak-bundle-update"
