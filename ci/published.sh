# shellcheck shell=bash
# Sourced by build-repo.sh: a package that didn't build held back, the published one kept. Uses its $out, $work, $key,
# $AGROS_PUBLISHED, asb and the held array (each "<name>: <why>")
# shellcheck disable=SC2154  # ($out, $work, $key, asb: build-repo.sh's)
hold() { held+=("$1: $2"); echo "!! $1: $2: the published one kept"; carry_over "$1" || exit 1; }
# The published database, read once; field <desc> <NAME>: a field of a package's entry in it
pubdb=$work/pubdb
field() { awk -v f="%$2%" '$0 == f { on = 1; next } /^%/ { on = 0 } on && NF' "$1"; }
pub_db() {
    [[ -d $pubdb ]] && return 0
    [[ -n ${AGROS_PUBLISHED:-} && -n $key ]] || { echo "!! no published repo to keep packages from"; return 1; }
    curl -fsSL --retry 3 --max-time 120 -o "$work/pub.db" "$AGROS_PUBLISHED/agros.db" &&
        curl -fsSL --retry 3 --max-time 60 -o "$work/pub.db.sig" "$AGROS_PUBLISHED/agros.db.sig" &&
        asb gpg --batch --verify "$work/pub.db.sig" "$work/pub.db" 2>/dev/null &&
        mkdir -p "$pubdb" && bsdtar -xf "$work/pub.db" -C "$pubdb" ||
        { echo "!! the published database couldn't be read or verified"; rm -rf "$pubdb"; return 1; }
}
# pub_desc <name>: the published package of that name, or that provides it
pub_desc() {
    local d
    for d in "$pubdb"/*/desc; do
        # (grep reads it all, not -q: -q stopped at the name, what it provides then hit a closed pipe, and pipefail
        # (build-repo.sh's) took the found package for none: one that provides anything was never found)
        { field "$d" NAME; field "$d" PROVIDES | sed 's/[<>=].*//'; } | grep -xF -- "$1" >/dev/null && { echo "$d"; return 0; }
    done
    return 1
}
# out_has <name>: a package here is or provides it
out_has() {
    local f
    for f in "$out"/*.pkg.tar*; do
        [[ $f == *.sig ]] && continue
        bsdtar -xOf "$f" .PKGINFO 2>/dev/null | sed -n 's/^\(pkgname\|provides\) = \([^<>=]*\).*/\2/p' | grep -xF -- "$1" >/dev/null &&
            return 0
    done
    return 1
}
# carry_over <name>: the published package into the repo here, unless one is built; then each of its dependencies
# this repo publishes (the official ones pacman finds in Arch's)
carry_over() {
    local desc f dep
    out_has "$1" && return 0
    pub_db && desc=$(pub_desc "$1") || { echo "!! $1: none published to keep"; return 1; }
    f=$(field "$desc" FILENAME)
    curl -fsSL --retry 3 --max-time 600 -o "$out/$f" "$AGROS_PUBLISHED/$f" &&
        curl -fsSL --retry 3 --max-time 60 -o "$out/$f.sig" "$AGROS_PUBLISHED/$f.sig" &&
        asb gpg --batch --verify "$out/$f.sig" "$out/$f" 2>/dev/null ||
        { echo "!! $f: the published copy couldn't be read or verified"; rm -f "$out/$f" "$out/$f.sig"; return 1; }
    chown builder: "$out/$f" "$out/$f.sig"
    echo "-- $f: the published one kept"
    for dep in $(field "$desc" DEPENDS | sed 's/[<>=].*//'); do
        if pub_desc "$dep" >/dev/null; then carry_over "$dep" || return 1; fi
    done
}

# reused <dir>: the PKGBUILD in <dir> not built, the published package kept instead, when nothing it's built from
# changed: the same name and version (its sources fetched, pkgver() run), the same PKGBUILD (the checksum makepkg keeps
# in .BUILDINFO: AgrOS's patches and swaps edit it) and every package it depends on or builds with still at the version
# it was built with (a new Boost or Qt: built). Anything else or unclear: 1, built as before (built_against then checks
# that build). Skips the long builds of a run that changes none of them
reused() {
    local info name ver desc f bi d dep='' cur log
    # (each way it gives up said, with why: one that never said built every time, unseen)
    log=$(cd "$1" && asb makepkg -od --noconfirm 2>&1) ||
        { echo "-- ${1##*/}: built (its sources not fetched to compare: $(tail -n3 <<<"$log" | paste -sd' '))"; return 1; }
    info=$(cd "$1" && asb makepkg --printsrcinfo 2>&1) ||
        { echo "-- ${1##*/}: built (no .SRCINFO to compare: $(tail -n3 <<<"$info" | paste -sd' '))"; return 1; }
    name=$(sed -n 's/^pkgname = //p' <<<"$info" | head -n1)
    ver=$(awk -F' = ' '/^\tepoch = /{e=$2":"} /^\tpkgver = /{v=$2} /^\tpkgrel = /{r=$2} END{print e v "-" r}' <<<"$info")
    out_has "$name" && return 0  # (built here already, as another's dependency)
    pub_db >/dev/null 2>&1 && desc=$(pub_desc "$name") || { echo "-- $name $ver: built (none published)"; return 1; }
    [[ $(field "$desc" NAME) == "$name" && $(field "$desc" VERSION) == "$ver" ]] ||
        { echo "-- $name $ver: built (published: $(field "$desc" NAME) $(field "$desc" VERSION))"; return 1; }
    log=$(carry_over "$name" 2>&1) || { echo "-- $name $ver: built (the published one not fetched: $log)"; return 1; }
    f=$out/$(field "$desc" FILENAME)
    bi=$(bsdtar -xOf "$f" .BUILDINFO 2>/dev/null | sed -n -e 's/^installed = \(.*\)-[^-]*$/\1/p' -e 's/^pkgbuild_sha256sum = /sha /p')
    grep -qxF "sha $(sha256sum <"$1/PKGBUILD" | cut -d' ' -f1)" <<<"$bi" || dep=PKGBUILD
    for d in $(bsdtar -xOf "$f" .PKGINFO 2>/dev/null | sed -n 's/^\(depend\|makedepend\) = \([^<>=]*\).*/\2/p'); do
        [[ -z $dep ]] || break
        cur=$(pacman -Sp --print-format '%n-%v' "$d" 2>/dev/null | tail -n1)
        [[ -n $cur ]] && grep -qxF "$cur" <<<"$bi" || dep="$d (now ${cur:-gone})"
    done
    if [[ -n $dep ]]; then
        echo "-- $name $ver: built ($dep changed since the published one)"
        rm -f "$f" "$f.sig"
        return 1
    fi
    echo "-- ${f##*/}: unchanged, the published one kept (not built)"
}

# hold_new <why>: each package here neither AgrOS's own nor the published file swapped for the published one (one never
# published: left out), said in held
hold_new() {
    local pubfiles f n names=()
    pub_db || exit 1
    pubfiles=$(for f in "$pubdb"/*/desc; do field "$f" FILENAME; done)
    for f in "$out"/*.pkg.tar*; do
        [[ $f == *.sig || ${f##*/} == agros-* ]] && continue
        grep -qxF -- "${f##*/}" <<<"$pubfiles" && continue
        names+=("$(bsdtar -xOf "$f" .PKGINFO | sed -n 's/^pkgname = //p')")
        rm -f "$f" "$f.sig"
    done
    for n in "${names[@]}"; do
        held+=("$n: $1")
        carry_over "$n" || echo "!! $n: new, none published: left out"
    done
}
