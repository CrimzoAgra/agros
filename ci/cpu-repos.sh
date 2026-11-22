#!/usr/bin/env bash
# cpu-repos.sh <level>...: agros-desktop resolved as on an AgrOS machine of each CachyOS CPU level (CI's sign job,
# after its install check, which has [cachyos] alone). On a CPU that has the level, the installer (Calamares'
# detect-architecture) puts CachyOS's optimised repos above [cachyos] and Arch's: v3 ([cachyos-v3], [cachyos-core-v3],
# [cachyos-extra-v3]) or znver4 (the same with -znver4, x86_64_v4 packages). Each level's pacman.conf is the system's
# with those repos before [cachyos] and their architecture allowed, its databases in a folder of their own (the
# system's untouched); no CPU of that level needed, nothing installed. agros-desktop not resolving there fails this,
# said in plain lines: its caller decides whether that's an error (CI's sign job: a warning).
# A library those repos build at another soname than the repo below them still resolves, and breaks at run time
# (cachyos-extra-v3's old libplacebo once Arch's ffmpeg needed libplacebo.so=387, November 2026: mpv broke on v3
# machines): said as a warning (and in the run's summary), not a failure, as it isn't AgrOS's to fix
# Each of these, a level not resolving, its repos not read, a library at another soname, also in a record kept across
# runs, AGROS_CPU_STATE (CI: agros-cpu-repos, published beside the repo, for the weekly status): "# checked <day>",
# then "<since><tab><what><tab><said>" each, <since> the day it was first seen, kept from AGROS_CPU_BEFORE (the record as
# published, one with the same <what>: "v3 unresolved", "v3 skew libplacebo"...). CachyOS's repos lag Arch's for a
# day or two, routinely, so the status says one only once it has lasted 3 days; the record lets it tell
set -uo pipefail
conf=${PACMAN_CONF:-/etc/pacman.conf} sync=${PACMAN_SYNC:-/var/lib/pacman/sync}
mirror=${CACHYOS_MIRROR:-https://mirror.cachyos.org/repo}
(($#)) || { echo "usage: cpu-repos.sh <v3|znver4>..."; exit 2; }
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
failed=0
found=() unread=()
# seen <what> <said>: one for the record
seen() {
    local s=${2//$'\t'/ }
    found+=("$1"$'\t'"${s//$'\n'/ }")
}
# sonames <db>: "<package> <library>.so=<version>" for each library each package in <db> provides
sonames() {
    bsdtar -xOf "$1" '*/desc' 2>/dev/null |
        awk '/^%/ { s = $0; next } s == "%NAME%" && NF { n = $0 } s == "%PROVIDES%" && /\.so=/ { print n, $0 }'
}
for level in "$@"; do
    case $level in
        v3) dir=x86_64_v3 arches="x86_64 x86_64_v3" ;;
        znver4) dir=x86_64_v4 arches="x86_64 x86_64_v3 x86_64_v4" ;;
        *) echo "!! no such CPU level: $level"; exit 2 ;;
    esac
    repos=("cachyos-$level" "cachyos-core-$level" "cachyos-extra-$level")
    c=$tmp/$level.conf db=$tmp/$level
    mkdir -p "$db"
    # (x86_64 first: it's pacman's $arch, Arch's and [agros]'s Server lines)
    awk -v arches="$arches" -v repos="${repos[*]}" -v server="$mirror/$dir/\$repo" '
        /^[[:space:]]*Architecture[[:space:]]*=/ { next }
        $0 == "[cachyos]" && !done {
            n = split(repos, r, " ")
            for (i = 1; i <= n; i++) printf "[%s]\nServer = %s\n\n", r[i], server
            done = 1
        }
        { print }
        $0 == "[options]" { print "Architecture = " arches }' "$conf" >"$c"
    grep -qx "\[${repos[0]}\]" "$c" || {
        echo "!! $conf has no [cachyos] to put the $level repos above"
        seen "$level noconf" "$conf has no [cachyos] to put CachyOS's $level repos above"
        failed=1
        continue
    }
    if ! out=$(pacman --config "$c" --dbpath "$db" -Sy 2>&1); then
        echo "!! CachyOS's $level repos couldn't be read: $(tail -n3 <<<"$out")"
        seen "$level unreadable" "CachyOS's $level repos couldn't be read: $(tail -n1 <<<"$out")"
        unread+=("$level")
        failed=1
        continue
    fi
    if ! plan=$(pacman --config "$c" --dbpath "$db" -Sp --print-format '%r %n' agros-desktop 2>&1); then
        echo "!! agros-desktop doesn't resolve on a $level machine (${repos[*]} above [cachyos]):"
        echo "$plan"
        seen "$level unresolved" "agros-desktop doesn't resolve with CachyOS's $level repos above [cachyos] (their lag behind Arch's: $(grep -E 'cannot resolve|error:' <<<"$plan" | head -n2 | paste -sd';' | sed 's/;/; /g'))"
        failed=1
        continue
    fi
    mine=$(awk -v l="$level" '$1 ~ "^cachyos(-core|-extra)?-" l "$" { print $2 }' <<<"$plan")
    echo "-- $level: agros-desktop resolves ($(wc -l <<<"$plan") packages, $(grep -c . <<<"$mine") from CachyOS's $level repos)"
    [[ -n $mine ]] || continue
    # The libraries each of those provides, against the same package's in the first repo below that has it ([cachyos],
    # then Arch's): what was built against the one below needs its soname
    skew=$({
        for r in "${repos[@]}"; do sonames "$db/sync/$r.db" | sed 's/^/0 /'; done
        i=0
        for r in cachyos core extra multilib; do
            i=$((i + 1))
            if [[ -e $sync/$r.db ]]; then sonames "$sync/$r.db" | sed "s/^/$i /"; fi
        done
    } | awk -v mine="${mine//$'\n'/ }" '
        BEGIN { n = split(mine, m, " "); for (i = 1; i <= n; i++) want[m[i]] = 1 }
        !($2 in want) { next }
        $1 == 0 { up[$2] = up[$2] " " $3; next }
        !($2 in rank) { rank[$2] = $1 }
        rank[$2] == $1 { below[$2] = below[$2] " " $3 }
        END {
            for (p in up) {
                if (!(p in below)) continue
                d = 0
                n = split(up[p], a, " "); for (i = 1; i <= n; i++) if (index(below[p] " ", " " a[i] " ") == 0) d = 1
                n = split(below[p], a, " "); for (i = 1; i <= n; i++) if (index(up[p] " ", " " a[i] " ") == 0) d = 1
                if (d) print p ":" up[p] " here, the repo below:" below[p]
            }
        }' | sort)
    while IFS= read -r s; do
        [[ -n $s ]] || continue
        echo "::warning::$level machines: $s (what links the other soname breaks)"
        seen "$level skew ${s%%:*}" "$level machines: $s (what links the other soname breaks)"
        if [[ -n ${GITHUB_STEP_SUMMARY:-} ]]; then
            echo "- CachyOS's $level repos, a library at another soname: $s" >>"$GITHUB_STEP_SUMMARY"
        fi
    done <<<"$skew"
done
# The record: each one found, since the day the record before first had it (AGROS_NOW: another day than today)
if [[ -n ${AGROS_CPU_STATE:-} ]]; then
    today=$(date -u -d "${AGROS_NOW:-now}" +%F)
    {
        echo "# checked $today"
        for f in "${found[@]}"; do
            since=$(awk -F'\t' -v w="${f%%$'\t'*}" '$2 == w { print $1; exit }' "${AGROS_CPU_BEFORE:-/dev/null}" 2>/dev/null)
            [[ $since =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || since=$today
            printf '%s\t%s\n' "$since" "$f"
        done
        # (a level whose repos couldn't be read this time: what the record before had of it, kept as it was. Dropped,
        # one of a hiccup's day started again from today, and the status said a long-standing one 3 days late)
        for l in "${unread[@]}"; do
            awk -F'\t' -v l="$l " 'index($2, l) == 1 && $2 != l "unreadable"' "${AGROS_CPU_BEFORE:-/dev/null}" 2>/dev/null
        done
    } >"$AGROS_CPU_STATE"
fi
exit "$failed"
