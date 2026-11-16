#!/usr/bin/env bash
# ci/test-passes.sh: which side broke the tests. All pass on this run's [agros]: ok; those that failed pass with the
# published [agros]: hold-agros; then on Arch as of the last good day: hold-upstream; else fail. Each pass reruns only
# what failed before. pacman and the tests are stand-ins, which fail as $BROKEN says (built, published, today)
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
mkdir -p "$t/repo/ci" "$t/repo/tests" "$t/bin"
cp "$here/ci/test-passes.sh" "$t/repo/ci/"
printf '[core]\nInclude = x\n[agros]\nServer = https://example.invalid/old\n' >"$t/pacman.conf"
: >"$t/mirrorlist"
printf '#!/bin/sh\nexit 0\n' >"$t/bin/pacman"
printf '#!/bin/sh\nshift 2\nexec "$@"\n' >"$t/bin/runuser"
# (the stand-in tests: hypr-api and lutris; they fail where $BROKEN names the [agros] or the Arch they run on; "crash":
# run.sh itself fails, naming none)
# shellcheck disable=SC2016
printf '#!/bin/bash\necho "$*" >>%s/ran\ntrap -p INT >>%s/int\n[[ " $BROKEN " != *" crash "* ]] || exit 3\nagros=$(sed -n "s/^Server = //p" %s/pacman.conf); arch=$(cat %s/mirrorlist)\nfor n in ${*:-hypr-api lutris}; do\n  case " $BROKEN " in *" $n@${agros##*/} "*|*" $n@today "*) [[ -n $arch && " $BROKEN " != *" $n@always "* ]] && echo "ok $n" || echo "FAIL $n: broken" ;; *) echo "ok $n" ;; esac\ndone\n' \
    "$t" "$t" "$t" "$t" >"$t/repo/tests/run.sh"
chmod +x "$t/bin/"* "$t/repo/tests/run.sh"
# go <BROKEN> [<day>]: the result line, what ran (a line per pass)
go() {
    rm -f "$t/ran" "$t/out"; : >"$t/mirrorlist"
    sed -i 's|^Server = .*|Server = https://example.invalid/old|' "$t/pacman.conf"
    BROKEN=$1 PATH=$t/bin:$PATH PACMAN_CONF=$t/pacman.conf MIRRORLIST=$t/mirrorlist GITHUB_OUTPUT=$t/out \
        AGROS_TEST_REPORT=$t/report "$t/repo/ci/test-passes.sh" file:///built https://example.invalid/published "${2:-}" \
        >/dev/null 2>&1 || true
    echo "$(cat "$t/out") | $(paste -sd'|' "$t/ran")"
}
[[ $(go "") == "result=ok | " ]] || fail "all passing: not ok: $(go "")"
# (the published [agros] fixes lutris: this run's AUR builds broke it; rerun alone)
[[ $(go "lutris@built") == "result=hold-agros | |lutris" ]] || fail "broken by this run's [agros]: $(go "lutris@built")"
grep -q 'FAIL lutris' "$t/report" || fail "the report doesn't say what failed: $(cat "$t/report")"
# (broken on today's Arch, whatever [agros]; fine on the last good day's Arch)
[[ $(go "hypr-api@today" 2026/11/14) == "result=hold-upstream | |hypr-api|hypr-api" ]] || fail "broken by an Arch update: $(go "hypr-api@today" 2026/11/14)"
grep -qx 'Server = https://archive.archlinux.org/repos/2026/11/14/$repo/os/$arch' "$t/mirrorlist" || fail "not on Arch's snapshot of that day: $(cat "$t/mirrorlist")"
[[ $(go "hypr-api@today hypr-api@always" 2026/11/14) == "result=fail | |hypr-api|hypr-api" ]] || fail "AgrOS's own break not a failure"
[[ $(go "hypr-api@today") == "result=fail | |hypr-api" ]] || fail "no last good day: not a failure"
# (run.sh failing with no test named (runuser refused, run.sh cut off): not "all passed", which approves Hyprland)
[[ $(go crash) == "result=fail | " ]] || fail "the tests not run read as all passed: $(go crash)"
# (not in a background job, which starts with Ctrl+C ignored: dotfiles-sync-edge's Ctrl+C then never reached the sync)
[[ ! -s $t/int ]] || fail "the tests ran with Ctrl+C ignored: $(sort -u "$t/int")"
echo "ok ci-test-passes"
