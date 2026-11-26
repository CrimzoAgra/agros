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
# (Quickshell built for the Qt here, whatever this machine's own says: update-kinds --qt-mismatch)
stub quickshell 'exit 0'
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
# (its time a second here, but one the real timeout takes: "5h50m" it refused, and nothing was ever offered)
stub timeout 'd=$1; shift; /usr/bin/timeout "$d" true || exit 125; exec /usr/bin/timeout 1 "$@"'
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
# Clicked: Settings' Updates opened (Caelestia's nexus updates) with what the check found (a file in your runtime
# folder), not checking again; --check's "Update now" starting the update, --check-now's (the Super menu's button) only
# opening it
stub notify-send 'echo default'
stub qs '[ "$*" = "-c caelestia ipc call nexus updates $7 $8" ] && echo "$7 $(cat "$8")" >'"$t"'/opened'
mkdir -p "$t/run"; rm -f "$seen"
XDG_RUNTIME_DIR=$t/run check
[[ $(cat "$t/opened" 2>/dev/null) == "true "$'system\tlinux\t6.1-1\t6.2-1' ]] ||
    fail "\"Update now\" didn't hand Settings what the check found: $(cat "$t/opened" 2>/dev/null)"
rm -f "$t/opened" "$t/run"/*
XDG_RUNTIME_DIR=$t/run HOME=$t/home XDG_CACHE_HOME=$t/home/.cache PATH=$t/bin:$PATH "$here/.local/bin/update-apps" --check-now
for _ in $(seq 50); do [[ -s $t/opened ]] && break; sleep 0.1; done
[[ $(cat "$t/opened" 2>/dev/null) == "false "$'system\tlinux\t6.1-1\t6.2-1' ]] ||
    fail "the Super menu's check didn't hand Settings what it found: $(cat "$t/opened" 2>/dev/null)"
rm -rf "$t/opened" "$t/run" "$t/bin/qs"
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
# Nor "Update now" while an update's install, carried on past a logout, is still going (paru-sudo's unit); once it's
# done, offered
rm -f "$seen" "$t/sent"; stub systemctl '[ "$*" = "is-active -q agros-pacman" ]'
check
[[ ! -e $t/sent ]] || fail "\"Update now\" offered while an install carried on past a logout"
rm "$t/bin/systemctl"
check
[[ -e $t/sent ]] || fail "\"Update now\" not offered once that install was done"
rm -f "$seen" "$t/sent"

# paru's sudo (paru-sudo, every paru of the update's): pacman run as root in a system unit of its own (agros-pacman:
# logging out, which ends every process of yours, doesn't cut it off), its output the caller's (--pipe), power off,
# sleep and the lid held off in it, its exit pacman's; sudo's options (-A, askpass) kept. Anything else (paru's sudo
# -v) sudo's own. Stand-ins: sudo, systemd-run and systemd-inhibit note what they're given and run it
# shellcheck disable=SC2016  # (expanded by the stand-ins)
for c in sudo systemd-run systemd-inhibit; do
    printf '#!/bin/sh
echo "%s $*" >>%s/ps
while [ "${1#-}" != "$1" ]; do shift; done
exec "$@"
' "$c" "$t" >"$t/ps-$c"
done
mkdir -p "$t/ps-bin"
for c in sudo systemd-run systemd-inhibit; do mv "$t/ps-$c" "$t/ps-bin/$c"; done
printf '#!/bin/sh
echo "pacman $*"
exit 3
' >"$t/ps-bin/pacman"
chmod +x "$t/ps-bin/"*
rc=0; out=$(PATH=$t/ps-bin:$PATH "$here/.local/bin/paru-sudo" -A pacman -Su --noconfirm) || rc=$?
[[ $rc == 3 && $out == "pacman -Su --noconfirm" ]] || fail "paru-sudo's pacman not run, or its exit not pacman's: $rc $out"
grep -q "^sudo -A systemd-run --unit=agros-pacman .*--pipe .*systemd-inhibit " "$t/ps" &&
    grep -q "^systemd-inhibit --what=sleep:shutdown:handle-lid-switch --mode=block .* pacman -Su --noconfirm$" "$t/ps" ||
    fail "pacman not run in its own system unit, power off and sleep held: $(cat "$t/ps")"
rm "$t/ps"
PATH=$t/ps-bin:$PATH "$here/.local/bin/paru-sudo" -A -v
[[ $(cat "$t/ps") == "sudo -A -v" ]] || fail "paru's sudo -v not sudo's own: $(cat "$t/ps")"
rm -r "$t/ps" "$t/ps-bin"

# Your password once for the whole run (no terminal: the Updates app): asked again when it was wrong, then every sudo
# of the run (each paru's) given it by askpass with no dialog, and its copy gone once the run ends. Cancelled: nothing
stub sudo 'case "$1" in -n) exit 1 ;; -S) read -r p; [ "$p" = right ] ;; esac'
stub zenity 'n=$(cat '"$t"'/asked 2>/dev/null || echo 0); echo $((n + 1)) >'"$t"'/asked; [ "$n" = 0 ] && echo wrong || echo right'
stub paru 'echo "paru $*" >>"'"$t"'/paru"; "$SUDO_ASKPASS" >>"'"$t"'/given"'
mkdir -p "$t/run"
pw_update() { XDG_RUNTIME_DIR=$t/run HOME=$t/home XDG_STATE_HOME=$t/state-pw XDG_CACHE_HOME=$t/home/.cache PATH=$t/bin:$PATH \
    "$here/.local/bin/update-apps" </dev/null 2>&1; }
pw_update >/dev/null || true
[[ $(cat "$t/asked") == 2 ]] || fail "the password not asked once more after a wrong one, or asked again: $(cat "$t/asked") dialogs"
[[ $(grep -c . "$t/given") -ge 2 && $(sort -u "$t/given") == right ]] ||
    fail "a sudo of the run not given the password without a dialog: $(cat "$t/given" 2>/dev/null)"
[[ -z $(ls -A "$t/run") ]] || fail "the run's password left behind: $(ls -A "$t/run")"
stub zenity 'exit 1'; rm -f "$t/paru"
out=$(pw_update) && fail "an update with no password given reported success"
[[ ! -e $t/paru && $out == *"no password given"* ]] || fail "updated with the dialog cancelled, or not said: $out"
stub sudo 'exit 0'  # (from here on: sudo asks for none, as with NOPASSWD)
stub paru 'echo "paru $*" >>"'"$t"'/paru"'
rm -rf "$t/paru" "$t/given" "$t/asked" "$t/run" "$t/state-pw"

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
grep -q -- "^paru --sudoloop --sudo $here/.local/bin/paru-sudo .*-Sy " "$t/paru" && ! grep -v -- "-Qua$\|--sudo $here/.local/bin/paru-sudo " "$t/paru" ||
    fail "the update's paru not given paru-sudo as its sudo: $(cat "$t/paru")"
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
stub auto-update-aur 'echo "$*" >>"'"$t"'/fetch"; [ "$1" = --fetch ] && mkdir -p "$2/${3%%=*}" &&
    printf "pkgrel=1\npkgrel+=.2\n" >"$2/${3%%=*}/PKGBUILD"'
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
# One CI relabelled (1.2.1, a release makepkg can't make): not built here at an older one, said; nothing else changes
rm -f "$t/paru" "$t/state/quickshell-qt"
sed -i 's/0.2.1.r5.gabc1234-1.2"/0.2.1.r5.gabc1234-1.2.1"/' "$t/bin/pacman"
out=$(qt 6.9.0 --qt-mark && qt 6.10.0 --qt-rebuild 2>&1) && fail "a relabelled rebuild left out reported success"
[[ $out == *"quickshell-git: its version installed, 0.2.1.r5.gabc1234-1.2.1, is AgrOS's own rebuild"* ]] &&
    ! grep -q -- "-Ui .* in quickshell-git$" "$t/paru" || fail "CI's relabelled Quickshell rebuilt at an older release: $out"
# ...but the one [agros] has now (its rebuild for this Qt): nothing to do, not left out, the Qt written down (counted as
# left out, agros-check said at every login that Quickshell wasn't built for the Qt installed)
rm -f "$t/paru" "$t/state/quickshell-qt"
sed -i 's/"-Slq agros") echo quickshell-git ;;/"-Slq agros") echo quickshell-git ;; "-Sl agros") echo "agros quickshell-git 0.2.1.r5.gabc1234-1.2.1 [installed]" ;;/' "$t/bin/pacman"
grep -q '"-Sl agros")' "$t/bin/pacman" || fail "the test's pacman stub not given [agros]'s list"
out=$(qt 6.9.0 --qt-mark && qt 6.10.0 --qt-rebuild 2>&1) || fail "[agros]'s own rebuild installed, for this Qt: reported as left out: $out"
grep -q 'qt6-base 6.10.0' "$t/state/quickshell-qt" && ! grep -q -- "-Ui .* in quickshell-git$" "$t/paru" 2>/dev/null ||
    fail "[agros]'s own rebuild installed: the Qt not written down, or rebuilt: $(cat "$t/state/quickshell-qt" 2>/dev/null)"
sed -i 's/ "-Sl agros") echo "agros quickshell-git 0.2.1.r5.gabc1234-1.2.1 \[installed\]" ;;//' "$t/bin/pacman"
sed -i 's/0.2.1.r5.gabc1234-1.2.1"/0.2.1.r5.gabc1234-1.2"/' "$t/bin/pacman"
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
# (Quickshell's own check saying it wasn't built for the Qt here, the stamp agreeing all the same: stale too)
stub quickshell '[ "$1" = --private-check-compat ] && exit 1; exit 0'
qt x --qt-stale || fail "--qt-stale doesn't take Quickshell's own check failing"
stub quickshell 'exit 0'
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
stub systemctl '[ "$*" = "is-active -q auto-update" ]'  # (the boot's run active; no install past a logout)
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
stub pacman 'case "$1 $2" in "-Q python" | "-Q ") echo "python $(cat "'"$t"'/py")" ;; "-Q qt6-base" | "-Q qt6-declarative") echo "$2 6.9.0-1" ;;
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

# A new Qt and [agros]'s Quickshell rebuilt for it (CI's, relabelled 1.1) in the same paru -Su: that one not built again
# here (at the AUR's release, older than CI's, it was refused, and every run ended "with problems", the Qt not written
# down), as the boot's builds skip one their download brings; the Qt written down
# shellcheck disable=SC2016  # (expanded by the stand-ins)
stub paru 'echo "paru $*" >>"'"$t"'/paru"; case "$*" in *" -Su "*) touch "'"$t"'/qt-new" ;; esac'
# shellcheck disable=SC2016
stub pacman 'qt=6.9.0-1 qs=0.2.1-1; [ -e "'"$t"'/qt-new" ] && qt=6.10.0-1 qs=0.2.1-1.1
    case "$1 $2" in "-Q ") printf "%s\n" "qt6-base $qt" "qt6-declarative $qt" "quickshell-git $qs" ;;
    "-Q qt6-base" | "-Q qt6-declarative") echo "$2 $qt" ;; "-Q quickshell-git") echo "quickshell-git $qs" ;;
    -Qi*) echo "Required By     : quickshell-git"; echo "Optional For    : None" ;; "-Slq agros") echo quickshell-git ;; *) exit 1 ;; esac'
stub auto-update-aur 'echo "$*" >>"'"$t"'/fetch"; exit 1'
echo "qt6-base 6.9.0 qt6-declarative 6.9.0 " >"$t/state/quickshell-qt"; rm -f "$t/paru" "$t/fetch" "$t/qt-new"
out=$(AUTO_UPDATE_AUR=$t/bin/auto-update-aur HOME=$t/home XDG_STATE_HOME=$t/state XDG_CACHE_HOME=$t/home/.cache \
    PATH=$t/bin:$PATH "$here/.local/bin/update-apps" </dev/null 2>&1) || true
[[ ! -e $t/fetch && $out != *"quickshell-git"* ]] || fail "[agros]'s Quickshell its repo rebuilt in the same run built again: $out"
[[ $(cat "$t/state/quickshell-qt") == "qt6-base 6.10.0 qt6-declarative 6.10.0 " ]] ||
    fail "the new Qt not written down after its repo's rebuild came with it: $(cat "$t/state/quickshell-qt")"
rm -f "$t/bin/auto-update-aur" "$t/qt-new"
stub paru 'echo "paru $*" >>"'"$t"'/paru"'

# AgrOS's own update code first (update-first): the lists synced with a newer agros-scripts or agros-system, those
# installed alone, then the run started again with the new code (its arguments, its password), which decides the
# update, once. None newer: no such step. Its install failing, or needing more than itself (a newer library): said, and
# the update goes on with the code it has. (update-apps a copy beside the helpers, which the install replaces)
mkdir -p "$t/ua" "$t/tmp"
for f in "$here"/.local/bin/*; do ln -s "$f" "$t/ua/"; done
rm "$t/ua/update-apps"; cp "$here/.local/bin/update-apps" "$t/ua/update-apps.old"
# (-Qu: $FIRST_QU waiting; -Sp: what installing the targets takes, them and $FIRST_NEEDS)
# shellcheck disable=SC2016  # (expanded by the stand-in)
stub pacman 'case "$1" in -Qu) echo "linux 6.1-1 -> 6.2-1"; [ -z "$FIRST_QU" ] || printf "%s\n" "$FIRST_QU" ;;
    -Sp) while [ "$1" != -- ]; do shift; done; shift; for a; do echo "${a#agros/}"; done; [ -z "$FIRST_NEEDS" ] || echo "$FIRST_NEEDS" ;; esac; true'
# (paru -S of them: the new update-apps in place, a new file as pacman's, saying it ran; $FIRST_RC: it fails)
cat >"$t/bin/paru" <<EOF
#!/bin/sh
echo "paru \$*" >>"$t/paru"
case "\$*" in *" -S --needed --noconfirm agros/"*)
    [ -z "\$FIRST_RC" ] || exit 1
    sed '2i echo "new update-apps \$*:\${AGROS_SELF_UPDATED:-}" >>"$t/paru"' "$t/ua/update-apps.old" >"$t/ua/new"
    chmod +x "$t/ua/new"; mv "$t/ua/new" "$t/ua/update-apps" ;;
esac
EOF
chmod +x "$t/bin/paru"
first() {
    rm -f "$t/paru"; cp "$t/ua/update-apps.old" "$t/ua/update-apps"
    XDG_RUNTIME_DIR=$t/run TMPDIR=$t/tmp HOME=$t/home XDG_STATE_HOME=$t/state XDG_CACHE_HOME=$t/home/.cache PATH=$t/bin:$PATH \
        /usr/bin/timeout 120 "$t/ua/update-apps" </dev/null 2>&1
}
# (its password asked once, by the first: no terminal, sudo wanting one)
stub sudo 'case "$1" in -n) exit 1 ;; -S) read -r p; [ "$p" = right ] ;; esac'
stub zenity 'n=$(cat '"$t"'/asked 2>/dev/null || echo 0); echo $((n + 1)) >'"$t"'/asked; echo right'
mkdir -p "$t/run"; rm -f "$t/asked"
out=$(FIRST_QU="agros-scripts r622.a-1 -> r702.b-1" first) || true
steps=$(grep -oE -- '-Sy --noconfirm$|-S --needed --noconfirm agros/agros-scripts$|^new update-apps :1$|-Su --noconfirm$' "$t/paru" | paste -sd,)
[[ $steps == "-Sy --noconfirm,-S --needed --noconfirm agros/agros-scripts,new update-apps :1,-Sy --noconfirm,-Su --noconfirm" ]] ||
    fail "AgrOS's newer update code not installed first, then the update run by it once: $(cat "$t/paru")"
[[ $(grep -c '^== System and AUR apps$' <<<"$out") == 1 && $out == *"AgrOS's update code first: agros-scripts"* ]] ||
    fail "the update code first not said, or the system step's title twice: $out"
[[ $(cat "$t/asked") == 1 && -z $(ls -A "$t/run") && -z $(ls -A "$t/tmp") ]] ||
    fail "the password asked again by the new code, or a file of the first run's left: $(cat "$t/asked") $(ls -A "$t/run" "$t/tmp")"
stub sudo 'exit 0'
# (both newer: both first, in one install)
FIRST_QU=$'agros-scripts r1-1 -> r2-1\nagros-system r1-1 -> r2-1 [ignored]' first >/dev/null || true
grep -qx -- 'paru .* -S --needed --noconfirm agros/agros-scripts' "$t/paru" ||
    fail "one pacman.conf holds back (IgnorePkg) installed first: $(cat "$t/paru")"
FIRST_QU=$'agros-system r1-1 -> r2-1\nagros-scripts r1-1 -> r2-1' first >/dev/null || true
grep -qx -- 'paru .* -S --needed --noconfirm agros/agros-system agros/agros-scripts' "$t/paru" ||
    fail "agros-scripts and agros-system not installed first together: $(cat "$t/paru")"
out=$(first) || true
{ grep -q -- ' -Su --noconfirm$' "$t/paru" && ! grep -qE -- ' -S .*agros/|^new ' "$t/paru" && [[ $out != *"update code"* ]]; } ||
    fail "a step for AgrOS's update code with none newer: $(cat "$t/paru") / $out"
out=$(FIRST_RC=1 FIRST_QU="agros-scripts r1-1 -> r2-1" first) || true
{ grep -q -- ' -S --needed --noconfirm agros/agros-scripts$' "$t/paru" && grep -q -- ' -Su --noconfirm$' "$t/paru" &&
    ! grep -q '^new ' "$t/paru" && [[ $out == *"couldn't be updated first: the update goes on with the code it has"* ]]; } ||
    fail "the update code's install failing stopped the update, or wasn't said: $(cat "$t/paru") / $out"
out=$(FIRST_NEEDS=python FIRST_QU="agros-scripts r1-1 -> r2-1" first) || true
{ grep -q -- ' -Su --noconfirm$' "$t/paru" && ! grep -qE -- ' -S .*agros/|^new ' "$t/paru" &&
    [[ $out == *"not updated first (agros-scripts): it needs python too"* ]]; } ||
    fail "the update code installed with a newer library (a partial upgrade), or not said: $(cat "$t/paru") / $out"
rm -rf "$t/ua" "$t/tmp"
stub paru 'echo "paru $*" >>"'"$t"'/paru"'

# [agros]'s packages that no longer load (soname-broken's: libcava, its libsndio.so.7 gone, rebuilt in [agros] at the
# same version) reinstalled from [agros] after the update, through paru (its sudo), said; one with its libraries there
# not; the reinstall failing said, the update going on
mkdir -p "$t/fix/usr/lib"; : >"$t/fix/usr/lib/libcava.so.1"
# shellcheck disable=SC2016  # (expanded by the stand-in)
stub pacman 'case "$1" in -Sl) echo "agros libcava 1.0.0-1 [installed]" ;; -Qlq) echo "'"$t"'/fix/usr/lib/libcava.so.1" ;;
    -Si) printf "Version : 1.0.0-1\nBuild Date : Thu 20\n" ;; -Qi) printf "Version : 1.0.0-1\nBuild Date : Mon 17\n" ;;
    -Sp) echo libcava ;; esac; true'
stub readelf 'echo " 0x1 (NEEDED) Shared library: [libsndio.so.7]"'
stub ldconfig 'echo "0 libs found in cache"'
# shellcheck disable=SC2016
stub paru 'echo "paru $*" >>"'"$t"'/paru"; case "$*" in *" agros/libcava"*) [ -z "$FIX_RC" ] ;; esac'
fix() { rm -f "$t/paru"; SONAME_HOLD_LIBDIR=$t/fix/usr/lib HOME=$t/home XDG_STATE_HOME=$t/state XDG_CACHE_HOME=$t/home/.cache \
    PATH=$t/bin:$PATH "$here/.local/bin/update-apps" </dev/null 2>&1; }
out=$(fix) || true
[[ $(grep -oE -- ' -Su --noconfirm$| -S --noconfirm agros/libcava$' "$t/paru" | paste -sd,) == " -Su --noconfirm, -S --noconfirm agros/libcava" &&
    $out == *"libcava needs libsndio.so.7, gone from the system: reinstalled from [agros] (1.0.0-1)"* ]] ||
    fail "[agros]'s package missing a library not reinstalled after the update, or not said: $(cat "$t/paru") / $out"
out=$(FIX_RC=1 fix) || true
[[ $out == *"!! Not reinstalled (libcava): tried again at the next update"* && $out == *"== Developer tools"* ]] ||
    fail "a failed reinstall not said, or the update stopped at it: $out"
: >"$t/fix/usr/lib/libsndio.so.7"
fix >/dev/null || true
grep -q -- 'agros/libcava' "$t/paru" && fail "reinstalled with all its libraries there: $(cat "$t/paru")"
rm -rf "$t/fix" "$t/bin/readelf" "$t/bin/ldconfig"
stub paru 'echo "paru $*" >>"'"$t"'/paru"'

# A conflict pacman won't settle by itself (--noconfirm, from Settings: its "Remove bar?" answered no; its messages in
# English, read): what conflicts held back alone, the rest updated, said with the command a person runs, a problem for
# Settings ("Finished, with problems"); nothing removed. Still refused without it: said, a problem too
# shellcheck disable=SC2016  # (expanded by the stand-in)
stub paru 'echo "paru $* ($LC_MESSAGES)" >>"'"$t"'/paru"
case "$*" in *" -Su "*)
    c=$(echo "$*" | sed -n "s/.*--config \([^ ]*\) .*/\1/p")
    if [ -n "$CONFLICT" ] && { [ "$CONFLICT" = always ] || ! grep -q "^IgnorePkg = .*foo" "$c"; }; then
        echo ":: foo-2-1 and bar-1-1 are in conflict. Remove bar? [y/N] error: unresolvable package conflicts detected"
        echo "error: failed to prepare transaction (conflicting dependencies)"; echo; echo ":: foo-2-1 and bar-1-1 are in conflict"; exit 1
    fi ;;
