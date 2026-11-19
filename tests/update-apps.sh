#!/usr/bin/env bash
# update-apps --list (the package tools stubbed): each kind's updates in one form, ignored AUR ones left out, and the
# package servers out of reach an "offline" line instead of an empty list that reads as up to date
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
# (the batteries battery-low reads: none, but where a test makes them; never this machine's own)
export AGROS_POWER_SUPPLY=$t/ps
mkdir -p "$t/bin" "$t/home"
stub() { printf '#!/bin/sh\n%s\n' "$2" >"$t/bin/$1"; chmod +x "$t/bin/$1"; }
# (checkupdates syncs its copy of the lists; what's waiting is pacman's -Qu on it, through the upstream gate: $t/qu)
stub checkupdates 'exit 0'
# (the system booted as itself: CI's container root is an overlay, which reads as a booted snapshot)
stub findmnt 'echo btrfs'
stub pacman '[ "$1" = -Qu ] && cat '"$t"'/qu 2>/dev/null; true'
echo "linux 6.1-1 -> 6.2-1" >"$t/qu"
# (paru translates its "[ignored]": in Portuguese it's "[ignorado]")
stub paru 'echo "equibop 1.0-1 -> 1.1-1"; [ "${LC_ALL:-}" = C ] && echo "held 1-1 -> 2-1 [ignored]" || echo "held 1-1 -> 2-1 [ignorado]"'
stub flatpak '[ "$1" = remote-ls ] && printf "com.spotify.Client\t1.3\n"; [ "$1" = info ] && echo "  Version: 1.2"; true'
# (this machine's firmware, developer tools and Proton builds aren't the test's: update-kinds' own test has them)
for c in fwupdmgr rustup npm pipx; do stub "$c" 'exit 2'; done
run() { HOME=$t/home PATH=$t/bin:$PATH "$here/.local/bin/update-apps" --list; }
out=$(run)
want=$(printf 'system\tlinux\t6.1-1\t6.2-1\naur\tequibop\t1.0-1\t1.1-1\nflatpak\tcom.spotify.Client\t1.2\t1.3')
[[ $out == "$want" ]] || fail "the list: $out"
stub checkupdates 'exit 1'
[[ $(run) == offline* ]] || fail "offline not said: $(run)"
stub checkupdates 'exit 2'; stub paru 'true'; stub flatpak 'true'; : >"$t/qu"
[[ -z $(run) ]] || fail "nothing waiting, still listed: $(run)"

# --check: a notification left unclicked until the next check (its timeout) still counts as announced; one the
# notification server dropped (Caelestia restarted under it) doesn't
stub checkupdates 'exit 0'; echo "linux 6.1-1 -> 6.2-1" >"$t/qu"
stub timeout 'shift; exec /usr/bin/timeout 1 "$@"'  # (5h50m: a second here)
mkdir -p "$t/home/.local/bin" "$t/home/.cache"
seen=$t/home/.cache/update-apps-notified
check() { HOME=$t/home XDG_CACHE_HOME=$t/home/.cache PATH=$t/bin:$PATH "$here/.local/bin/update-apps" --check; }
# (notify-wait's own tools: the notification, and D-Bus' watch for the server going away, which never comes here)
stub gdbus 'exec sleep 60'
stub notify-send 'exit 143'
stub id 'echo users wheel'  # (an admin's: only they can update)
check
[[ ! -e $seen ]] || fail "a notification the server dropped noted as announced"
stub notify-send 'exec sleep 30'
check
[[ $(cat "$seen" 2>/dev/null) == linux ]] || fail "an unclicked notification (its time ran out) not noted: announced again every check"
# An account that can't sudo (not in wheel): no "Update now" offered (it only failed); the boot's update covers it
rm -f "$seen"; stub id 'echo users'; stub notify-send 'echo sent >>"'"$t"'/sent"'
check
[[ ! -e $t/sent ]] || fail "\"Update now\" offered to an account that can't sudo"
# ...nor an update tried there (it failed at sudo, part of the way in): said, a failure
stub paru 'echo "paru $*" >>"'"$t"'/paru"'
out=$(HOME=$t/home XDG_STATE_HOME=$t/state XDG_CACHE_HOME=$t/home/.cache PATH=$t/bin:$PATH "$here/.local/bin/update-apps" \
    </dev/null 2>&1) && fail "an update by an account that can't sudo reported success"
