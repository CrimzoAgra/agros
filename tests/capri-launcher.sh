#!/usr/bin/env bash
# ~/.local/bin/capri: her build's binary started (current/capri) with her arguments, its output in ~/.cache/capri.log,
# which is moved to capri.log.1 once past 5 MB (each start adds to it); $CAPRI_RUN run instead when set; not installed
# (or only an Electron build of hers there): said
set -uo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
export HOME="$t/ho me" XDG_DATA_HOME='' XDG_CACHE_HOME='' CAPRI_RUN=''
out=$("$here/.local/bin/capri" 2>&1) && fail "started with her not installed"
[[ $out == *"isn't installed"* ]] || fail "not installed not said: $out"
b="$HOME/.local/share/capri/abc1234"
mkdir -p "$b/node_modules/.bin"; echo '{}' >"$b/package.json"
ln -s abc1234 "$HOME/.local/share/capri/current"
out=$("$here/.local/bin/capri" 2>&1) && fail "started an Electron build"
[[ $out == *"isn't installed"* ]] || fail "an Electron build not said as not installed: $out"
printf '#!/bin/sh\necho "started $0 with: $*"\n' >"$b/capri"
chmod +x "$b/capri"
log="$HOME/.cache/capri.log"
HYPRLAND_INSTANCE_SIGNATURE=x "$here/.local/bin/capri" --hidden || fail "she didn't start"
grep -qx "started $HOME/.local/share/capri/current/capri with: --hidden" "$log" ||
    fail "not started as her build's binary with her arguments alone: $(cat "$log")"
# Past 5 MB: moved aside at her next start, the new log begun
head -c 6000000 /dev/zero >"$log"
"$here/.local/bin/capri" || fail "she didn't start"
[[ $(stat -c %s "$log.1") == 6000000 && $(wc -l <"$log") == 1 ]] || fail "the log not moved aside past 5 MB"
grep -qx "started $HOME/.local/share/capri/current/capri with: " "$log" || fail "not started as she is: $(cat "$log")"
# A small one kept as it is
"$here/.local/bin/capri"
[[ $(wc -l <"$log") == 2 ]] || fail "a small log moved aside"
# In a VMware VM, her video's GPU buffers turned off (VMware's driver refuses them: her frame empty); not elsewhere,
# and a value of yours kept
printf '#!/bin/sh\necho "sink=${WEBKIT_GST_DMABUF_SINK_DISABLED-unset}"\n' >"$b/capri"
stub systemd-detect-virt 'echo "$VIRT"'
start() { VIRT=$1 PATH=$t/bin:$PATH "$here/.local/bin/capri"; tail -1 "$log"; }
[[ $(start vmware) == sink=1 ]] || fail "in VMware, her video's GPU buffers not turned off: $(tail -1 "$log")"
[[ $(start none) == sink=unset ]] || fail "her video's GPU buffers turned off outside VMware: $(tail -1 "$log")"
[[ $(WEBKIT_GST_DMABUF_SINK_DISABLED=0 start vmware) == sink=0 ]] || fail "your own WEBKIT_GST_DMABUF_SINK_DISABLED replaced"
# $CAPRI_RUN: that script instead, with her arguments
printf '#!/bin/sh\necho "mine: $*"\n' >"$t/run"; chmod +x "$t/run"
[[ $(CAPRI_RUN=$t/run "$here/.local/bin/capri" --hidden) == "mine: --hidden" ]] || fail "\$CAPRI_RUN not run"
echo "ok capri-launcher"
