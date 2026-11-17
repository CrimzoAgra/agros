#!/usr/bin/env bash
# ci/test-passes.sh: which side broke the tests. All pass on this run's [agros]: ok; those that failed pass with the
# published [agros]: hold-agros; then on Arch as of the last good day: hold-upstream; else fail. Each pass runs every
# test (what it ran: "all"). pacman and the tests are stand-ins, which fail as $BROKEN says (built, published, today)
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
mkdir -p "$t/repo/ci" "$t/repo/tests" "$t/bin"
cp "$here/ci/test-passes.sh" "$t/repo/ci/"
printf '[core]\nInclude = x\n[agros]\nServer = https://example.invalid/old\n' >"$t/pacman.conf"
: >"$t/mirrorlist"
printf '#!/bin/sh\nexit 0\n' >"$t/bin/pacman"
printf '#!/bin/sh\nshift 2\nexec "$@"\n' >"$t/bin/runuser"
# (the stand-in tests: hypr-api and lutris; they fail where $BROKEN names the [agros] or the Arch they run on, and pass
# saying upstream's next release doesn't fit where it names main: the line a test makes for it, lib.sh's ok_line;
# "crash": run.sh itself fails, naming none)
ahead "no longer fits main"; ahead x
ok_line test "2 left out" >"$t/main-line"
# shellcheck disable=SC2016
printf '#!/bin/bash\necho "${*:-all}" >>%s/ran\ntrap -p INT >>%s/int\n[[ " $BROKEN " != *" crash "* ]] || exit 3\nagros=$(sed -n "s/^Server = //p" %s/pacman.conf); arch=$(cat %s/mirrorlist)\nfor n in ${*:-hypr-api lutris}; do\n  case " $BROKEN " in *" $n@${agros##*/} "*|*" $n@today "*) [[ -n $arch && " $BROKEN " != *" $n@always "* ]] && echo "ok $n" || echo "FAIL $n: broken" ;; *" $n@main "*) sed "s/^ok test /ok $n /" %s/main-line ;; *) echo "ok $n" ;; esac\ndone\n' \
    "$t" "$t" "$t" "$t" "$t" >"$t/repo/tests/run.sh"
chmod +x "$t/bin/"* "$t/repo/tests/run.sh"
# go <BROKEN> [<day>]: the result line, what ran (a line per pass)
go() {
    rm -f "$t/ran" "$t/out"; : >"$t/mirrorlist"
    sed -i 's|^Server = .*|Server = https://example.invalid/old|' "$t/pacman.conf"
    # (the published repo's database signatures, as an earlier sync leaves them)
    mkdir -p "$t/sync"; touch "$t/sync/agros.db.sig" "$t/sync/agros.files.sig" "$t/sync/core.db"
    BROKEN=$1 PATH=$t/bin:$PATH PACMAN_CONF=$t/pacman.conf PACMAN_SYNC=$t/sync MIRRORLIST=$t/mirrorlist GITHUB_OUTPUT=$t/out \
        AGROS_TEST_REPORT=$t/report "$t/repo/ci/test-passes.sh" file:///built https://example.invalid/published "${2:-}" \
        >/dev/null 2>&1 || true
    echo "$(cat "$t/out") | $(paste -sd'|' "$t/ran")"
}
[[ $(go "") == "result=ok | all" ]] || fail "all passing: not ok: $(go "")"
# (no stale database signature left for the unsigned built repo: pacman refused its new database with the old .sig)
go "" >/dev/null
[[ ! -e $t/sync/agros.db.sig && ! -e $t/sync/agros.files.sig && -e $t/sync/core.db ]] ||
    fail "[agros]'s old database signatures left, or another repo's file taken: $(ls "$t/sync")"
# (the published [agros] fixes lutris: this run's AUR builds broke it; every test run again)
[[ $(go "lutris@built") == "result=hold-agros | all|all" ]] || fail "broken by this run's [agros]: $(go "lutris@built")"
grep -q 'FAIL lutris' "$t/report" || fail "the report doesn't say what failed: $(cat "$t/report")"
# (one that passed on this run's [agros] fails on the published one, which a hold would put out beside this commit's
# own packages: an overlay changed for the new Caelestia, on the old one): not a hold
[[ $(go "hypr-api@built lutris@published") == "result=fail | all|all" ]] ||
    fail "a test failing only on the published [agros] not run before holding it: $(go "hypr-api@built lutris@published")"
# (broken on today's Arch, whatever [agros]; fine on the last good day's Arch)
[[ $(go "hypr-api@today" 2026/11/14) == "result=hold-upstream | all|all|all" ]] || fail "broken by an Arch update: $(go "hypr-api@today" 2026/11/14)"
grep -qx 'Server = https://archive.archlinux.org/repos/2026/11/14/$repo/os/$arch' "$t/mirrorlist" || fail "not on Arch's snapshot of that day: $(cat "$t/mirrorlist")"
[[ $(go "hypr-api@today hypr-api@always" 2026/11/14) == "result=fail | all|all|all" ]] || fail "AgrOS's own break not a failure"
[[ $(go "hypr-api@today") == "result=fail | all|all" ]] || fail "no last good day: not a failure"
# (run.sh failing with no test named (runuser refused, run.sh cut off): not "all passed", which approves Hyprland)
[[ $(go crash) == "result=fail | all" ]] || fail "the tests not run read as all passed: $(go crash)"
# (upstream's next release not fitting: no failure, said in the report once, after what failed, whatever the result)
[[ $(go "lutris@main") == "result=ok | all" ]] || fail "upstream's main not fitting: not ok: $(go "lutris@main")"
grep -qx '    AHEAD lutris: no longer fits main; x' "$t/report" || fail "upstream's main not fitting not in the report: $(cat "$t/report")"
[[ $(go "lutris@main hypr-api@built") == "result=hold-agros | all|all" ]] || fail "with upstream's main not fitting: $(go "lutris@main hypr-api@built")"
[[ $(grep -c AHEAD "$t/report") == 1 && $(tail -n1 "$t/report") == "    AHEAD lutris: no longer fits main; x" ]] ||
    fail "upstream's main not said once, at the end: $(cat "$t/report")"
[[ $(go "lutris@main hypr-api@today hypr-api@always" 2026/11/14) == "result=fail | all|all|all" ]] ||
    fail "AgrOS's own break not a failure with a test saying upstream's main doesn't fit"
# (not in a background job, which starts with Ctrl+C ignored: dotfiles-sync-edge's Ctrl+C then never reached the sync)
[[ ! -s $t/int ]] || fail "the tests ran with Ctrl+C ignored: $(sort -u "$t/int")"
echo "ok ci-test-passes"