[[ ! -e $t/paru && $out == "Only an administrator can install updates"* ]] ||
    fail "an update tried by an account that can't sudo, or not said: $out / $(cat "$t/paru" 2>/dev/null)"
stub id 'echo users wheel'  # (an admin's, from here on)

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
# Around a pacman -Syu, between update-apps --qt-mark and --qt-rebuild: a new Qt rebuilds Quickshell and Caelestia
# (only those installed, as the Updates app does), and the new Qt is written down; Qt unchanged: nothing rebuilt
rm -f "$t/paru" "$t/state/quickshell-qt"
# shellcheck disable=SC2016  # (expanded by the stub)
# (what's built on Qt: Quickshell and Caelestia, from the AUR; darkly-bin, prebuilt; kconfig, a repo's)
stub pacman 'case "$1 $2" in "-Q qt6-base" | "-Q qt6-declarative") echo "$2 $QT-1" ;; "-Q quickshell-git" | "-Q caelestia-shell") true ;;
    -Qi*) echo "Required By     : quickshell-git  caelestia-shell darkly-bin kconfig"; echo "Optional For    : None" ;;
    "-Qm quickshell-git" | "-Qm caelestia-shell" | "-Qm darkly-bin") true ;; *) exit 1 ;; esac'
qt() { QT=$1 HOME=$t/home XDG_STATE_HOME=$t/state PATH=$t/bin:$PATH "$here/.local/bin/update-apps" "$2" </dev/null; }
{ qt 6.9.0 --qt-mark && qt 6.9.0 --qt-rebuild; } || fail "--qt-mark/--qt-rebuild with Qt unchanged failed"
[[ ! -e $t/paru ]] || fail "rebuilt with Qt unchanged: $(cat "$t/paru")"
qt 6.10.0 --qt-rebuild >/dev/null || fail "the rebuild for a new Qt failed"
grep -q -- "-S --rebuild --noconfirm aur/caelestia-shell aur/quickshell-git$" "$t/paru" || fail "not rebuilt for the new Qt: $(cat "$t/paru" 2>/dev/null)"
[[ $(cat "$t/state/quickshell-qt") == "qt6-base 6.10.0 qt6-declarative 6.10.0 " ]] || fail "the new Qt not written down"
# [agros]'s own (Quickshell, built there with AgrOS's fix) rebuilt as the boot's rebuild does it: the AUR's build files
# of the version installed, AgrOS's fix added (auto-update-aur --fetch), built from them; never paru -S's, the AUR's
# newest without the fix. The AUR's own (not in [agros]) still by paru -S
rm -f "$t/paru" "$t/state/quickshell-qt"
# shellcheck disable=SC2016  # (expanded by the stubs)
stub pacman 'case "$1 $2" in "-Q qt6-base" | "-Q qt6-declarative") echo "$2 $QT-1" ;; "-Q quickshell-git") echo "quickshell-git 0.2.1.r5.gabc1234-1.2" ;;
    "-Q caelestia-shell") true ;; -Qi*) echo "Required By     : quickshell-git  caelestia-shell"; echo "Optional For    : None" ;;
    "-Slq agros") echo quickshell-git ;; "-Qm caelestia-shell") true ;; *) exit 1 ;; esac'
