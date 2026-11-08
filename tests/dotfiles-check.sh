#!/usr/bin/env bash
# dotfiles-check's "is this shell running": by the configs Quickshell lists, missing ones reported; no repo to
# compare the system files with doesn't call them out of date
set -uo pipefail
. "$(dirname "$0")/lib.sh"
# (always in a home of its own, XDG_STATE_HOME unset: it checks the Hyprland config, writing down the errors; Hyprland a
# stand-in, its config fine)
export XDG_STATE_HOME='' HOME=$t/home0
cat >"$t/Hyprland" <<'H'
#!/bin/sh
printf '======== Config parsing result:\n\nconfig ok\n'
H
chmod +x "$t/Hyprland"
printf '#!/bin/sh\nprintf "  Config path: %%s\\n" "$HOME/.config/quickshell/caelestia/shell.qml" "$HOME/.config/quickshell/widgets/shell.qml"\n' >"$t/qs"; chmod +x "$t/qs"
out=$(PATH=$t:$PATH "$here/.local/bin/dotfiles-check" 2>&1)
grep -q "Not running: qs -c switcher" <<<"$out" || fail "a missing shell wasn't reported: $out"
grep -q "Not running: qs -c caelestia\|Not running: qs -c widgets" <<<"$out" && fail "a running shell reported missing: $out"

# In a home of its own: an overlay file's real error reported, a list item's "of null" not; a Caelestia tag my config
# relies on that's gone reported
h=$t/home; mkdir -p "$h/.config/quickshell/caelestia/modules" "$h/.config/hypr/hyprland"
: >"$h/.config/quickshell/caelestia/modules/Mine.qml"
printf '"music_player" "communication_app" "todo_app"\n' >"$h/.config/hypr/hyprland/rules.lua"
cat >"$t/qs" <<'Q'
#!/bin/sh
[ "$1" = log ] && printf '%s\n' "WARN: @modules/Mine.qml[3:-1]: ReferenceError: Gone is not defined" \
    "WARN: @modules/Mine.qml[9:-1]: TypeError: Cannot read property 'actions' of null" \
    "WARN: @modules/other/AllMine.qml[1:1]: ReferenceError: Theirs is not defined" \
    "WARN: @other/modules/Mine.qml[1:1]: ReferenceError: Theirs too is not defined"
exit 0
Q
out=$(HOME=$h PATH=$t:$PATH "$here/.local/bin/dotfiles-check" 2>&1)
grep -q "ReferenceError: Gone" <<<"$out" || fail "an overlay QML error wasn't reported: $out"
grep -q "of null" <<<"$out" && fail "a list item going away was reported: $out"
grep -q "Theirs" <<<"$out" && fail "Caelestia's own file of a similar name blamed on the overlay: $out"
grep -q 'no longer has "system_monitor"' <<<"$out" || fail "a missing Caelestia tag wasn't reported: $out"
grep -q 'no longer has "todo_app"' <<<"$out" && fail "a present Caelestia tag reported missing: $out"
# No repo where it looks (cloned elsewhere): the installed system files aren't all called out of date
out=$(HOME=$h DOTFILES_DIR=$t/none PATH=$t:$PATH "$here/.local/bin/dotfiles-check" 2>&1)
grep -q "System files not the repo" <<<"$out" && fail "no repo to compare with, system files called older: $out"

# Hyprland's config errors: from checking it (Hyprland --verify-config), not from hyprctl configerrors alone, which every
# hyprctl eval clears and a failed one fills with its own error (not the config's); its lines naming a config file kept
cat >"$t/hyprctl" <<'H'
#!/bin/sh
[ "$3" = configerrors ] && printf '%s\n' 'return hl.window_rule({ match = 1 });:1: attempt to call a nil value' \
    "$HOME/.config/hypr/user.lua:3: in the session only"
exit 0
H
chmod +x "$t/hyprctl"
out=$(HOME=$h PATH=$t:$PATH "$here/.local/bin/dotfiles-check" 2>&1)
grep -q "user.lua:3: in the session only" <<<"$out" || fail "a config file's error from the session not reported: $out"
grep -q "hl.window_rule" <<<"$out" && fail "a failed hyprctl eval reported as a config error: $out"
cat >"$t/Hyprland" <<'H'
#!/bin/sh
printf '======== Config parsing result:\n\nuser/apps.lua:7: bad bind\n'
exit 1
H
out=$(HOME=$h PATH=$t:$PATH "$here/.local/bin/dotfiles-check" 2>&1)
grep -q "Hyprland config errors: user/apps.lua:7: bad bind" <<<"$out" || fail "the config's own error (checked) not reported: $out"
# The install at shutdown (auto-update --install writes down how it went): a failure reported with its reason, an ok
# one not; pacman's own lock with no pacman running reported, not while one runs
mkdir -p "$t/au" "$t/pacdb"
echo "failed 2026-11-05 22:10 error: failed to commit transaction (conflicting files)" >"$t/au/install-result"
: >"$t/pacdb/db.lck"
printf '#!/bin/sh\nexit 1\n' >"$t/pgrep"; chmod +x "$t/pgrep"
chk() { HOME=$h AUTO_UPDATE_DIR=$t/au PACMAN_DB_DIR=$t/pacdb PATH=$t:$PATH "$here/.local/bin/dotfiles-check" 2>&1; }
out=$(chk)
grep -q "failed to install at shutdown (2026-11-05 22:10: error: failed to commit transaction" <<<"$out" ||
    fail "a failed install at shutdown not reported: $out"
grep -q "pacman's lock was left behind" <<<"$out" || fail "pacman's stale lock not reported: $out"
echo "ok 2026-11-05 22:10 " >"$t/au/install-result"
out=$(chk)
grep -q "failed to install" <<<"$out" && fail "an install that went fine reported: $out"
# Who holds pacman's lock: pgrep -x finds them by name (a stand-in here, its pids those of processes named in their
# command line as the real ones would be: perl's $0); pacman on other lists (checkupdates' --dbpath) or only querying
# (-Qu) isn't one, so the lock is still said to be left behind; pacman installing, PackageKit's or pamac's daemon is
# (and the names it looks for are theirs)
procs=()
trap 'kill "${procs[@]}" 2>/dev/null; rm -rf "$t"' EXIT
for cmd in "pacman -Syu" "packagekitd" "pamac-daemon" "pacman -Sy --dbpath /tmp/checkup-db --logfile /dev/null" "pacman -Qu"; do
    # shellcheck disable=SC2016  # (perl's own $0)
    perl -e '$0 = $ARGV[0]; sleep 300' "$cmd" >/dev/null 2>&1 &
    pid=$!
    procs+=("$pid")
    # shellcheck disable=SC2016  # (expanded by the stand-in)
    printf '#!/bin/sh\necho "$2" | tr "|" " " | grep -qw -- %s && echo %s\n' "${cmd%% *}" "$pid" >"$t/pgrep"
    sleep 0.2
    out=$(chk)
    case $cmd in
        *--dbpath* | *-Qu) grep -q "pacman's lock was left behind" <<<"$out" || fail "'$cmd' taken for holding pacman's lock: $out" ;;
        *) grep -q "pacman's lock" <<<"$out" && fail "pacman's lock reported while '$cmd' runs: $out" ;;
    esac
done
echo "ok dotfiles-check"
