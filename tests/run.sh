#!/usr/bin/env bash
# Every test, in a throwaway home each (nothing of yours is touched): tests/run.sh, or tests/run.sh <name>...
# Run after changing a script, and after Caelestia, Lutris or Hyprland updates (the overlays and patch must still fit)
# Several at once (one per CPU; AGROS_TEST_JOBS=1: one at a time). One that fails among the others runs again alone:
# only a failure there counts (two tests at once sharing something, /tmp or the user manager, isn't the code's fault)
here=$(cd "$(dirname "$0")" && pwd)
failed=0
tests=("$@")
if ((!${#tests[@]})); then
    for f in "$here"/*.sh; do f=${f##*/}; [[ $f == run.sh || $f == lib.sh ]] || tests+=("${f%.sh}"); done
    tests+=(boot-video-mode)
fi
# one <test>: its line, "ok <test>" or "FAIL <test>: <why>"
one() {
    local t=$1 out f last
    case $t in
        boot-video-mode) out=$(python3 "$here/../system/boot-video-mode" --test 2>&1 </dev/null) && out="ok boot-video-mode" ;;
        # (no test can wait on the terminal: no stdin, and in a session of its own, without it, as sudo asks there)
        # (and none runs on forever: stopped at its time limit, AGROS_TEST_TIMEOUT seconds, with what it started in its
        # session, timeout's process group (one left holding the output kept this waiting too). A hang otherwise ran CI's
        # job until GitHub stopped it hours later, with no word of which test)
        *) out=$(setsid -w timeout -k 10 "$limit" "$here/$t.sh" 2>&1 </dev/null) ;;
    esac || {
        local rc=$?
        f=$(grep -m1 "^FAIL: " <<<"$out") || f=${out##*$'\n'}
        ((rc != 124 && rc != 137)) || f="stopped at its time limit (${limit}s; its last line: ${f:-none})"
        out="FAIL $t: ${f#FAIL: }"
    }
    # (a pass ends on its own "ok <test>" or "skip <test>" line: one that stopped early with exit 0, an exit meant for a
    # stand-in it writes or a script it sources, never reached its last checks)
    last=${out##*$'\n'}
    case $last in
        "FAIL $t: "* | "ok $t" | "ok $t "* | "skip $t" | "skip $t "*) ;;
        *) out="FAIL $t: it ended without its \"ok $t\" line: ${last:-no output}" ;;
    esac
    # (on CI a pass approves that Hyprland for AgrOS's machines (the upstream gate), and CI has all the tests need: a
    # test skipped there, in part or whole (offline, a check that couldn't run), isn't a pass)
    last=${out##*$'\n'}
    if [[ -n ${CI:-} && ( $last == skip\ * || $last == *SKIPPED* ) ]]; then
        out="FAIL $t: skipped on CI, where a pass approves Hyprland: ${last}"
    fi
    echo "$out" | tail -1
}
jobs=${AGROS_TEST_JOBS:-$(nproc 2>/dev/null || echo 1)}
limit=${AGROS_TEST_TIMEOUT:-600}
res=$(mktemp -d) && trap 'rm -rf "$res"' EXIT
if ((jobs > 1 && ${#tests[@]} > 1)); then
    export -f one && export here limit
    # shellcheck disable=SC2016  # (expanded by that bash)
    printf '%s\0' "${tests[@]}" | xargs -0 -P "$jobs" -I{} bash -c 'one "$1" >"$2/$1"' _ {} "$res"
fi
# (in order, as one at a time printed them)
for t in "${tests[@]}"; do
    first=$(cat "$res/$t" 2>/dev/null) line=$first
    [[ -n $line && $line != FAIL\ * ]] || line=$(one "$t")
    # (one that failed among the others and passed alone said on stderr, out of the results: a flaky test showed nowhere)
    [[ $first != FAIL\ * || $line == FAIL\ * ]] || echo "!! $t failed among the others, passed alone: ${first#"FAIL $t: "}" >&2
    [[ $line != FAIL\ * ]] || failed=1
    echo "$line"
done
exit $failed