stub curl 'echo "{\"results\":[{\"PackageBase\":\"quickshell-git\"}]}"'
# shellcheck disable=SC2016
stub paru 'echo "paru $* in ${PWD##*/}" >>"'"$t"'/paru"'
# shellcheck disable=SC2016
stub auto-update-aur 'echo "$*" >>"'"$t"'/fetch"; [ "$1" = --fetch ] && mkdir -p "$2/${3%%=*}"'
export AUTO_UPDATE_AUR=$t/bin/auto-update-aur
# (a build folder a run cut off left, hours old, taken away; one of a run going on now, and anything else there, kept)
mkdir -p "$t/home/.cache/agros-rebuild.OLDone/quickshell-git" "$t/home/.cache/agros-rebuild.NEWone" "$t/home/.cache/agros-rebuild-mine"
touch -d '7 hours ago' "$t/home/.cache/agros-rebuild.OLDone" "$t/home/.cache/agros-rebuild-mine"
qt 6.9.0 --qt-mark && qt 6.10.0 --qt-rebuild >/dev/null || fail "the rebuild of [agros]'s own for a new Qt failed"
[[ ! -e $t/home/.cache/agros-rebuild.OLDone && -d $t/home/.cache/agros-rebuild.NEWone && -d $t/home/.cache/agros-rebuild-mine ]] ||
    fail "a build folder a cut-off run left not taken away, or another one taken: $(ls -A "$t/home/.cache")"
rm -rf "$t/home/.cache/agros-rebuild.NEWone" "$t/home/.cache/agros-rebuild-mine"
grep -q -- "^--fetch $t/home/.cache/agros-rebuild\.[^ ]* quickshell-git=0.2.1.r5.gabc1234-1.2$" "$t/fetch" ||
    fail "[agros]'s Quickshell not fetched at its version installed, with AgrOS's fix: $(cat "$t/fetch" 2>/dev/null)"
grep -q -- "-Ui --noconfirm in quickshell-git$" "$t/paru" && ! grep -q "aur/quickshell-git" "$t/paru" ||
    fail "[agros]'s Quickshell not built from those build files: $(cat "$t/paru")"
grep -q -- "-S --rebuild --noconfirm aur/caelestia-shell in" "$t/paru" || fail "the AUR's own not rebuilt: $(cat "$t/paru")"
[[ -z $(compgen -G "$t/home/.cache/agros-rebuild.*") ]] || fail "the rebuild's build folder left behind"
unset AUTO_UPDATE_AUR; rm "$t/bin/curl"
# Part of Qt not installed (an edition without qt6-declarative): --qt-mark doesn't fail, the stamp names each one
# ("none"), and nothing is rebuilt with Qt unchanged
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
# Marked again once Qt is in: a stamp naming a package that wasn't installed
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
# Those the boot's builds hold for review (auto-update-aur's guard: a base whose AUR maintainers changed, named by
# its aur-maintainer-changed, its split packages too; a signed repository's package now foreign) never built
# unreviewed from the Updates app (the next boot took those maintainers as reviewed): left out (paru's --ignore), said
# with how to review them; the others built as before
mkdir -p "$t/au" "$t/pacdb/local/libfoo-1-1"
echo "foo malloryb: 1-1" >"$t/au/aur-maintainer-changed"
printf '%%NAME%%\nlibfoo\n\n%%BASE%%\nfoo\n' >"$t/pacdb/local/libfoo-1-1/desc"
stub pacman 'case "$1" in -Qm) printf "%s\n" "libfoo 1-1" "equibop 1.0-1" "oldrepo 1-1" ;;
    -Qmi) printf "%s\n" "Name            : equibop" "Validated By    : None" "Name            : oldrepo" "Validated By    : Signature" ;; esac; true'
# shellcheck disable=SC2016  # (expanded by the stand-in)
stub paru 'case "$*" in *-Qua*) printf "%s\n" "equibop 1.0-1 -> 1.1-1" "libfoo 1-1 -> 2-1" "oldrepo 1-1 -> 2-1" ;; *) echo "paru $*" >>"'"$t"'/paru" ;; esac'
rm -f "$t/paru"
out=$(HOME=$t/home XDG_STATE_HOME=$t/state XDG_CACHE_HOME=$t/home/.cache AUTO_UPDATE_DIR=$t/au PACMAN_DB_DIR=$t/pacdb \
    PATH=$t/bin:$PATH "$here/.local/bin/update-apps" </dev/null 2>&1) || true
grep -q "AUR apps built now, their build scripts not reviewed.*: equibop$" <<<"$out" ||
    fail "those held for review listed as built, or the others not: $(grep AUR <<<"$out")"
