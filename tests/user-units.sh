#!/usr/bin/env bash
# The systemd user units: a service that restarts itself and notifies on failure (OnFailure=) goes straight back to
# starting between crashes (RestartMode=direct), or every crash, the first included, sends "keeps crashing"
set -euo pipefail
. "$(dirname "$0")/lib.sh"
for u in "$here"/.config/systemd/user/*.service; do
    if grep -q '^OnFailure=' "$u" && grep -qE '^Restart=(on-failure|always|on-abnormal)' "$u"; then
        grep -qx 'RestartMode=direct' "$u" || fail "${u##*/}: OnFailure= fires on every crash it restarts from (no RestartMode=direct)"
    fi
done
echo "ok user-units"
