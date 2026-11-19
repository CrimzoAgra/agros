#!/usr/bin/env bash
# ci/cpu-repos.sh: agros-desktop resolved with CachyOS's v3 and znver4 repos above [cachyos], as the installer sets an
# AgrOS machine of that CPU level up: each level's pacman.conf (the repos in order, their architecture, their server),
# its databases apart from the system's; not resolving, or the repos not read, fails; a library one of them provides
# at another soname than the first repo below with that package (cachyos-extra-v3's libplacebo, November 2026) said as
# a warning, not a failure; each in a record across runs, since the day first seen (AGROS_CPU_STATE). pacman is a
# stand-in (its databases made here, its plan $T/plan, "LEVEL" the level's)
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
mkdir -p "$t/bin" "$t/dbs" "$t/sync"
# mkdb <db> <name>=<provides,...>...: a sync database
mkdb() {
    local db=$1 d p n; shift
    d=$(mktemp -d "$t/db.XXXX")
    for p; do
        n=${p%%=*}
        mkdir "$d/$n-1-1"
        printf '%%FILENAME%%\n%s-1-1-x86_64.pkg.tar.zst\n\n%%NAME%%\n%s\n\n%%VERSION%%\n1-1\n\n%%PROVIDES%%\n%s\n\n' \
            "$n" "$n" "$(tr ',' '\n' <<<"${p#*=}")" >"$d/$n-1-1/desc"
    done
    (cd "$d" && bsdtar -czf "$db" -- *)
}
mkdb "$t/dbs/cachyos-extra-v3.db" 'libplacebo=libplacebo.so=351-64' 'unused=libunused.so=1-64'
mkdb "$t/dbs/cachyos-core-v3.db" 'zlib=libz.so=1-64'
mkdb "$t/dbs/cachyos-v3.db" 'mesa=libgbm.so=1-64'
mkdb "$t/sync/cachyos.db" 'mesa=libgbm.so=1-64'
mkdb "$t/sync/core.db" 'zlib=libz.so=1-64'
mkdb "$t/sync/extra.db" 'libplacebo=libplacebo.so=387-64' 'unused=libunused.so=2-64' 'mesa=libgbm.so=2-64'
cp -r "$t/sync" "$t/sync.before"
printf '%s\n' '[options]' 'Architecture = auto' 'SigLevel = Required DatabaseOptional' '' '[cachyos]' \
    'Server = https://mirror.cachyos.org/repo/$arch/$repo' '' '[core]' 'Include = /etc/pacman.d/mirrorlist' '' \
    '[extra]' 'Include = /etc/pacman.d/mirrorlist' '' '[agros]' 'Server = file:///out/x86_64' >"$t/pacman.conf"
# (the level from the config's first optimised repo; -Sy copies each of its repos' databases made here; -Sp prints the
# plan; $T/nosync, $T/noresolve: each fails)
cat >"$t/bin/pacman" <<'S'
#!/bin/bash
conf= db= op=
while (($#)); do
    case $1 in
        --config) conf=$2; shift ;;
        --dbpath) db=$2; shift ;;
        --print-format) shift ;;
        -*) op=$1 ;;
    esac
    shift
done
[[ -n $conf && -n $db ]] || { echo "the system's own config or databases"; exit 9; }
level=$(sed -n 's/^\[cachyos-\(v3\|znver4\)\]$/\1/p' "$conf")
cp "$conf" "$T/conf-$level"
case $op in
    -Sy)
        [[ ! -e $T/nosync ]] || { echo "error: failed retrieving file 'cachyos-v3.db'"; exit 1; }
        mkdir -p "$db/sync"
        for r in $(sed -n 's/^\[\(.*\)\]$/\1/p' "$conf"); do
            if [[ $r != options && -e $T/dbs/$r.db ]]; then cp "$T/dbs/$r.db" "$db/sync/"; fi
        done ;;
    -Sp)
        [[ ! -e $T/noresolve ]] || { echo "error: target not found: agros-foo"; exit 1; }
        sed "s/LEVEL/$level/" "$T/plan" ;;
esac
S
chmod +x "$t/bin/pacman"
printf '%s\n' 'cachyos-extra-LEVEL libplacebo' 'cachyos-core-LEVEL zlib' 'cachyos-LEVEL mesa' 'extra unused' 'agros agros-desktop' >"$t/plan"
go() {
    rm -f "$t"/conf-* "$t/summary"
    T=$t PATH=$t/bin:$PATH PACMAN_CONF=$t/pacman.conf PACMAN_SYNC=$t/sync GITHUB_STEP_SUMMARY=$t/summary \
        "$here/ci/cpu-repos.sh" "$@" 2>&1
}
out=$(go v3 znver4) || fail "resolving with the CPU levels' repos failed: $out"
# (the repos above [cachyos], in the installer's order, from their level's folder; its architecture allowed, x86_64 first)
[[ $(grep '^\[' "$t/conf-v3" | paste -sd' ') == "[options] [cachyos-v3] [cachyos-core-v3] [cachyos-extra-v3] [cachyos] [core] [extra] [agros]" ]] ||
    fail "v3's repos not above [cachyos]: $(grep '^\[' "$t/conf-v3" | paste -sd' ')"