grep -q "held for review .*: libfoo oldrepo\. To review them: run update-apps in a terminal" <<<"$out" ||
    fail "those held for review not said, or not how to review them: $(grep -i held <<<"$out")"
grep -q -- " -Su --noconfirm --ignore libfoo,oldrepo$" "$t/paru" || fail "those held for review built unreviewed: $(cat "$t/paru")"
rm -r "$t/au" "$t/pacdb"
# (the lid too: logind suspends on it whatever sleep lock is held, LidSwitchIgnoreInhibited=yes, but for that one)
grep -q -- "--what=sleep:shutdown:handle-lid-switch --mode=block .*tail --pid=" "$t/inhibit" ||
    fail "the install not held against power off, sleep and the lid: $(cat "$t/inhibit" 2>/dev/null)"
# (the lid's lock refused, polkit's: power off and sleep held all the same)
# shellcheck disable=SC2016
stub systemd-inhibit 'case "$1" in *handle-lid-switch*) exit 1 ;; esac; echo "inhibit $*" >>"'"$t"'/inhibit"; while [ "${1#--}" != "$1" ]; do shift; done; exec "$@"'
rm -f "$t/inhibit"
HOME=$t/home XDG_STATE_HOME=$t/state XDG_CACHE_HOME=$t/home/.cache PATH=$t/bin:$PATH "$here/.local/bin/update-apps" \
    </dev/null >/dev/null 2>&1 || true
grep -q -- "--what=sleep:shutdown --mode=block .*tail --pid=" "$t/inhibit" ||
    fail "the lid's lock refused, power off and sleep not held either: $(cat "$t/inhibit" 2>/dev/null)"
# The boot's run (auto-update active) still to download what its AUR builds need (its "downloading" mark): waited for,
# paru not run until the mark is gone (both writing pacman's cache at once would corrupt it)
mkdir -p "$t/au"; touch "$t/au/downloading"; rm -f "$t/paru"
stub systemctl 'true'
stub sleep 'exec /usr/bin/sleep 0.1'  # (its 5 s between looks)
HOME=$t/home XDG_STATE_HOME=$t/state XDG_CACHE_HOME=$t/home/.cache AUTO_UPDATE_DIR=$t/au PATH=$t/bin:$PATH \
    "$here/.local/bin/update-apps" </dev/null >"$t/wait-out" 2>&1 &
/usr/bin/sleep 1
[[ ! -e $t/paru ]] || fail "paru run while the boot's run still downloads: $(cat "$t/paru")"
grep -q "Waiting for the update started at boot" "$t/wait-out" || fail "the wait not said: $(cat "$t/wait-out")"
rm "$t/au/downloading"
wait || true
# (its lists synced, then the update through the upstream gate's pacman.conf: update-gate's)
{ grep -q -- " -Sy --noconfirm$" "$t/paru" && grep -qE -- " --config [^ ]+ -Su --noconfirm( --ignore [^ ]+)?$" "$t/paru"; } ||
    fail "paru not run once the boot's download was done, through the gate: $(cat "$t/paru" 2>/dev/null)"
rm "$t/bin/sleep"
# A newer keyring waiting (weeks offline): installed first, on its own, then the rest (a package signed with a key the
# keyring here lacks failed the whole update); one pacman.conf holds back ("[ignored]") left out
rm -f "$t/paru"; stub systemctl 'exit 1'
stub pacman 'case "$1" in -Qu) printf "%s\n" "linux 6.1-1 -> 6.2-1" "archlinux-keyring 1-1 -> 2-1" "cachyos-keyring 1-1 -> 2-1 [ignored]" ;; esac; true'
HOME=$t/home XDG_STATE_HOME=$t/state XDG_CACHE_HOME=$t/home/.cache PATH=$t/bin:$PATH "$here/.local/bin/update-apps" \
    </dev/null >/dev/null 2>&1 || true
