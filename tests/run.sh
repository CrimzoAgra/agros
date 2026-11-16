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
        *) out=$(setsid -w "$here/$t.sh" 2>&1 </dev/null) ;;
    esac || { f=$(grep -m1 "^FAIL: " <<<"$out") || f=${out##*$'\n'}; out="FAIL $t: ${f#FAIL: }"; }
    # (on CI a pass approves that Hyprland for AgrOS's machines (the upstream gate), and CI has all the tests need: a
    # test skipped there, in part or whole (offline, a check that couldn't run), isn't a pass)
    last=${out##*$'\n'}
    if [[ -n ${CI:-} && ( $last == skip\ * || $last == *SKIPPED* ) ]]; then
        out="FAIL $t: skipped on CI, where a pass approves Hyprland: ${last}"
    fi
    echo "$out" | tail -1
}
jobs=${AGROS_TEST_JOBS:-$(nproc 2>/dev/null || echo 1)}
res=$(mktemp -d) && trap 'rm -rf "$res"' EXIT
if ((jobs > 1 && ${#tests[@]} > 1)); then
    export -f one && export here
    # shellcheck disable=SC2016  # (expanded by that bash)
    printf '%s\0' "${tests[@]}" | xargs -0 -P "$jobs" -I{} bash -c 'one "$1" >"$2/$1"' _ {} "$res"
fi
# (in order, as one at a time printed them)
for t in "${tests[@]}"; do
    line=$(cat "$res/$t" 2>/dev/null)
    [[ -n $line && $line != FAIL\ * ]] || line=$(one "$t")
    [[ $line != FAIL\ * ]] || failed=1
    echo "$line"
done
exit $failed