esac'
stub pacman 'true'
conflict() { rm -f "$t/paru"; HOME=$t/home XDG_STATE_HOME=$t/state XDG_CACHE_HOME=$t/home/.cache PATH=$t/bin:$PATH \
    "$here/.local/bin/update-apps" </dev/null 2>&1; }
rc=0; out=$(CONFLICT=1 conflict) || rc=$?
[[ $rc != 0 && $(grep -c -- " -Su --noconfirm (C)$" "$t/paru") == 2 &&
    $out == *"!! Waits: foo conflicts with bar (needs a person: sudo pacman -Syu, which asks whether to remove bar)"* &&
    $out == *"tried again without what conflicts"* && $out != *"leaves no update that installs"* ]] ||
    fail "a conflict not held back alone, the rest updated, or not said: $rc $out / $(cat "$t/paru")"
grep -q -- " -R" "$t/paru" && fail "a package removed for a conflict: $(cat "$t/paru")"
rc=0; out=$(CONFLICT=always conflict) || rc=$?
[[ $rc != 0 && $out == *"!! Holding back what conflicts leaves no update that installs"* ]] ||
    fail "an update still refused for a conflict not said: $rc $out"
stub paru 'echo "paru $*" >>"'"$t"'/paru"'

# Run in a terminal: how it went said where it waits for a key, as the Updates app says it. A step that failed (its
# error scrolled away above) isn't "Done.", which read as everything updated; all of it working is
if scr=$(command -v script); then
    rm -f "$t/bin/timeout"  # (the real one: its time limits as they are)
    # (in a terminal of its own, script's, a key pressed every second: the one it waits for at the end)
    term() {
        while sleep 1; do printf x 2>/dev/null || break; done |  # (stops as it ends: SIGPIPE can be ignored)
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
