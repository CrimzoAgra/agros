#!/usr/bin/env bash
# The tests on what this run built, and when some fail, which side broke them (CI's test job, as root in its container,
# the tests run as the ci user). Each pass runs every test, not only those that failed before: a hold puts out what
# that pass had (the published AUR builds beside this commit's own packages, Hyprland approved after B), and a test
# that passed on this run's builds can fail on those (an overlay changed for the new Caelestia, run on the old one):
#   A. [agros] as this run built it ($1, a pacman Server line's URL), on today's CachyOS above Arch (its v3 repos, as
#      CI's build tools set up, as most machines have): all pass, result=ok. Then once more on Arch's own builds, ahead
#      of CachyOS's rebuilds of them (its v3 repos out): what fails there said as AHEAD lines (machines meet it once
#      CachyOS catches up: adapt before), nothing held; CachyOS's put back after (the gate approves what's installed)
#   B. the published [agros] ($2), the last good one: all pass, result=hold-agros (this run's new AUR builds broke them;
#      today's Arch, Hyprland too, passed). Which one: each new build of a package installed here tried alone over B's
#      (with the new builds it needs), only the tests that failed in A run again (twice when they fail: once is chance),
#      then all the tests with the others together. Found: hold=<"<name>: <why>" lines> (ci/published.sh's
#      AGROS_HOLD_ONLY), it and the new builds that need it held, the rest out. Not found (each passes alone, a test that
#      failed by chance, more than AGROS_TRIALS tries), or the others together failing: no hold= line, every new AUR
#      build held, as the report says
#   C. that, on Arch as of the last day the tests passed on it ($3, YYYY/MM/DD, its archive's snapshot; CachyOS's v3
#      repos out, as it keeps no dated snapshots): all pass, result=hold-upstream (an upstream update, Arch's or
#      CachyOS's rebuild of it, broke them: its Hyprland not approved, the new AUR builds held too)
#   Still failing: AgrOS's own code, result=fail (exit 1): nothing goes out
# A check against upstream's next release (its main branch) that doesn't fit isn't a failure: neither pass B nor C could
# undo it. The tests say it on their last line ("ok <test> (AHEAD: ...)", tests/lib.sh's ahead), and pass A's go in the
# report, "    AHEAD <test>: <what>" lines (ci/report.sh keeps its issue open for them), whatever the result
# Writes result=<...> to $GITHUB_OUTPUT (or stdout), and what failed in each pass to $AGROS_TEST_REPORT (markdown)
set -uo pipefail
built=${1:?usage: test-passes.sh <built repo URL> <published repo URL> [<last good Arch day>]} published=${2:?} day=${3:-}
report=${AGROS_TEST_REPORT:-/dev/null} out=${GITHUB_OUTPUT:-/dev/stdout}
here=$(cd "$(dirname "$0")/.." && pwd)
sync=${PACMAN_SYNC:-/var/lib/pacman/sync}
: >"$report"
keep=$(mktemp -d)
trap 'rm -rf "$keep"' EXIT
# agros_at <url>: [agros] read from there. (The last one's database signatures go: the built repo is unsigned until the
# sign job signs it, and the published one's .sig, left in pacman's sync folder, failed its new database)
conf=${PACMAN_CONF:-/etc/pacman.conf}
agros_at() {
    sed -i "/^\[agros\]$/,/^Server/ s|^Server = .*|Server = $1|" "$conf"
    rm -f "$sync"/agros.{db,files}.sig
}
# v3_off: CachyOS's v3 repos out of pacman.conf (CI's build tools put them above [cachyos]): Arch's own builds read
v3_off() { sed -i -e '/^\[cachyos-\(core-\|extra-\)\?v3\]$/,/^Include/d' -e 's/^Architecture = x86_64 x86_64_v3$/Architecture = auto/' "$conf"; }
# run_tests [<test>...]: those (none: every test), as the ci user: the names that failed, in $failed, their lines in
# $log, run.sh's status in $rc (run here, not in <(...): a background job starts with Ctrl+C ignored, no trap can undo
# that, and dotfiles-sync-edge tests one)
run_tests() {
    rc=0
    log=$(runuser -u ci -- env DOTS_BUILD_TESTS=1 "$here/tests/run.sh" "$@") || rc=$?
    printf '%s\n' "$log" >&2
    mapfile -t failed < <(sed -n 's/^FAIL \([^:]*\): .*/\1/p' <<<"$log")
}
# tests: every test, what failed in the report
tests() {
    run_tests
    grep '^FAIL ' <<<"$log" | sed 's/^/    /' >>"$report"
    # (run.sh failing with none named (runuser refused, run.sh cut off): the tests didn't run, not "all passed", which
    # approves Hyprland)
    ((rc == 0 || ${#failed[@]})) || { echo "    the tests didn't run (run.sh: exit $rc)" >>"$report"; result fail 1; }
}
# stopped <why>: a pass that couldn't be run (a download failed, an install refused), said in the report too: the issue
# read as AgrOS's own code failing, with nothing under it saying otherwise
stopped() { echo "$1"; echo "    $1: not known which side broke the tests" >>"$report"; result fail 1; }
# synced <why> <pacman option>...: a pass's packages synced and installed, tried again a minute later, three times (a
# server's hiccup: archive.archlinux.org's "Operation too slow" stopped pass C, a mirror caught mid-sync), then stopped.
# Each try within AGROS_SYNC_TIMEOUT seconds (a download that hangs, with pacman's own timeout off: its lock then left
# behind taken away, or the next try found the database locked)
synced() {
    local why=$1 i rc
    shift
    for i in 1 2 3; do
        rc=0
        timeout -k 10 "${AGROS_SYNC_TIMEOUT:-1200}" pacman "$@" >/dev/null || rc=$?
        ((rc)) || return 0
        ((rc != 124 && rc != 137)) || { echo "!! pacman $1 stopped at its time limit"; rm -f "${sync%/*}/db.lck"; }
        ((i == 3)) || sleep "${AGROS_RETRY_WAIT:-60}"
    done
    stopped "$why"
}
# descs <db>: each package in a sync database, "<name> <file>", "<name> > <what it needs>" and "<name> = <what it
# provides>" (versions left out)
descs() {
    bsdtar -xOf "$1" '*/desc' 2>/dev/null | awk '
        /^%[A-Z0-9]+%$/ { k = $0; next }
        !NF { next }
        k == "%FILENAME%" { f = $0 }
        k == "%NAME%" { n = $0; print n, f }
        k == "%DEPENDS%" || k == "%PROVIDES%" { sub(/[<>=].*/, ""); print n, (k == "%DEPENDS%" ? ">" : "="), $0 }'
}
declare -A file=() needs=() prov=()
new=()
# closure <name>: it and the new builds it needs (by name or by what they provide), and what those need
closure() {
    local -A seen=()
    local todo=("$1") x d p
    while ((${#todo[@]})); do
        x=${todo[0]} todo=("${todo[@]:1}")
        [[ -z ${seen[$x]:-} ]] || continue
        seen[$x]=1
        for d in ${needs[$x]:-}; do
            for p in "$d" ${prov[$d]:-}; do [[ " ${new[*]} " != *" $p "* ]] || todo+=("$p"); done
        done
    done
    printf '%s\n' "${!seen[@]}" | sort | paste -sd' '
}
# trial <name>...: their new builds installed over the published [agros] (pass B's), the tests in $want run again (none:
# all), then pass B's packages back. 0: they pass; 1: some fail ($failed); 2: it couldn't be tried
tries=0
trial() {
    local files=() n r=0 extra
    tries=$((tries + 1))
    for n; do files+=("${built#file://}/${file[$n]}"); done
    pacman -U --noconfirm "${files[@]}" >/dev/null 2>&1 || r=2
    if ((r == 0)); then
        run_tests "${want[@]}"
        ((rc == 0 || ${#failed[@]})) || r=2
        ((r || ${#failed[@]} == 0)) || r=1
    fi
    pacman -Suu --noconfirm >/dev/null 2>&1 || r=2
    mapfile -t extra < <(pacman -Qq 2>/dev/null | sort | comm -13 "$keep/installed" -)
    ((${#extra[@]} == 0)) || pacman -Rdd --noconfirm "${extra[@]}" >/dev/null 2>&1 || r=2
    return "$r"
}
# culprits (after pass B passed): which new build broke the tests, as said at the top. shortcut: one at a time, not
# bisected: only the new builds of packages installed here are tried (Caelestia's, Quickshell's: a handful); more than
# AGROS_TRIALS tries' worth, all held as before
culprits() {
    local n a b c x r max=${AGROS_TRIALS:-10} cands=() rest=() others line
    local -A pub=() bad=() hold=()
    notfound() { echo "    not found which one ($1): every new AUR build held" >>"$report"; }
    [[ -s $keep/built.db ]] || { notfound "the built database wasn't kept"; return; }
    while read -r n a b; do
        case $a in
            '>') needs[$n]+=" $b" ;;
            '=') prov[$b]+=" $n" ;;
            *) file[$n]=$a ;;
        esac
    done < <(descs "$keep/built.db")
    while read -r n a b; do [[ $a == [\>=] ]] || pub[$n]=$a; done < <(descs "$sync/agros.db")
    # (AgrOS's own aren't held: this commit's)
    mapfile -t new < <(for n in "${!file[@]}"; do
        [[ $n == agros-* || ${pub[$n]:-} == "${file[$n]}" ]] || echo "$n"
    done | sort)
    # (one not installed here: the tests never had it)
    for n in "${new[@]}"; do if pacman -Q "$n" >/dev/null 2>&1; then cands+=("$n"); fi; done
    echo "- Each new build installed here tried alone over the published [agros] (with the new builds it needs), the tests that failed run again (${broke[*]}):" >>"$report"
    ((${#cands[@]})) || { notfound "none of them is installed where the tests run"; return; }
    ((${#cands[@]} < max)) || { notfound "${#cands[@]} new builds, more than AGROS_TRIALS=$max tries"; return; }
    pacman -Qq 2>/dev/null | sort >"$keep/installed"
    want=("${broke[@]}")
    for c in "${cands[@]}"; do
        # shellcheck disable=SC2046  # (names, each a word)
        trial $(closure "$c"); r=$?
        ((r != 2)) || { notfound "$c's couldn't be installed, or the tests run"; return; }
        ((r)) || { echo "    $c: passed" >>"$report"; continue; }
        bad[$c]=${failed[*]}
        ((tries < max)) || { notfound "no tries left to try $c's again"; return; }
        # shellcheck disable=SC2046
        trial $(closure "$c"); r=$?
        ((r != 2)) || { notfound "$c's couldn't be installed again, or the tests run"; return; }
        ((r)) || { notfound "$c's failed ${bad[$c]}, then passed: by chance"; return; }
        echo "    $c: fails ${bad[$c]}, twice" >>"$report"
    done
    ((${#bad[@]})) || { notfound "each passes alone: only some together fail them, or they failed by chance"; return; }
    # Held: each that failed (said as needing another, held, when its trial had that one's new build too); then each new
    # build, installed here or not, that needs one held: it goes with it
    for c in "${!bad[@]}"; do
        others=$(for x in $(closure "$c"); do [[ $x == "$c" || -z ${bad[$x]:-} ]] || echo "$x"; done | paste -sd' ')
        if [[ -n $others ]]; then
            hold[$c]="it needs ${others// /, }'s new build, held"
        else
            hold[$c]="its new build fails AgrOS's tests ${bad[$c]// /, } (they pass with the published one)"
        fi
    done
    a=1
    while ((a)); do
        a=0
        for n in "${new[@]}"; do
            [[ -z ${hold[$n]:-} ]] || continue
            for x in $(closure "$n"); do
                [[ $x != "$n" && -n ${hold[$x]:-} ]] || continue
                hold[$n]="it needs $x's new build, held" a=1
                break
            done
        done
    done
    # The rest together, every test (what goes out with them; none installed here: pass B's, passed)
    for c in "${cands[@]}"; do [[ -n ${hold[$c]:-} ]] || rest+=("$c"); done
    if ((${#rest[@]})); then
        ((tries < max)) || { notfound "no tries left for the others together"; return; }
        want=()
        trial "${rest[@]}"; r=$?
        ((r != 1)) || { notfound "the others together fail ${failed[*]}"; return; }
        ((r == 0)) || { notfound "the others couldn't be installed together, or the tests run"; return; }
    fi
    line=$(printf '%s\n' "${!hold[@]}" | sort | paste -sd' ')
    echo "    held: ${line// /, }; the other new builds go out${rest[*]:+ (every test passes with ${rest[*]})}" >>"$report"
    { echo 'hold<<EOF'; for n in $line; do echo "$n: ${hold[$n]}"; done; echo EOF; } >>"$out"
}
ahead=
result() {
    if [[ -n $ahead ]]; then
        echo "- Upstream's next release (its main branch, or Arch's builds CachyOS hasn't rebuilt yet) no longer fits AgrOS's changes: nothing held, adapt them before it's released:"
        echo "$ahead"
    fi >>"$report"
    # (the tests that failed among the others and passed alone, tests/run.sh's AGROS_FLAKY: CI's record of them)
    [[ -z ${AGROS_FLAKY:-} ]] || echo "flaky=$(sort -u "$AGROS_FLAKY" 2>/dev/null | paste -sd' ')" >>"$out"
    echo "result=$1" >>"$out"; echo "Tests: $1"; exit "${2:-0}"
}
agros_at "$built"
synced "!! the built [agros] didn't install" -Syuu --noconfirm --needed caelestia-shell
# (the built database, for which builds are new: pass B syncs the published one over it)
cp "$sync/agros.db" "$keep/built.db" 2>/dev/null
echo "- With this run's [agros], on today's Arch:" >>"$report"
tests
ahead=$(sed -n 's/^ok \([^ ]*\) .*(AHEAD: \(.*\))$/    AHEAD \1: \2/p' <<<"$log")
# arch_ahead: pass A once more on Arch's own builds, when CachyOS's v3 repos were above them (not on a runner without
# x86-64-v3): what fails there an AHEAD line. Arch's not installing only said; CachyOS's put back as it was (synced:
# that failing stops the run, as the approved versions are read from what's installed)
arch_ahead() {
    local n why
    grep -qx '\[cachyos-v3\]' "$conf" || return 0
    cp "$conf" "$keep/pacman.conf"
    v3_off
    if pacman -Syyuu --noconfirm >/dev/null 2>&1; then
        run_tests
        while read -r n why; do
            ahead+=${ahead:+$'\n'}"    AHEAD ${n%:}: fails on Arch's own builds, ahead of CachyOS's v3 rebuilds of them: $why"
        done < <(sed -n 's/^FAIL //p' <<<"$log")
    else
        echo "    (not tried on Arch's own builds, ahead of CachyOS's: they didn't install)" >>"$report"
    fi
    cp "$keep/pacman.conf" "$conf"
    synced "!! CachyOS's v3 builds didn't install again" -Syyuu --noconfirm
}
((${#failed[@]})) || { echo "    all passed" >>"$report"; arch_ahead; result ok; }
broke=("${failed[@]}")
agros_at "$published"
# (-yy: the sync db is the built one, newer than the published; -y kept it, checked against the published .sig)
synced "!! the published [agros] didn't install" -Syyuu --noconfirm
echo "- All again with the published [agros]:" >>"$report"
tests
((${#failed[@]})) || { echo "    passed: this run's new AUR builds broke them" >>"$report"; culprits; result hold-agros; }
# (none: agros-arch-ok not published yet, or not read, CI's test job's fetch failing)
[[ $day =~ ^[0-9]{4}/[0-9]{2}/[0-9]{2}$ ]] || stopped "!! no day Arch last passed on (agros-arch-ok), not tried on an older Arch"
# shellcheck disable=SC2016  # (pacman's own variables)
printf 'Server = https://archive.archlinux.org/repos/%s/$repo/os/$arch\n' "$day" >"${MIRRORLIST:-/etc/pacman.d/mirrorlist}"
v3_off
# (no download timeout: the archive answers slowly, pacman gave up after 10 seconds under a byte a second)
synced "!! Arch as of $day didn't install" -Syyuu --noconfirm --disable-download-timeout
echo "- All again on Arch as of $day (the last day they passed on it; CachyOS's v3 rebuilds left out):" >>"$report"
tests
((${#failed[@]})) || { echo "    passed: an upstream update since (Arch's, or CachyOS's rebuild of it) broke them" >>"$report"; result hold-upstream; }
echo "    still failing: AgrOS's own code" >>"$report"
result fail 1
