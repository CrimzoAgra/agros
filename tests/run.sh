#!/usr/bin/env bash
# Every test, in a throwaway home each (nothing of yours is touched): tests/run.sh, or tests/run.sh <name>...
# Run after changing a script, and after Caelestia, Lutris or Hyprland updates (the overlays and patch must still fit)
here=$(cd "$(dirname "$0")" && pwd)
failed=0
tests=("$@")
((${#tests[@]})) || tests=($(cd "$here" && ls -- *.sh | grep -vx -e run.sh -e lib.sh | sed 's/\.sh$//') boot-video-mode)
for t in "${tests[@]}"; do
    case $t in
        boot-video-mode) out=$(python3 "$here/../system/boot-video-mode" --test 2>&1 </dev/null) && out="ok boot-video-mode" ;;
        # (no test can wait on the terminal: no stdin, and in a session of its own, without it, as sudo asks there)
        *) out=$(setsid -w "$here/$t.sh" 2>&1 </dev/null) ;;
    esac || { failed=1; out="FAIL $t: ${out##*$'\n'}"; }
    echo "$out" | tail -1
done
exit $failed