keys=$(grep -n -- " --config [^ ]* -S --needed --noconfirm archlinux-keyring$" "$t/paru" | cut -d: -f1)
su=$(grep -n -- " -Su --noconfirm$" "$t/paru" | cut -d: -f1)
[[ -n $keys && -n $su ]] && ((keys < su)) || fail "the newer keyring not installed first, on its own: $(cat "$t/paru")"
# The packages AgrOS dropped (agros-system's retired list) removed after the update, through paru (its sudo): only
# those in as a dependency that nothing needs (pacman -Qdtq); one installed by hand, or still needed, kept. A removal
# failing doesn't fail the update, said
printf '%s\n' '# AgrOS dropped these' qview gone-too >"$t/retired"
update() { AGROS_RETIRED=$t/retired HOME=$t/home XDG_STATE_HOME=$t/state XDG_CACHE_HOME=$t/home/.cache PATH=$t/bin:$PATH \
    "$here/.local/bin/update-apps" </dev/null 2>&1; }
stub pacman 'case "$1" in -Qdtq) printf "%s\n" libfoo qview ;; esac; true'
rm -f "$t/paru"; update >/dev/null || true
[[ $(grep -oE -- " -(Su|Rns) --noconfirm( qview)?$" "$t/paru" | paste -sd,) == " -Su --noconfirm, -Rns --noconfirm qview" ]] ||
    fail "not just the dropped orphan removed, after the update: $(cat "$t/paru")"
stub pacman 'case "$1" in -Qdtq) echo libfoo ;; esac; true'
rm -f "$t/paru"; update >/dev/null || true
grep -q -- -Rns "$t/paru" && fail "a package removed that was installed by hand or is needed: $(cat "$t/paru")"
stub pacman 'case "$1" in -Qdtq) echo qview ;; esac; true'
stub paru 'echo "paru $*" >>"'"$t"'/paru"; case "$*" in *" -Rns "*) exit 1 ;; esac'
mv "$t/bin/timeout" "$t/timeout"  # (the real one: the Flatpaks' step fails with the stand-in's)
rc=0; out=$(update) || rc=$?
[[ $rc == 0 && $out == *"!! Not removed (qview)"* ]] || fail "a failed removal failed the update, or wasn't said: $rc $out"
stub paru 'echo "paru $*" >>"'"$t"'/paru"'
mv "$t/timeout" "$t/bin/timeout"; rm "$t/retired"
# On a battery nearly empty (a laptop off its charger, below 15%): nothing installed (a power cut mid-install leaves
# packages half in), said, a failure for the Updates app; on its charger, updated
mkdir -p "$t/ps/BAT0"; echo Battery >"$t/ps/BAT0/type"; echo 9 >"$t/ps/BAT0/capacity"; echo Discharging >"$t/ps/BAT0/status"
rm -f "$t/paru"
out=$(HOME=$t/home XDG_STATE_HOME=$t/state XDG_CACHE_HOME=$t/home/.cache PATH=$t/bin:$PATH "$here/.local/bin/update-apps" \
    </dev/null 2>&1) && fail "an update on a nearly empty battery reported success"
[[ ! -e $t/paru && $out == *"nearly empty (9 percent): nothing updated"* ]] ||
    fail "updated on a nearly empty battery, or not said: $out / $(cat "$t/paru" 2>/dev/null)"
echo Charging >"$t/ps/BAT0/status"
HOME=$t/home XDG_STATE_HOME=$t/state XDG_CACHE_HOME=$t/home/.cache PATH=$t/bin:$PATH "$here/.local/bin/update-apps" \
    </dev/null >/dev/null 2>&1 || true
grep -q -- " -Su --noconfirm$" "$t/paru" || fail "not updated on a low battery that's charging: $(cat "$t/paru" 2>/dev/null)"
rm -r "$t/ps"
# A booted snapshot (its root an overlay in RAM) or the live USB: nothing updated (gone at the next boot), said, a
# failure for the Updates app; and no update offered by --check
stub findmnt 'echo overlay'; rm -f "$t/paru" "$t/sent"
out=$(HOME=$t/home XDG_STATE_HOME=$t/state XDG_CACHE_HOME=$t/home/.cache PATH=$t/bin:$PATH "$here/.local/bin/update-apps" \
    </dev/null 2>&1) && fail "an update from a snapshot reported success"
