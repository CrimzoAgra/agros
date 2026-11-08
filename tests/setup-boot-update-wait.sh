#!/usr/bin/env bash
# The setup steps that install packages wait for the update started at boot first (both fetching the same package
# into pacman's cache at once corrupts it): the caelestia and system steps too, which can run alone
# (./setup.sh --only system right after a boot), not only packages and apps
set -euo pipefail
. "$(dirname "$0")/lib.sh"
export HOME=$t/home log=$t/calls
mkdir -p "$HOME" "$t/bin"
# Stand-ins noting each call: nothing installed or changed
for c in paru caelestia sudo modinfo; do printf '#!/bin/sh\necho "%s $*" >>"$log"\n' "$c" >"$t/bin/$c"; done
printf '#!/bin/sh\necho "systemctl $*" >>"$log"\n[ "$1" != is-active ] || exit 1\n' >"$t/bin/systemctl"
chmod +x "$t/bin/"*
export PATH=$t/bin:$PATH
# The step's first call to sudo, caelestia or paru: after it looked for the boot's update
waited_first() {
    local first
    first=$(grep -nm1 -E '^(sudo|caelestia|paru) ' "$log" | cut -d: -f1)
    grep -nm1 '^systemctl is-active -q auto-update' "$log" | awk -F: -v f="${first:-999999}" '$1 < f {ok=1} END {exit !ok}'
}
for step in caelestia system; do
    : >"$log"
    repo=$here yes=true bash -c 'source "$1/setup/lib.sh"; source "$1"/setup/modules/[0-9][0-9]-"$2".sh; module_"$2"' \
        _ "$here" "$step" >/dev/null 2>&1 || true
    grep -qE '^(sudo|caelestia|paru) ' "$log" || fail "the $step step didn't run: $(cat "$log")"
    waited_first || fail "the $step step installs without waiting for the boot's update: $(head -3 "$log")"
done
echo "ok setup-boot-update-wait"
