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
        { field "$d" NAME; field "$d" PROVIDES | sed 's/[<>=].*//'; } | grep -qxF -- "$1" && { echo "$d"; return 0; }
    done
    return 1
}
# out_has <name>: a package here is or provides it
out_has() {
    local f
    for f in "$out"/*.pkg.tar*; do
        [[ $f == *.sig ]] && continue
        bsdtar -xOf "$f" .PKGINFO 2>/dev/null | sed -n 's/^\(pkgname\|provides\) = \([^<>=]*\).*/\2/p' | grep -qxF -- "$1" &&
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
