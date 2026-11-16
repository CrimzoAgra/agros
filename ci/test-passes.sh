#!/usr/bin/env bash
# The tests on what this run built, and when some fail, which side broke them (CI's test job, as root in its container,
# the tests run as the ci user). Each pass runs the tests that failed in the one before:
#   A. [agros] as this run built it ($1, a pacman Server line's URL), on today's Arch: all pass, result=ok
#   B. the published [agros] ($2), the last good one: they pass, result=hold-agros (this run's new AUR builds broke them:
#      held back, the published ones kept; today's Arch, Hyprland too, passed)
#   C. that, on Arch as of the last day the tests passed on it ($3, YYYY/MM/DD, its archive's snapshot): they pass,
#      result=hold-upstream (an Arch update broke them: its Hyprland not approved, the new AUR builds held too)
#   Still failing: AgrOS's own code, result=fail (exit 1): nothing goes out
# Writes result=<...> to $GITHUB_OUTPUT (or stdout), and what failed in each pass to $AGROS_TEST_REPORT (markdown)
set -uo pipefail
built=${1:?usage: test-passes.sh <built repo URL> <published repo URL> [<last good Arch day>]} published=${2:?} day=${3:-}
report=${AGROS_TEST_REPORT:-/dev/null} out=${GITHUB_OUTPUT:-/dev/stdout}
here=$(cd "$(dirname "$0")/.." && pwd)
: >"$report"
agros_at() { sed -i "/^\[agros\]$/,/^Server/ s|^Server = .*|Server = $1|" "${PACMAN_CONF:-/etc/pacman.conf}"; }
# tests [<name>...]: the tests (all, or those), as the ci user: the names that failed
tests() {
    local log
    log=$(runuser -u ci -- env DOTS_BUILD_TESTS=1 "$here/tests/run.sh" "$@")
    printf '%s\n' "$log" >&2
    sed -n 's/^FAIL \([^:]*\): .*/\1/p' <<<"$log"
    grep '^FAIL ' <<<"$log" | sed 's/^/    /' >>"$report"
}
result() { echo "result=$1" >>"$out"; echo "Tests: $1"; exit "${2:-0}"; }
agros_at "$built"
pacman -Syuu --noconfirm --needed caelestia-shell >/dev/null || { echo "!! the built [agros] didn't install"; result fail 1; }
echo "- With this run's [agros], on today's Arch:" >>"$report"
mapfile -t failed < <(tests)
((${#failed[@]})) || { echo "    all passed" >>"$report"; result ok; }
agros_at "$published"
pacman -Syuu --noconfirm >/dev/null || { echo "!! the published [agros] didn't install"; result fail 1; }
echo "- The same with the published [agros]:" >>"$report"
mapfile -t failed < <(tests "${failed[@]}")
((${#failed[@]})) || { echo "    passed: this run's new AUR builds broke them" >>"$report"; result hold-agros; }
[[ $day =~ ^[0-9]{4}/[0-9]{2}/[0-9]{2}$ ]] || { echo "    (no day Arch last passed on: not tried on an older Arch)" >>"$report"; result fail 1; }
# shellcheck disable=SC2016  # (pacman's own variables)
printf 'Server = https://archive.archlinux.org/repos/%s/$repo/os/$arch\n' "$day" >"${MIRRORLIST:-/etc/pacman.d/mirrorlist}"
pacman -Syyuu --noconfirm >/dev/null || { echo "!! Arch as of $day didn't install"; result fail 1; }
echo "- The same on Arch as of $day (the last day they passed on it):" >>"$report"
mapfile -t failed < <(tests "${failed[@]}")
((${#failed[@]})) || { echo "    passed: an Arch update since broke them" >>"$report"; result hold-upstream; }
echo "    still failing: AgrOS's own code" >>"$report"
result fail 1
