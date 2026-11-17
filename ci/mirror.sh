#!/usr/bin/env bash
# mirror.sh: the [agros] repo as GitHub Pages publishes it, copied to its second server, Cloudflare R2
# (.github/workflows/mirror.yml), so a Pages outage doesn't stop every AgrOS machine's updates
#   mirror.sh fetch <site> <dir> <key.asc>
#       The published repo into <dir> (empty or new): agros.db with its .sig, agros.files and the .tar.gz copies of
#       both (with theirs) where published, every package the database lists with its .sig, agros-approved and
#       agros-arch-ok (with theirs, where published). Every signature checked against <key.asc> alone (gpgv), the
#       database's required: nothing is mirrored that AgrOS didn't sign. Writes the upload's order beside <dir>:
#       <dir>.pkgs (the packages), <dir>.meta (the rest), <dir>.db (the database). Fails, said, on anything missing
#   mirror.sh upload <dir> <remote>
#       To rclone's <remote> (r2:<bucket>/repo/x86_64): the packages first, then the lists beside them, the database
#       last of all, and only then what the repo no longer has removed (rclone sync), so a mirror mid-update never
#       lists a package it doesn't have. Only the current set is kept (R2's free 10 GB: the repo is ~190 MB)
set -uo pipefail
usage="usage: mirror.sh fetch <site> <dir> <key.asc> | mirror.sh upload <dir> <remote>"

fetch() {
    local site=${1:?$usage} dir=${2:?$usage} key=${3:?$usage} f n code
    mkdir -p "$dir" || return 1
    # (a global: removed at the script's exit)
    tmp=$(mktemp -d) || return 1
    trap 'rm -rf "$tmp"' EXIT
    # get <file> [optional]: 0 fetched; 1 not published (404), when optional; 2 failed, said
    # (?t=: Pages' CDN keeps a copy up to 10 minutes after a deploy, and an older database with its packages still
    # cached mirrored the last publish, said as done; the query asks for the current one, as agros-iso's ISO build does)
    local stamp
    stamp=$(date +%s)
    get() {
        code=$(curl -sS --retry 8 --retry-delay 15 --connect-timeout 20 -m 600 -o "$dir/$1" -w '%{http_code}' "$site/$1?t=$stamp") || code=000
        [[ $code == 200 ]] && return 0
        rm -f "$dir/$1"
        [[ $code == 404 && -n ${2:-} ]] && return 1
        echo "::error::$site/$1 couldn't be read (HTTP $code)"
        return 2
    }
    : >"$dir.pkgs"; : >"$dir.meta"; : >"$dir.db"
    get agros.db && get agros.db.sig || return 1
    printf '%s\n' agros.db agros.db.sig >>"$dir.db"
    for f in agros.db.tar.gz agros.files agros.files.tar.gz agros-approved agros-arch-ok; do
        get "$f" optional
        case $? in 1) continue ;; 2) return 1 ;; esac
        if [[ $f == agros.db.* ]]; then echo "$f" >>"$dir.db"; else echo "$f" >>"$dir.meta"; fi
        get "$f.sig" optional
        case $? in 0) if [[ $f == agros.db.* ]]; then echo "$f.sig" >>"$dir.db"; else echo "$f.sig" >>"$dir.meta"; fi ;; 2) return 1 ;; esac
    done
    # The packages the database lists (its entries' %FILENAME%), each with its signature (the database carries none)
    mkdir "$tmp/db" && bsdtar -xf "$dir/agros.db" -C "$tmp/db" || { echo "::error::agros.db can't be read"; return 1; }
    n=0
    while read -r f; do
        # (a bare file name: nothing written outside <dir>)
        [[ $f =~ ^[A-Za-z0-9@_+][A-Za-z0-9@._+:-]*$ ]] || { echo "::error::agros.db lists a file name that isn't one: $f"; return 1; }
        get "$f" && get "$f.sig" || return 1
        printf '%s\n' "$f" "$f.sig" >>"$dir.pkgs"
        n=$((n + 1))
    done < <(cat "$tmp"/db/*/desc 2>/dev/null | awk '/^%FILENAME%$/ { getline; print }')
    ((n)) || { echo "::error::agros.db lists no packages"; return 1; }
    # Every signature fetched checked: by <key.asc>'s key alone (a keyring of it, not gpg's own)
    gpg --batch --quiet --dearmor <"$key" >"$tmp/key.gpg" || { echo "::error::$key can't be read"; return 1; }
    while read -r f; do
        [[ $f == *.sig ]] || continue
        gpgv --keyring "$tmp/key.gpg" "$dir/$f" "$dir/${f%.sig}" >/dev/null 2>&1 ||
            { echo "::error::$f isn't a good signature by AgrOS's key: nothing mirrored"; return 1; }
    done < <(cat "$dir.db" "$dir.meta" "$dir.pkgs")
    echo "fetched: $n packages, $(wc -l <"$dir.meta") other files, the database"
}

upload() {
    local dir=${1:?$usage} remote=${2:?$usage} list
    # (never a sync of a folder without a database: it would empty the mirror)
    [[ -s $dir/agros.db && -s $dir.pkgs && -s $dir.db ]] || { echo "::error::$dir isn't a fetched repo: nothing uploaded"; return 1; }
    local opts=(--s3-no-check-bucket --retries 3 --checksum)
    for list in pkgs meta db; do
        [[ -s $dir.$list ]] || continue
        rclone copy "${opts[@]}" --files-from "$dir.$list" "$dir" "$remote" || return 1
    done
    rclone sync "${opts[@]}" "$dir" "$remote"
}

case ${1:-} in
    fetch) shift; fetch "$@" ;;
    upload) shift; upload "$@" ;;
    *) echo "$usage" >&2; exit 2 ;;
esac
