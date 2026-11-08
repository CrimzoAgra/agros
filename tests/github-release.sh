#!/usr/bin/env bash
# The GitHub release checks appimage-update and flatpak-bundle-update share (curl stubbed: a made-up release): the
# x86_64 file picked, its checksum found by exact name or not at all, a download that doesn't match refused
set -euo pipefail
. "$(dirname "$0")/lib.sh"
source "$here/.local/share/github-release/lib.sh"
mkdir -p "$t/srv" "$t/bin" "$t/dl"
# curl: -o <file> <url> copies the release's file from $t/srv (by its name in the URL)
printf '%s\n' '#!/bin/bash' 'prev=; for a; do [[ $prev == -o ]] && out=$a; prev=$a; done' 'cp "$SRV/${a##*/}" "$out"' >"$t/bin/curl"
chmod +x "$t/bin/curl"
export SRV=$t/srv PATH=$t/bin:$PATH
release() {  # release <asset name>...: its JSON
    printf '%s\n' "$@" | jq -R '{name: ., browser_download_url: ("https://x/" + .), size: 1}' | jq -s '{assets: .}'
}
echo app >"$t/srv/App-x86_64.AppImage"
sum=$(sha256sum "$t/srv/App-x86_64.AppImage" | cut -d' ' -f1)

r=$(release App-aarch64.AppImage App-x86_64.AppImage App.flatpak)
[[ $(asset_url "$r" appimage) == https://x/App-x86_64.AppImage ]] || fail "the x86_64 AppImage not picked: $(asset_url "$r" appimage)"
[[ -z $(asset_url "$r" flatpak) ]] || fail "a .flatpak not named for x86_64 picked"
[[ -z $(asset_url "$(release App-arm64.AppImage)" appimage) ]] || fail "an arm64-only release gave a file"

# No checksums in the release: nothing, and fine
want=$(checksum "$r" App-x86_64.AppImage "$t/dl") || fail "a release without checksums failed"
[[ -z $want ]] || fail "a release without checksums gave one: $want"
# A list covering it: by its exact name (not the .zsync named like it), also a "*name" binary-mode line
printf '%s  App-x86_64.AppImage.zsync\n%s *App-x86_64.AppImage\n' 0000 "$sum" >"$t/srv/SHA256SUMS"
r=$(release App-x86_64.AppImage SHA256SUMS)
[[ $(checksum "$r" App-x86_64.AppImage "$t/dl") == "$sum" ]] || fail "the checksum not found by its exact name"
# A list for another build only: refused, not installed unchecked
printf '%s  App-aarch64.AppImage\n' "$sum" >"$t/srv/SHA256SUMS"
if checksum "$r" App-x86_64.AppImage "$t/dl" 2>/dev/null; then fail "a checksum list without this file passed"; fi
# ...or only another build's own <file>.sha256
if checksum "$(release App-x86_64.AppImage App-aarch64.AppImage.sha256)" App-x86_64.AppImage "$t/dl" 2>/dev/null; then
    fail "another build's own checksum file passed"
fi
# Its own <file>.sha256, just the hash
echo "$sum" >"$t/srv/App-x86_64.AppImage.sha256"
r=$(release App-x86_64.AppImage App-x86_64.AppImage.sha256)
[[ $(checksum "$r" App-x86_64.AppImage "$t/dl") == "$sum" ]] || fail "a bare <file>.sha256 not read"

download https://x/App-x86_64.AppImage "$t/dl" "$sum" 2>/dev/null || fail "a matching download refused"
[[ -f $t/dl/App-x86_64.AppImage ]] || fail "the download isn't under its own name"
if download https://x/App-x86_64.AppImage "$t/dl" "${sum//?/0}" >/dev/null 2>&1; then fail "a download not matching its checksum passed"; fi
echo "ok github-release"
