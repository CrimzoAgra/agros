#!/usr/bin/env bash
# update-apps --list (the package tools stubbed): each kind's updates in one form, ignored AUR ones left out, and the
# package servers out of reach an "offline" line instead of an empty list that reads as up to date
set -euo pipefail
. "$(dirname "$0")/lib.sh"
mkdir -p "$t/bin" "$t/home"
stub() { printf '#!/bin/sh\n%s\n' "$2" >"$t/bin/$1"; chmod +x "$t/bin/$1"; }
stub checkupdates 'echo "linux 6.1-1 -> 6.2-1"'
# (paru translates its "[ignored]": in Portuguese it's "[ignorado]")
stub paru 'echo "equibop 1.0-1 -> 1.1-1"; [ "${LC_ALL:-}" = C ] && echo "held 1-1 -> 2-1 [ignored]" || echo "held 1-1 -> 2-1 [ignorado]"'
stub flatpak '[ "$1" = remote-ls ] && printf "com.spotify.Client\t1.3\n"; [ "$1" = info ] && echo "  Version: 1.2"; true'
run() { HOME=$t/home PATH=$t/bin:$PATH "$here/.local/bin/update-apps" --list; }
out=$(run)
want=$(printf 'system\tlinux\t6.1-1\t6.2-1\naur\tequibop\t1.0-1\t1.1-1\nflatpak\tcom.spotify.Client\t1.2\t1.3')
[[ $out == "$want" ]] || fail "the list: $out"
stub checkupdates 'exit 1'
[[ $(run) == offline* ]] || fail "offline not said: $(run)"
stub checkupdates 'exit 2'; stub paru 'true'; stub flatpak 'true'
[[ -z $(run) ]] || fail "nothing waiting, still listed: $(run)"

# --check: a notification left unclicked until the next check (its timeout) still counts as announced; one the
# notification server dropped (Caelestia restarted under it) doesn't
stub checkupdates 'echo "linux 6.1-1 -> 6.2-1"'
stub timeout 'shift; exec /usr/bin/timeout 1 "$@"'  # (5h50m: a second here)
mkdir -p "$t/home/.local/bin" "$t/home/.cache"
seen=$t/home/.cache/update-apps-notified
check() { HOME=$t/home XDG_CACHE_HOME=$t/home/.cache PATH=$t/bin:$PATH "$here/.local/bin/update-apps" --check; }
printf '#!/bin/sh\nexit 143\n' >"$t/home/.local/bin/notify-wait"; chmod +x "$t/home/.local/bin/notify-wait"
check
[[ ! -e $seen ]] || fail "a notification the server dropped noted as announced"
printf '#!/bin/sh\nexec sleep 30\n' >"$t/home/.local/bin/notify-wait"
check
[[ $(cat "$seen" 2>/dev/null) == linux ]] || fail "an unclicked notification (its time ran out) not noted: announced again every check"

# The update, with no state folder yet: the Qt Quickshell was built for written down the first time, not taken for a
# new Qt at every run (each one rebuilding Quickshell and Caelestia)
stub paru 'echo "paru $*" >>"'"$t"'/paru"'
stub pacman 'case "$1 $2" in "-Q qt6-base" | "-Q qt6-declarative") echo "$2 6.9.0-1" ;; esac; true'
stub systemctl 'exit 1'
# (power off and sleep held off around pacman: systemd-inhibit stubbed, noting it and running what it holds for)
# shellcheck disable=SC2016
stub systemd-inhibit 'echo "inhibit $*" >>"'"$t"'/inhibit"; while [ "${1#--}" != "$1" ]; do shift; done; exec "$@"'
for _ in 1 2; do
    HOME=$t/home XDG_STATE_HOME=$t/state XDG_CACHE_HOME=$t/home/.cache PATH=$t/bin:$PATH "$here/.local/bin/update-apps" \
        </dev/null >/dev/null 2>&1 || true  # (its other steps, not stubbed here, fail)
done
[[ -s $t/state/quickshell-qt ]] || fail "the Qt Quickshell was built for not written down"
! grep -q -- --rebuild "$t/paru" || fail "Quickshell rebuilt with Qt unchanged: $(cat "$t/paru")"
# setup's own pacman -Syu, between update-apps --qt-mark and --qt-rebuild: a new Qt rebuilds Quickshell and Caelestia
# (only those installed, as the Updates app does), and the new Qt is written down; Qt unchanged: nothing rebuilt
rm -f "$t/paru" "$t/state/quickshell-qt"
# shellcheck disable=SC2016  # (expanded by the stub)
stub pacman 'case "$1 $2" in "-Q qt6-base" | "-Q qt6-declarative") echo "$2 $QT-1" ;; "-Q quickshell-git" | "-Q caelestia-shell") true ;; *) exit 1 ;; esac'
qt() { QT=$1 HOME=$t/home XDG_STATE_HOME=$t/state PATH=$t/bin:$PATH "$here/.local/bin/update-apps" "$2" </dev/null; }
{ qt 6.9.0 --qt-mark && qt 6.9.0 --qt-rebuild; } || fail "--qt-mark/--qt-rebuild with Qt unchanged failed"
[[ ! -e $t/paru ]] || fail "rebuilt with Qt unchanged: $(cat "$t/paru")"
qt 6.10.0 --qt-rebuild >/dev/null || fail "the rebuild for a new Qt failed"
grep -q -- "-S --rebuild --noconfirm aur/quickshell-git aur/caelestia-shell$" "$t/paru" || fail "not rebuilt for the new Qt: $(cat "$t/paru" 2>/dev/null)"
[[ $(cat "$t/state/quickshell-qt") == "qt6-base 6.10.0 qt6-declarative 6.10.0 " ]] || fail "the new Qt not written down"
# Part of Qt not installed (a fresh Arch, an edition without qt6-declarative): --qt-mark doesn't fail (setup runs it
# under set -e), the stamp names each one ("none"), and nothing is rebuilt with Qt unchanged
rm -f "$t/paru" "$t/state/quickshell-qt"
# shellcheck disable=SC2016  # (expanded by the stand-in)
stub pacman 'case "$1 $2" in "-Q qt6-base") echo "qt6-base 6.12.0-1" ;; *) exit 1 ;; esac'
qt x --qt-mark || fail "--qt-mark failed with qt6-declarative not installed"
[[ $(cat "$t/state/quickshell-qt") == "qt6-base 6.12.0 qt6-declarative none " ]] ||
    fail "the stamp with qt6-declarative missing: $(cat "$t/state/quickshell-qt")"
