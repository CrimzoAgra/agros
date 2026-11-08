#!/usr/bin/env bash
# flatpak-bundle-update's version check: a release over the pre-release of the same number is newer, the same or an
# older one isn't
set -euo pipefail
. "$(dirname "$0")/lib.sh"
source <(sed -n '/^newer() {/,/^}/p' "$here/.local/bin/flatpak-bundle-update")
newer 0.1.34 0.1.33 || fail "0.1.34 not newer than 0.1.33"
newer 0.1.33 0.1.33-alpha || fail "0.1.33 not newer than 0.1.33-alpha"
newer 0.1.33-beta 0.1.33-alpha || fail "0.1.33-beta not newer than 0.1.33-alpha"
newer 0.1.34-alpha 0.1.33 || fail "0.1.34-alpha not newer than 0.1.33"
! newer 0.1.33 0.1.33 || fail "the same version counted as newer"
! newer 0.1.33-alpha 0.1.33 || fail "a pre-release counted as newer than its release"
! newer 0.1.9 0.1.10 || fail "0.1.9 counted as newer than 0.1.10"
# A release with no Linux .flatpak (yet: its files still uploading, or none for Linux) isn't announced as an update
# that then fails to install (flatpak and curl stubbed: a bundle on 1.0, its repo's latest release 1.1, Windows only)
mkdir -p "$t/bin" "$t/app/files/share/metainfo"
echo '<url>https://github.com/o/app</url>' >"$t/app/files/share/metainfo/a.xml"
cat >"$t/bin/flatpak" <<F
#!/bin/bash
case "\$*" in
    list*) printf 'com.x.App\tapp-origin\tuser\n' ;;
    *--show-location*) echo "$t/app" ;;
    info*) echo '  Version: 1.0' ;;
esac
F
printf '#!/bin/sh\ncat %s/release\n' "$t" >"$t/bin/curl"
chmod +x "$t/bin/flatpak" "$t/bin/curl"
release() { echo '{"tag_name": "v1.1", "assets": [{"name": "'"$1"'", "browser_download_url": "https://x/'"$1"'"}]}' >"$t/release"; }
release App-x64.exe
out=$(PATH=$t/bin:$PATH "$here/.local/bin/flatpak-bundle-update" --check) || true
[[ $out == *"no Linux .flatpak"* && $out != *"update available"* ]] || fail "a release without a .flatpak announced as an update: $out"
# (the same release with one: announced)
release App-x86_64.flatpak
out=$(PATH=$t/bin:$PATH "$here/.local/bin/flatpak-bundle-update" --check) || true
[[ $out == *"update available (1.0 -> 1.1)"* ]] || fail "a release with a .flatpak not announced: $out"
# Its repo from the app's own metainfo, by its home page, not the first github.com link in it (a library's)
printf '%s\n' '<a href="https://github.com/lib/other">lib</a>' '<url type="homepage">https://github.com/o/app</url>' \
    >"$t/app/files/share/metainfo/com.x.App.metainfo.xml"
printf '#!/bin/sh\ncase "$*" in *repos/o/app/*) cat %s/release ;; *) exit 22 ;; esac\n' "$t" >"$t/bin/curl"
out=$(PATH=$t/bin:$PATH "$here/.local/bin/flatpak-bundle-update" --check) || true
[[ $out == *"update available (1.0 -> 1.1)"* ]] || fail "the repo taken from another link than the app's home page: $out"
# The boot's update's two steps: --fetch downloads an update's file into a folder (nothing installed: it holds nothing),
# --install-fetched then reinstalls from it (the boot's update holds sleep and power off as root around that alone)
cat >"$t/bin/flatpak" <<F
#!/bin/bash
case "\$*" in
    list*) printf 'com.x.App\tapp-origin\tuser\n' ;;
    *--show-location*) echo "$t/app" ;;
    info*) echo '  Version: 1.0' ;;
    install*) echo "flatpak \$*" >>"$t/installs" ;;
esac
F
cat >"$t/bin/curl" <<C
#!/bin/sh
prev=
for a; do [ "\$prev" = -o ] && { echo bundle >"\$a"; exit 0; }; prev=\$a; done
cat "$t/release"
C
chmod +x "$t/bin/flatpak" "$t/bin/curl"
release App-x86_64.flatpak
mkdir -p "$t/fetched"
out=$(PATH=$t/bin:$PATH "$here/.local/bin/flatpak-bundle-update" --fetch "$t/fetched" 2>&1) || fail "--fetch failed: $out"
[[ ! -e $t/installs && $(cut -f1,3,4 "$t/fetched/fetched") == $'user\tcom.x.App\t1.1' && $(cat "$(cut -f2 "$t/fetched/fetched")") == bundle ]] ||
    fail "--fetch didn't only download the update: $out / $(cat "$t/fetched/fetched" 2>/dev/null) / $(cat "$t/installs" 2>/dev/null)"
out=$(PATH=$t/bin:$PATH "$here/.local/bin/flatpak-bundle-update" --install-fetched "$t/fetched" 2>&1) || fail "--install-fetched failed: $out"
{ grep -qx "flatpak install --user -y --noninteractive --reinstall --bundle $t/fetched/com.x.App/App-x86_64.flatpak" "$t/installs" &&
    [[ $out == *"com.x.App: updated to 1.1"* ]]; } || fail "--install-fetched didn't reinstall from the file: $out / $(cat "$t/installs")"
# Two apps fetched: both reinstalled, flatpak install (which may read its stdin) not eating the list's next line
printf '%s\n' '#!/bin/bash' "case \"\$*\" in install*) cat >/dev/null; echo \"flatpak \$*\" >>'$t/installs2' ;; esac" >"$t/bin/flatpak"
printf 'user\t%s\tcom.x.A\t2\nsystem\t%s\tcom.x.B\t3\n' "$t/a.flatpak" "$t/b.flatpak" >"$t/fetched/fetched"
out=$(PATH=$t/bin:$PATH "$here/.local/bin/flatpak-bundle-update" --install-fetched "$t/fetched" 2>&1) || fail "--install-fetched (two apps) failed: $out"
{ [[ $(grep -c -- '--reinstall --bundle' "$t/installs2") == 2 && $out == *"com.x.A: updated to 2"* && $out == *"com.x.B: updated to 3"* ]] &&
    grep -q -- "--system -y --noninteractive --reinstall --bundle $t/b.flatpak" "$t/installs2"; } ||
    fail "--install-fetched didn't reinstall both apps: $out / $(cat "$t/installs2" 2>/dev/null)"
echo "ok flatpak-bundle-update"