[[ ! -e $t/paru && $out == *"runs from a snapshot"*"nothing updated"* ]] ||
    fail "updated from a snapshot, or not said: $out / $(cat "$t/paru" 2>/dev/null)"
stub id 'echo users wheel'; rm -f "$seen"; echo "linux 6.1-1 -> 6.2-1" >"$t/qu"
stub pacman '[ "$1" = -Qu ] && cat '"$t"'/qu 2>/dev/null; true'
check
[[ ! -e $t/sent && ! -e $seen ]] || fail "an update offered from a snapshot"
stub findmnt 'echo btrfs'
check
[[ -e $t/sent ]] || fail "test setup: no update offered from the system itself either"

# A new Python (3.13 to 3.14) from its paru -Su: the AUR's packages in the old folder (python-foo) rebuilt, as the
# boot's AUR builds do (update-kinds' one list), not the repo's; a Python bugfix release rebuilds nothing
# shellcheck disable=SC2016  # (expanded by the stand-ins)
stub paru 'echo "paru $*" >>"'"$t"'/paru"; case "$*" in *" -Su "*) echo "$PY_NEW" >"'"$t"'/py" ;; esac'
# shellcheck disable=SC2016
stub pacman 'case "$1 $2" in "-Q python") echo "python $(cat "'"$t"'/py")" ;; "-Q qt6-base" | "-Q qt6-declarative") echo "$2 6.9.0-1" ;;
    "-Qoq /usr/lib/python3.13/") printf "%s\n" python-foo python-repo ;; "-Qm python-foo") true ;; *) exit 1 ;; esac'
for v in 3.14.0-1 3.13.8-1; do
    echo 3.13.7-1 >"$t/py"; rm -f "$t/paru"
    PY_NEW=$v HOME=$t/home XDG_STATE_HOME=$t/state XDG_CACHE_HOME=$t/home/.cache PATH=$t/bin:$PATH \
        "$here/.local/bin/update-apps" </dev/null >/dev/null 2>&1 || true
    if [[ $v == 3.14* ]]; then
        grep -q -- "-S --rebuild --noconfirm aur/python-foo$" "$t/paru" || fail "the AUR's Python package not rebuilt for a new Python: $(cat "$t/paru")"
    else
        grep -q -- --rebuild "$t/paru" && fail "rebuilt for a Python bugfix release: $(cat "$t/paru")"
    fi
done

# Run in a terminal: how it went said where it waits for a key, as the Updates app says it. A step that failed (its
# error scrolled away above) isn't "Done.", which read as everything updated; all of it working is
if scr=$(command -v script); then
    rm -f "$t/bin/timeout"  # (the real one: its time limits as they are)
    # (in a terminal of its own, script's, a key pressed every second: the one it waits for at the end)
    term() {
        while sleep 1; do printf x; done |
            /usr/bin/timeout -s KILL 60 env HOME="$t/home" XDG_STATE_HOME="$t/state" XDG_CACHE_HOME="$t/home/.cache" \
                PATH="$t/bin:$PATH" SHELL=/bin/bash "$scr" -qec "$here/.local/bin/update-apps" /dev/null 2>&1
        return "${PIPESTATUS[1]}"  # (update-apps', through script: not the keys', cut off as it ends)
    }
    stub paru 'exit 1'
    out=$(term) && fail "a failed update in a terminal exited 0"
    [[ $out == *"Finished, with problems"* && $out != *"Done."* ]] ||
        fail "a failed update said as done in a terminal: $(tail -3 <<<"$out")"
    stub paru 'true'
    out=$(term) || fail "an update with nothing failing failed in a terminal: $(tail -5 <<<"$out")"
    [[ $out == *"Done. Press any key"* && $out != *"with problems"* ]] ||
        fail "an update with nothing failing not said as done in a terminal: $(tail -3 <<<"$out")"
else
    skipped "no script(1): the run in a terminal not tried"
fi
echo "ok update-apps"
