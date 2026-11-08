#!/usr/bin/env bash
# The desktop step stopped (Ctrl+C, a kill) while LibreWolf makes its first profile: that background LibreWolf ended too
# (it doesn't get Ctrl+C, and left running it kept the profile in use: LibreWolf said "already running" and setup
# "close LibreWolf" with no window open), and the temporary policies file taken away
set -euo pipefail
. "$(dirname "$0")/lib.sh"
export HOME=$t/home log=$t/calls
mkdir -p "$HOME/.local/share/firefox" "$t/bin" "$t/repo/.local/bin"
touch "$HOME/.local/share/firefox/settings.js"  # (what the step goes by: AgrOS has no bookmarks file)
# Stand-ins: a LibreWolf that never makes a profile, sudo noting its calls (and taking the policies file's text), no
# LibreWolf running already (a real one open on this machine doesn't count)
printf '#!/bin/sh\necho $$ >"%s/lw.pid"\nexec sleep 300\n' "$t" >"$t/bin/librewolf"
printf '#!/bin/sh\necho "sudo $*" >>"$log"\ncat >/dev/null\n' >"$t/bin/sudo"
printf '#!/bin/sh\nexit 1\n' >"$t/bin/pgrep"
printf '#!/bin/sh\n' >"$t/repo/.local/bin/firefox-bookmarks-export"
chmod +x "$t/bin/"* "$t/repo/.local/bin/"*
export PATH=$t/bin:$PATH
trap '[[ ! -s $t/lw.pid ]] || kill "$(cat "$t/lw.pid")" 2>/dev/null || true; rm -rf "$t"' EXIT

repo=$t/repo yes=true bash -c 'source "$1/setup/lib.sh"; source "$1/setup/modules/60-desktop.sh"; firefox_setup' _ "$here" \
    >/dev/null 2>&1 </dev/null &
setup=$!
for _ in $(seq 50); do [[ -s $t/lw.pid ]] && break; sleep 0.1; done
[[ -s $t/lw.pid ]] || fail "LibreWolf wasn't started"
kill -TERM "$setup"
for _ in $(seq 50); do kill -0 "$setup" 2>/dev/null || break; sleep 0.1; done
kill -0 "$setup" 2>/dev/null && fail "the step didn't stop"
sleep 0.2
kill -0 "$(cat "$t/lw.pid")" 2>/dev/null && fail "the background LibreWolf was left running"
# (only where this machine has no policies file of its own: else none is put there)
if [[ ! -e /etc/librewolf/policies/policies.json ]]; then
    grep -q "^sudo rm -f /etc/librewolf/policies/policies.json" "$log" || fail "the temporary policies file stayed: $(cat "$log")"
fi
# Written with its mark first; one a run cut off where nothing could take it away (a power cut) left, mark and all:
# the next run takes it away (here with LibreWolf open, the step going no further)
grep -q "^sudo install -Dm644 /dev/null /etc/librewolf/policies/policies.json.dotfiles-temporary" "$log" ||
    [[ -e /etc/librewolf/policies/policies.json ]] || fail "the policies file's mark not written before it: $(cat "$log")"
pol=$t/etc/librewolf/policies/policies.json
mkdir -p "${pol%/*}"; echo '{}' >"$pol"; touch "$pol.dotfiles-temporary"
# shellcheck disable=SC2016  # (expanded by the stand-in)
printf '#!/bin/sh\n[ "$1" = -n ] && shift\nexec "$@"\n' >"$t/bin/sudo"
printf '#!/bin/sh\nexit 0\n' >"$t/bin/pgrep"
out=$(LIBREWOLF_POLICIES=$pol repo=$t/repo yes=true bash -c 'source "$1/setup/lib.sh"; source "$1/setup/modules/60-desktop.sh"; firefox_setup' _ "$here" 2>&1 </dev/null) ||
    fail "the step failed taking away a left policies file: $out"
[[ ! -e $pol && ! -e $pol.dotfiles-temporary && $out == *"Took away the temporary LibreWolf policies file"* ]] ||
    fail "a policies file a cut-off run left (its mark beside it) not taken away: $out"
# (one of the machine's own, no mark: left alone)
mkdir -p "${pol%/*}"; echo '{}' >"$pol"
LIBREWOLF_POLICIES=$pol repo=$t/repo yes=true bash -c 'source "$1/setup/lib.sh"; source "$1/setup/modules/60-desktop.sh"; firefox_setup' _ "$here" >/dev/null 2>&1 </dev/null || true
[[ -e $pol ]] || fail "the machine's own policies file taken away"
# Its mark written, the policies file itself not (here sudo refuses that write): the mark taken away again at once,
# or a policies file put there later (yours, a package's) was removed as this one's. (LibreWolf makes its profile at
# once here, and that's the step's end)
rm -rf "${t:?}/etc"
# shellcheck disable=SC2016  # (expanded by the stand-ins)
printf '#!/bin/sh\n[ "$1" = -n ] && shift\ncase "$*" in *" /dev/stdin "*) cat >/dev/null; exit 1 ;; esac\nexec "$@"\n' >"$t/bin/sudo"
printf '#!/bin/sh\nexit 1\n' >"$t/bin/pgrep"
printf '#!/bin/sh\nmkdir -p %s/prof && touch %s/prof/prefs.js\n' "$t" "$t" >"$t/bin/librewolf"
# shellcheck disable=SC2016
printf '#!/bin/sh\n[ "$1" = --profile ] && [ -e %s/prof/prefs.js ] && echo %s/prof\nexit 0\n' "$t" "$t" >"$t/repo/.local/bin/firefox-bookmarks-export"
# shellcheck disable=SC2016  # (the step's own shell expands them)
LIBREWOLF_POLICIES=$pol repo=$t/repo yes=true timeout 60 bash -c 'source "$1/setup/lib.sh"; source "$1/setup/modules/60-desktop.sh"; firefox_setup' _ "$here" >/dev/null 2>&1 </dev/null || true
[[ -e $t/prof/prefs.js ]] || fail "test setup: the step didn't get to LibreWolf's first start"
[[ ! -e $pol.dotfiles-temporary && ! -e $pol ]] || fail "the policies file's mark left after its write failed"
echo "ok setup-librewolf-stop"