[[ $(grep -c '^Architecture' "$t/conf-v3") == 1 ]] && grep -qx 'Architecture = x86_64 x86_64_v3' "$t/conf-v3" ||
    fail "v3's architecture: $(grep '^Architecture' "$t/conf-v3")"
[[ $(grep -c '^Server = https://mirror.cachyos.org/repo/x86_64_v3/\$repo$' "$t/conf-v3") == 3 ]] ||
    fail "v3's repos not from x86_64_v3: $(cat "$t/conf-v3")"
[[ $(grep '^\[' "$t/conf-znver4" | paste -sd' ') == "[options] [cachyos-znver4] [cachyos-core-znver4] [cachyos-extra-znver4] [cachyos] [core] [extra] [agros]" ]] &&
    grep -qx 'Architecture = x86_64 x86_64_v3 x86_64_v4' "$t/conf-znver4" &&
    [[ $(grep -c '^Server = https://mirror.cachyos.org/repo/x86_64_v4/\$repo$' "$t/conf-znver4") == 3 ]] ||
    fail "znver4's config: $(cat "$t/conf-znver4")"
diff -r "$t/sync" "$t/sync.before" >/dev/null || fail "the system's databases changed"
# (libplacebo at another soname than Arch's: said; zlib the same as core's, mesa as [cachyos]'s (the first below with
# it, not Arch's), unused not taken from v3: not said; znver4's repos empty here: nothing)
[[ $(grep -c '^::warning::' <<<"$out") == 1 ]] &&
    grep -qxF '::warning::v3 machines: libplacebo: libplacebo.so=351-64 here, the repo below: libplacebo.so=387-64 (what links the other soname breaks)' <<<"$out" ||
    fail "the soname skews said: $out"
grep -q 'libplacebo.so=351-64' "$t/summary" || fail "the skew not in the run's summary: $(cat "$t/summary" 2>/dev/null)"
grep -qx -- '-- v3: agros-desktop resolves (5 packages, 3 from CachyOS'"'"'s v3 repos)' <<<"$out" || fail "the resolution not said: $out"
# Not resolving, or the repos not read: a failure, said
touch "$t/noresolve"
out=$(go v3) && fail "agros-desktop not resolving passed"
grep -q "^!! agros-desktop doesn't resolve on a v3 machine" <<<"$out" && grep -q 'agros-foo' <<<"$out" || fail "not resolving not said: $out"
rm "$t/noresolve"; touch "$t/nosync"
out=$(go znver4) && fail "the repos not read passed"
grep -q "^!! CachyOS's znver4 repos couldn't be read" <<<"$out" || fail "the repos not read not said: $out"
rm "$t/nosync"
out=$(go v4) && fail "a level that doesn't exist passed"
# The record kept across runs (AGROS_CPU_STATE, for the weekly status): each one found with the day it was first seen,
# kept from the record before (AGROS_CPU_BEFORE) when it was there too, today's when new; one gone, gone; the day checked
skew=$'v3 machines: libplacebo: libplacebo.so=351-64 here, the repo below: libplacebo.so=387-64 (what links the other soname breaks)'
printf '# checked 2026-11-17\n2026-11-15\tv3 skew libplacebo\tsaid before\n2026-11-10\tv3 unresolved\tsaid before\n' >"$t/before"
rec() { AGROS_CPU_BEFORE=${BEFORE-$t/before} AGROS_CPU_STATE=$t/state AGROS_NOW=2026-11-18 go "$@" >/dev/null || true; cat "$t/state"; }
[[ $(rec v3 znver4) == "# checked 2026-11-18"$'\n'"2026-11-15"$'\t'"v3 skew libplacebo"$'\t'"$skew" ]] ||
    fail "the record not kept from the one before: $(cat -A "$t/state")"
[[ $(BEFORE=/nonexistent rec v3) == "# checked 2026-11-18"$'\n'"2026-11-18"$'\t'"v3 skew libplacebo"$'\t'"$skew" ]] ||
    fail "one new not since today: $(cat -A "$t/state")"
touch "$t/noresolve"
[[ $(rec v3) == "# checked 2026-11-18"$'\n'"2026-11-10"$'\t'"v3 unresolved"$'\t'"agros-desktop doesn't resolve with CachyOS's v3 repos above [cachyos] (their lag behind Arch's: error: target not found: agros-foo)" ]] ||
    fail "not resolving not in the record, since the day first seen: $(cat -A "$t/state")"
rm "$t/noresolve"
grep -q 'AGROS_CPU_BEFORE=/tmp/cpu-before AGROS_CPU_STATE=out/x86_64/agros-cpu-repos ci/cpu-repos.sh v3 znver4' "$here/.github/workflows/ci.yml" ||
    fail "CI's install check doesn't publish the record beside the repo, from the one before"
echo "ok ci-cpu-repos"
