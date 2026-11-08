# shellcheck shell=bash
# GitHub releases: the latest one, its Linux x86_64 file, checked against its checksums. Sourced by appimage-update and
# flatpak-bundle-update (one copy of the checks both rely on)

# latest_release <owner/repo>: the latest release, as GitHub's JSON
latest_release() { curl -fsSL --connect-timeout 10 -m 60 "https://api.github.com/repos/${1%.git}/releases/latest"; }

# asset_url <release JSON> <extension>: its Linux x86_64 file of that kind (appimage, flatpak); nothing when it has none
asset_url() {
    jq -r --arg e "$2" '[.assets[].browser_download_url | select(test("(?i)(x86[_-]64|amd64|x64).*\\." + $e + "$"))][0] // empty' <<<"$1"
}

# checksum <release JSON> <file name> <dir>: the file's SHA-256 from the release, from its own <file>.sha256 or the list
# of every file's (SHA256SUMS, checksums.txt). Nothing when the release has no checksums; fails (not installed unchecked)
# when it has some but none for this file (only another build's, e.g. arm64's) or they can't be fetched
checksum() {
    local own list
    own=$(jq -r --arg n "$2" '[.assets[].browser_download_url | select(endswith("/" + $n + ".sha256") or endswith("/" + $n + ".sha256sum"))][0] // empty' <<<"$1")
    list=$(jq -r '[.assets[].browser_download_url | select(test("(?i)/[^/]*(sha256sums|checksums|sha256\\.txt)[^/]*$"))][0] // empty' <<<"$1")
    if [[ -z $own && -z $list ]]; then
        jq -e '[.assets[].name | select(test("(?i)sha256|checksum"))] | length == 0' <<<"$1" >/dev/null && return 0
        echo "$2: the release's checksums don't cover it, not installed" >&2
        return 1
    fi
    curl -fsSL --connect-timeout 10 -m 60 -o "$3/sums" "${own:-$list}" || { echo "$2: can't fetch its checksum, not installed" >&2; return 1; }
    # (by the file's exact name, not as a pattern; a <file>.sha256 may hold just the hash)
    awk -v n="$2" -v own="${own:+1}" '$2 == n || $2 == "*" n || (own && NF == 1) {print $1; exit}' "$3/sums" | grep . ||
        { echo "$2: not in the release's checksum list, not installed" >&2; return 1; }
}

# download <url> <dir> [SHA-256]: the file into <dir> under its own name, checked against the SHA-256 when given.
# A progress bar when someone's watching (setup.sh), quiet in the boot log
download() {
    local name=${1##*/}
    curl -fL --connect-timeout 10 --speed-limit 1000 --speed-time 60 "$([[ -t 2 ]] && echo --progress-bar || echo -sS)" -o "$2/$name" "$1" || return 1
    if [[ -n ${3:-} ]] && ! (cd "$2" && echo "$3  $name" | sha256sum -c --quiet); then
        echo "$name: checksum mismatch, not installed"
        return 1
    fi
}
