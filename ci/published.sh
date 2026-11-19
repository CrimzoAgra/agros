# shellcheck shell=bash
# Sourced by build-repo.sh: the published repo's packages kept in place of this run's. A package that didn't build held
# back, the published one kept (hold); one whose rebuild would only be thrown away not built (reused); this run's new
# AUR builds swapped for the published ones (hold_new, --hold-new); the AUR packages CI holds unbuilt (keep_held). Uses
# its $out, $work, $keyring, $AGROS_PUBLISHED, asb and the held array (each "<name>: <why>"); sets $stamp,
# build-repo.sh's keep_published's too
# shellcheck disable=SC2154  # ($out, $work, $keyring, asb: build-repo.sh's)
# verify_sig <sig> <file>: a good signature by AgrOS's key, checked against $keyring (ci/agros.asc's key) alone, with
# gpgv: no other key, the builder's keyring neither (the AUR build scripts', it may hold anything)
verify_sig() { gpgv --keyring "$keyring" "$1" "$2" >/dev/null 2>&1; }
# (?t= on each fetch of the published repo: Pages' CDN keeps a copy up to 10 minutes after a deploy, an older
# database, or a 404 from before a file was published; the query asks for the current one, as mirror.sh's fetch)
stamp=$(date +%s)
hold() { held+=("$1: $2"); echo "!! $1: $2: the published one kept"; carry_over "$1" || exit 1; }
# The published database, read once; field <desc> <NAME>: a field of a package's entry in it
pubdb=$work/pubdb
field() { awk -v f="%$2%" '$0 == f { on = 1; next } /^%/ { on = 0 } on && NF' "$1"; }
pub_db() {
    [[ -d $pubdb ]] && return 0
    [[ -n ${AGROS_PUBLISHED:-} ]] || { echo "!! no published repo to keep packages from"; return 1; }
    curl -fsSL --retry 8 --retry-delay 15 --max-time 120 -o "$work/pub.db" "$AGROS_PUBLISHED/agros.db?t=$stamp" &&
        curl -fsSL --retry 8 --retry-delay 15 --max-time 60 -o "$work/pub.db.sig" "$AGROS_PUBLISHED/agros.db.sig?t=$stamp" &&
        verify_sig "$work/pub.db.sig" "$work/pub.db" &&
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
# carry_over <name> [alone]: the published package into the repo here, unless one is built; then each of its
# dependencies this repo publishes (the official ones pacman finds in Arch's), but with "alone" (one kept before the
# builds: those it needs are built or kept themselves, and one carried over then would sit beside its new build)
carry_over() {
    local desc f dep
    out_has "$1" && return 0
    pub_db && desc=$(pub_desc "$1") || { echo "!! $1: none published to keep"; return 1; }
    f=$(field "$desc" FILENAME)
    curl -fsSL --retry 8 --retry-delay 15 --max-time 600 -o "$out/$f" "$AGROS_PUBLISHED/$f?t=$stamp" &&
        curl -fsSL --retry 8 --retry-delay 15 --max-time 60 -o "$out/$f.sig" "$AGROS_PUBLISHED/$f.sig?t=$stamp" &&
        verify_sig "$out/$f.sig" "$out/$f" ||
        { echo "!! $f: the published copy couldn't be read or verified"; rm -f "$out/$f" "$out/$f.sig"; return 1; }
    chown builder: "$out/$f" "$out/$f.sig"
    echo "-- $f: the published one kept"
    [[ ${2:-} != alone ]] || return 0
    for dep in $(field "$desc" DEPENDS | sed 's/[<>=].*//'); do
        if pub_desc "$dep" >/dev/null; then carry_over "$dep" || return 1; fi
    done
}

# reused <dir>: the PKGBUILD in <dir> not built, the published package kept instead, when its rebuild would only be
# thrown away: the same name and version (its sources fetched, pkgver() run), the same PKGBUILD (the checksum makepkg
# keeps in .BUILDINFO: AgrOS's patches and swaps edit it), and what built_against (build-repo.sh) publishes a rebuild
# for unchanged: every library its programs need still in the repos (a new Boost's soname: built), the same Qt, the same
# Python. Anything else or unclear: 1, built as before (built_against then checks that build). Skips the long builds of
# a run that changes none of them
reused() {
    local info name ver desc f bi dep='' log x s cur pub
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
    bi=$(bsdtar -xOf "$f" .BUILDINFO 2>/dev/null)
    grep -qxF "pkgbuild_sha256sum = $(sha256sum <"$1/PKGBUILD" | cut -d' ' -f1)" <<<"$bi" || dep=PKGBUILD
    # (the libraries: each one it needs, but its own, found in the repos' file lists, this repo's too: synced each time,
    # it grows as the build goes)
    x=$(mktemp -d) && bsdtar -xf "$f" -C "$x" 2>/dev/null
    pacman -Fy >/dev/null 2>&1
    for s in $(find "$x" -type f \( -name '*.so*' -o -perm -u+x \) -print0 2>/dev/null | xargs -0r readelf -d 2>/dev/null |
        sed -n 's/.*(NEEDED).*\[\(.*\)\]/\1/p' | sort -u); do
        [[ -z $dep ]] || break
        [[ -n $(find "$x" -name "$s" -print -quit) ]] && continue
        [[ -n $(pacman -Fq "$s" 2>/dev/null) ]] || dep="the library $s (gone)"
    done
    # (Qt's and Python's versions without Arch's rebuild number, as built_against: x.y for Python)
    if [[ -z $dep ]] && find "$x" -type f -print0 | xargs -0r readelf -d 2>/dev/null | grep 'NEEDED.*\[libQt6' >/dev/null; then
        pub=$(sed -n 's/^installed = qt6-base-\(.*\)-[^-]*-[^-]*$/\1/p' <<<"$bi")
        cur=$(pacman -Sp --print-format '%v' qt6-base 2>/dev/null | tail -n1); cur=${cur%-*}
        [[ $pub == "$cur" ]] || dep="Qt ($pub, now ${cur:-gone})"
    fi
    pub=$(find "$x/usr/lib" -maxdepth 1 -name 'python3.*' -printf '%f\n' 2>/dev/null | head -n1)
    if [[ -z $dep && -n $pub ]]; then
        cur=$(pacman -Sp --print-format '%v' python 2>/dev/null | tail -n1 | cut -d. -f1,2)
        [[ $pub == "python$cur" ]] || dep="Python ($pub, now python${cur:-gone})"
    fi
    rm -rf "$x"
    if [[ -n $dep ]]; then
        echo "-- $name $ver: built ($dep changed since the published one)"
        rm -f "$f" "$f.sig"
        return 1
    fi
    echo "-- ${f##*/}: unchanged, the published one kept (not built)"
}

# hold_new <why>: each package here neither AgrOS's own nor the published file swapped for the published one (one never
# published: left out), said in held. AgrOS's own too when AGROS_HOLD_OWN names it (CI: agros-hyprbars, built for
# Arch's Hyprland, while the tests hold that Hyprland back: the published one is built for the approved one, which the
# machines and the ISO stay on, and the plugin only starts on the Hyprland it was built for)
hold_new() {
    local pubfiles f n names=()
    pub_db || exit 1
    pubfiles=$(for f in "$pubdb"/*/desc; do field "$f" FILENAME; done)
    for f in "$out"/*.pkg.tar*; do
        [[ $f == *.sig ]] && continue
        grep -qxF -- "${f##*/}" <<<"$pubfiles" && continue
        n=$(bsdtar -xOf "$f" .PKGINFO | sed -n 's/^pkgname = //p')
        [[ ( ${f##*/} == agros-* || $n == agros-* ) && " ${AGROS_HOLD_OWN:-} " != *" $n "* ]] && continue
        names+=("$n")
        rm -f "$f" "$f.sig"
    done
    for n in "${names[@]}"; do
        held+=("$n: $1")
        carry_over "$n" || echo "!! $n: new, none published: left out"
    done
}

# The AUR packages CI holds without building them (AGROS_AUR_HELD, ci/aur-maintainers.sh's, "<name> <base> <why>"
# each: their AUR maintainers changed days ago, or the AUR no longer has them). aur_fence reads them (aur_held, by
# name) and fences their build files off: the builder's git (paru's) told to fetch each base's from nowhere, so a build
# that would still want one (a dependency it didn't find installed) fails, and is held itself, rather than run the new
# maintainers' files. Not said in $AGROS_HELD (CI's held issue, which GitHub notifies of): nothing went wrong, and the
# weekly status says what's held, until when
declare -A aur_held=()
aur_fence() {
    local n b why
    while read -r n b why; do
        [[ -n $why ]] || continue
        aur_held[$n]=$why
        asb git config --global "url.file:///nonexistent/agros-held/$b.git.insteadOf" "https://aur.archlinux.org/$b.git"
    done <<<"${AGROS_AUR_HELD:-}"
}
# keep_held <name>: one aur_held has kept as published, alone (carry_over), and installed here as a dependency, no
# dependency checks (what needs it builds against it: paru and makepkg find it installed, not on the AUR); none
# published to keep: the build fails, as hold's. 1: not held, build it
keep_held() {
    local f
    [[ -n ${aur_held[$1]:-} ]] || return 1
    echo "-- $1: ${aur_held[$1]}"
    carry_over "$1" alone || exit 1
    f=$(field "$(pub_desc "$1")" FILENAME)
    { asb repo-add -q "$out/agros.db.tar.gz" "$out/$f" && pacman -Sy --noconfirm >/dev/null &&
        pacman -Sdd --needed --noconfirm --asdeps "$1" >/dev/null; } ||
        echo "!! $1: kept, but not installed here: what needs it may not build"
}