qt x --qt-rebuild || fail "--qt-rebuild failed with qt6-declarative not installed"
[[ ! -e $t/paru ]] || fail "rebuilt with Qt unchanged (part of it missing): $(cat "$t/paru")"
qt x --qt-stale && fail "--qt-stale says Qt changed when it didn't"
# shellcheck disable=SC2016  # (expanded by the stand-in)
stub pacman 'case "$1 $2" in "-Q qt6-base") echo "qt6-base 6.13.0-1" ;; *) exit 1 ;; esac'
qt x --qt-stale || fail "--qt-stale doesn't see a new Qt"
# Marked again once Qt is in (setup after its packages, a plain Arch): a stamp naming a package that wasn't installed
# ("none") is written anew, not taken for a new Qt to rebuild for; one naming each is kept
# shellcheck disable=SC2016  # (expanded by the stand-in)
stub pacman 'case "$1 $2" in "-Q qt6-base" | "-Q qt6-declarative") echo "$2 6.13.0-1" ;; *) exit 1 ;; esac'
qt x --qt-mark
[[ $(cat "$t/state/quickshell-qt") == "qt6-base 6.13.0 qt6-declarative 6.13.0 " ]] ||
    fail "a stamp from before Qt was installed not written anew: $(cat "$t/state/quickshell-qt")"
qt x --qt-stale && fail "Qt installed with Quickshell taken for a new Qt"
echo "qt6-base 6.9.0 qt6-declarative 6.9.0 " >"$t/state/quickshell-qt"
qt x --qt-mark
[[ $(cat "$t/state/quickshell-qt") == "qt6-base 6.9.0 qt6-declarative 6.9.0 " ]] || fail "--qt-mark overwrote a full stamp"
# From the Updates app (no terminal): the AUR apps it builds without a review of their build scripts said first
# shellcheck disable=SC2016  # (expanded by the stand-in)
stub paru 'case "$*" in *-Qua*) echo "equibop 1.0-1 -> 1.1-1"; echo "held 1-1 -> 2-1 [ignored]" ;; *) echo "paru $*" >>"'"$t"'/paru" ;; esac'
out=$(HOME=$t/home XDG_STATE_HOME=$t/state XDG_CACHE_HOME=$t/home/.cache PATH=$t/bin:$PATH "$here/.local/bin/update-apps" </dev/null 2>&1) || true
grep -q "AUR apps built now, their build scripts not reviewed.*: equibop$" <<<"$out" ||
    fail "the AUR apps built without review not listed: $(head -5 <<<"$out")"
# (that list not made, the AUR not reached: said, not taken for "none"; none to build: nothing said)
# shellcheck disable=SC2016
stub paru 'case "$*" in *-Qua*) echo "error: failed to get AUR info" >&2; exit 1 ;; *) echo "paru $*" >>"'"$t"'/paru" ;; esac'
out=$(HOME=$t/home XDG_STATE_HOME=$t/state XDG_CACHE_HOME=$t/home/.cache PATH=$t/bin:$PATH "$here/.local/bin/update-apps" </dev/null 2>&1) || true
grep -q "couldn't be listed (paru -Qua: error: failed to get AUR info)" <<<"$out" ||
    fail "paru -Qua failing not said: $(head -5 <<<"$out")"
# shellcheck disable=SC2016
stub paru 'case "$*" in *-Qua*) exit 1 ;; *) echo "paru $*" >>"'"$t"'/paru" ;; esac'
out=$(HOME=$t/home XDG_STATE_HOME=$t/state XDG_CACHE_HOME=$t/home/.cache PATH=$t/bin:$PATH "$here/.local/bin/update-apps" </dev/null 2>&1) || true
grep -qE "couldn't be listed|built now, their build" <<<"$out" && fail "no AUR updates said as a list or a failure: $(head -5 <<<"$out")"
grep -q -- "--what=sleep:shutdown --mode=block .*tail --pid=" "$t/inhibit" ||
    fail "the install not held against power off and sleep: $(cat "$t/inhibit" 2>/dev/null)"
echo "ok update-apps"
