#!/usr/bin/env bash
# Capri after a restore (agros-personal's mark: gh's login came back in the keyring, which opens only from the next
# login): dotfiles-check at that login (--notify) installs her with capri-update, in the background, a failure said in
# a notification; gh still without a login, said as a problem; once either way (the mark gone); run by hand, nothing
# done; already installed, nothing done
set -uo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
export HOME=$t/home XDG_STATE_HOME=''
lib=$t/lib mark=$t/home/.local/state/agros/capri-at-login
mkdir -p "$lib" "$t/bin" "${mark%/*}"
# (dotfiles-check alone beside its helpers' stand-ins: capri-update and dots-warn written down, the others not there)
cp "$here/.local/bin/dotfiles-check" "$lib/"
printf '#!/bin/sh\necho capri-update >>"%s/ran"\necho "capri: cant clone it"\nexit "${CAPRI_RC:-0}"\n' "$t" >"$lib/capri-update"
# (Capri's notifications only: the check's own, of the helpers not there, isn't this test's)
printf '#!/bin/sh\ncase "$1" in Capri*) echo "warn $*" >>"%s/ran" ;; esac\n' "$t" >"$lib/dots-warn"
printf '#!/bin/sh\n[ "$1 $2" = "auth status" ] && exit "${GH_RC:-0}"\nexit 0\n' >"$t/bin/gh"
printf '#!/bin/sh\nexit 0\n' >"$t/bin/qs"
chmod +x "$lib"/* "$t/bin"/*
check() { rm -f "$t/ran"; PATH=$t/bin:$PATH "$lib/dotfiles-check" "$@" 2>&1; }
ran() {  # <want>: what ran, once its background run is done
    for _ in {1..50}; do [[ $(cat "$t/ran" 2>/dev/null) == "$1" ]] && return 0; sleep 0.1; done
    return 1
}

: >"$mark"
check >/dev/null
[[ -e $mark && ! -e $t/ran ]] || fail "run by hand: the mark acted on"
check --notify >/dev/null
ran capri-update || fail "Capri not installed at the login after the restore: $(cat "$t/ran" 2>/dev/null)"
[[ ! -e $mark ]] || fail "the mark left after Capri's install started"
check --notify >/dev/null
sleep 0.5; [[ ! -e $t/ran ]] || fail "Capri installed twice: $(cat "$t/ran")"
# Her install failing: said
: >"$mark"; CAPRI_RC=1 check --notify >/dev/null
ran $'capri-update\nwarn Capri didn\'t install capri: cant clone it' || fail "a failed install not said: $(cat "$t/ran" 2>/dev/null)"
# gh with no login: said, once
: >"$mark"; out=$(GH_RC=1 check --notify)
grep -q "Capri isn't installed: GitHub has no login here" <<<"$out" || fail "gh with no login not said: $out"
[[ ! -e $mark ]] || fail "the mark left with gh not logged in"
# Already installed (by hand): nothing
mkdir -p "$HOME/.local/share/capri/current"; : >"$mark"; check --notify >/dev/null
sleep 0.5; [[ ! -e $t/ran && ! -e $mark ]] || fail "Capri, installed, installed again: $(cat "$t/ran" 2>/dev/null)"
echo "ok dotfiles-check-capri"
