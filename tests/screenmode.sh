#!/usr/bin/env bash
# screenmode.py's best(): the screen's own resolution when it has a mode there, else the highest, then its best refresh
# rate (its self-check)
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
PYTHONDONTWRITEBYTECODE=1 python3 -I "$here/.local/share/caelestia-greeter/screenmode.py"
