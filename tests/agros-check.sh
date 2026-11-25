#!/usr/bin/env bash
# agros-check's "is this shell running": by the configs Quickshell lists, missing ones reported; no repo to
# compare the system files with doesn't call them out of date
set -uo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
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
out=$(PATH=$t:$PATH "$here/.local/bin/agros-check" 2>&1)
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
    "WARN: @modules/Mine.qml[249:-1]: TypeError: Value is undefined and could not be converted to an object" \
    "WARN: @modules/Mine.qml[250:-1]: TypeError: Value is undefined and could not be converted to an object" \
    "WARN: @modules/Mine.qml[251:-1]: TypeError: Value is undefined and could not be converted to an object" \
    "WARN: @modules/Mine.qml[7:-1]: TypeError: Property 'gone' of object Icons is not a function" \
    "WARN: @modules/other/AllMine.qml[1:1]: ReferenceError: Theirs is not defined" \
    "WARN: @other/modules/Mine.qml[1:1]: ReferenceError: Theirs too is not defined"
exit 0
Q
out=$(HOME=$h PATH=$t:$PATH "$here/.local/bin/agros-check" 2>&1)
grep -q "ReferenceError: Gone" <<<"$out" || fail "an overlay QML error wasn't reported: $out"
grep -q "of null" <<<"$out" && fail "a list item going away was reported: $out"
# ...nor a window read before it has its IPC object (Workspace.qml's, upstream's line: Steam's windows coming and
# going), even three of them before a real one; a function renamed is
grep -q "could not be converted" <<<"$out" && fail "a window without its IPC object yet was reported: $out"
grep -q "'gone' of object Icons is not a function" <<<"$out" || fail "a renamed function wasn't reported after transient errors: $out"
grep -q "Theirs" <<<"$out" && fail "Caelestia's own file of a similar name blamed on the overlay: $out"
grep -q 'no longer has "system_monitor"' <<<"$out" || fail "a missing Caelestia tag wasn't reported: $out"
grep -q 'no longer has "todo_app"' <<<"$out" && fail "a present Caelestia tag reported missing: $out"
# No repo where it looks (cloned elsewhere): the installed system files aren't all called out of date
out=$(HOME=$h DOTFILES_DIR=$t/none PATH=$t:$PATH "$here/.local/bin/agros-check" 2>&1)
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
out=$(HOME=$h PATH=$t:$PATH "$here/.local/bin/agros-check" 2>&1)
grep -q "user.lua:3: in the session only" <<<"$out" || fail "a config file's error from the session not reported: $out"
grep -q "hl.window_rule" <<<"$out" && fail "a failed hyprctl eval reported as a config error: $out"
cat >"$t/Hyprland" <<'H'
#!/bin/sh
printf '======== Config parsing result:\n\nuser/apps.lua:7: bad bind\n'
exit 1
H
out=$(HOME=$h PATH=$t:$PATH "$here/.local/bin/agros-check" 2>&1)
grep -q "Hyprland config errors: user/apps.lua:7: bad bind" <<<"$out" || fail "the config's own error (checked) not reported: $out"
# The install at shutdown (auto-update --install writes down how it went): a failure reported with its reason, an ok
# one not; pacman's own lock with no pacman running reported, not while one runs
mkdir -p "$t/au" "$t/pacdb"
echo "failed 2026-11-05 22:10 error: failed to commit transaction (conflicting files)" >"$t/au/install-result"
: >"$t/pacdb/db.lck"
printf '#!/bin/sh\nexit 1\n' >"$t/pgrep"; chmod +x "$t/pgrep"
# (an administrator's account, wheel, unless a check says otherwise: what it's told to do depends on it)
# shellcheck disable=SC2016  # (expanded by the stand-in)
printf '#!/bin/sh\n[ "$1" = -nG ] && exec echo "${ID_GROUPS-users wheel}"\nexec /usr/bin/id "$@"\n' >"$t/id"; chmod +x "$t/id"
chk() { HOME=$h AUTO_UPDATE_DIR=$t/au PACMAN_DB_DIR=$t/pacdb PATH=$t:$PATH "$here/.local/bin/agros-check" 2>&1; }
out=$(chk)
grep -q "failed to install at shutdown (2026-11-05 22:10: error: failed to commit transaction" <<<"$out" ||
    fail "a failed install at shutdown not reported: $out"
grep -q "pacman's lock was left behind" <<<"$out" || fail "pacman's stale lock not reported: $out"
# ...but not while the boot's download runs: AgrOS's own update code installed first, from its lists, holds it
touch "$t/au/downloading"
# shellcheck disable=SC2016  # (expanded by the stand-in)
printf '#!/bin/sh\n[ "$*" = "is-active -q auto-update" ] && exit ${AU_ACTIVE:-0}\nexit 3\n' >"$t/systemctl"; chmod +x "$t/systemctl"
[[ $(chk) != *"pacman's lock was left behind"* ]] || fail "pacman's lock said left behind while the boot's update holds it"
[[ $(AU_ACTIVE=3 chk) == *"pacman's lock was left behind"* ]] || fail "a lock left by a boot update no longer running not said"
rm "$t/au/downloading" "$t/systemctl"
echo "ok 2026-11-05 22:10 " >"$t/au/install-result"
out=$(chk)
grep -q "failed to install" <<<"$out" && fail "an install that went fine reported: $out"
# The boot's AUR builds that failed: said while what they meant to build is older than that; not once Updates built
# it; and not beside the update held back for the same failure (one message per cause)
mkdir -p "$t/au/aur"; echo "a build failed" >"$t/au/aur/failed"; echo "equibop 1.1-1" >"$t/au/aur/wanted"
# shellcheck disable=SC2016  # (expanded by the stand-in)
printf '#!/bin/sh
[ "$1" = -Q ] || exit 1
case $2 in equibop) echo "equibop $EQUIBOP" ;; qt6-base) echo "qt6-base ${QT:-6.9.0-1}" ;; python) echo "python ${PY:-3.13.7-1}" ;; *) exit 1 ;; esac
' >"$t/pacman"
chmod +x "$t/pacman"
[[ $(EQUIBOP=1.0-1 chk) == *"couldn't build AUR apps (a build failed): still waiting: equibop;"* ]] || fail "the failed AUR builds not said: $(EQUIBOP=1.0-1 chk)"
[[ $(EQUIBOP=1.1-1 chk) != *"couldn't build AUR apps"* ]] || fail "the failed AUR builds said after Updates built them"
# (a run that failed before it planned anything, the AUR out of reach: nothing known to be waiting, nothing said)
rm "$t/au/aur/wanted"
[[ $(EQUIBOP=1.0-1 chk) != *"couldn't build AUR apps"* ]] || fail "a whole run's failure with nothing planned said as AUR apps waiting"
echo "equibop 1.1-1" >"$t/au/aur/wanted"
# (what a build or a package's install script wrote never reaches the notification as it is: no Markdown link, image
# or HTML)
printf '%s\n' 'equibop: it needs ![x](https://e.vil/i.png) <img src=x> [a](b)' >"$t/au/aur/failed"
out=$(EQUIBOP=1.0-1 chk)
line=$(grep "couldn.t build AUR apps" <<<"$out"); [[ -n $line && $line != *[\<\>\[\]\!]* ]] || fail "a build's text reached the notification as it is: $out"
# (one held for its build files to be reviewed, auto-update-aur's guard: the Updates app leaves it out, so not "run
# Updates" but update-apps in a terminal, which shows them)
echo "equibop: its AUR maintainers changed (alice to bob): review it: run update-apps in a terminal" >"$t/au/aur/failed"
out=$(EQUIBOP=1.0-1 chk)
[[ $out == *"still waiting: equibop; run update-apps in a terminal"* ]] || fail "an app held for review said to be updated from Updates: $out"
echo "a build failed" >"$t/au/aur/failed"
# Another account (not wheel, its Updates without "Update all", update-apps refusing it): told to ask an
# administrator, not to run Updates, nor to read the boot update's log (root:wheel 0640)
echo "failed 2026-11-05 22:10 error: x" >"$t/au/install-result"
out=$(ID_GROUPS=users EQUIBOP=1.0-1 chk)
[[ $out == *"still waiting: equibop; ask an administrator to run Updates"* && $out == *"(2026-11-05 22:10: error: x): ask an administrator to run Updates"* &&
    $out != *"auto-update.log"* ]] || fail "an account that can't update told to run Updates itself: $out"
out=$(EQUIBOP=1.0-1 chk)
[[ $out == *"still waiting: equibop; run Updates"* && $out == *"error: x): see /var/log/auto-update.log, or run Updates"* ]] ||
    fail "an administrator not told to run Updates: $out"
echo "ok 2026-11-05 22:10 " >"$t/au/install-result"
# The held update: only what's still waiting named (Qt's installed since by Updates, Python's not)
printf '%s\n' "qt6-base 6.9.0-1 -> 6.10.0-1" "python 3.13.7-1 -> 3.14.0-1" >"$t/au/held"
out=$(EQUIBOP=1.0-1 chk)
[[ $out == *"held back (a new qt6-base, python;"* && $out != *"couldn't build AUR apps"* ]] || fail "the held update and its failed build said twice: $out"
out=$(EQUIBOP=1.0-1 QT=6.10.0-1 chk)
[[ $out == *"held back (a new python;"* ]] || fail "the held update names what's installed since: $out"
out=$(EQUIBOP=1.0-1 QT=6.10.0-1 PY=3.14.0-1 chk)
[[ $out != *"held back"* ]] || fail "the held update said with everything installed: $out"
rm -r "$t/pacman" "$t/au/aur" "$t/au/held"
# Who holds pacman's lock: pgrep -x finds them by name (a stand-in here, its pids those of processes named in their
# command line as the real ones would be: perl's $0); pacman on other lists (checkupdates' --dbpath) or only querying
# (-Qu) isn't one, so the lock is still said to be left behind; pacman installing, PackageKit's or pamac's daemon is
# (and the names it looks for are theirs)
procs=()
on_exit 'kill "${procs[@]}"'
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
# The day AgrOS's checks last passed (the boot's copy of agros-arch-ok): said past 10 days, counted to when it was
# fetched (the file's time); not when it's recent, nor from a copy fetched long ago that was recent then, nor garbage
# (dates the region's way, pt_PT's: the day in agros-arch-ok read all the same. And the file's time given as @seconds:
# date's own output there, "sex 09 out 2026", isn't one touch -d reads back, so the file kept today's)
arch_ok() { echo "$1" >"$t/arch-ok"; touch -d "$2" "$t/arch-ok"
    HOME=$h AGROS_ARCH_OK=$t/arch-ok PATH=$t:$PATH LC_TIME=pt_PT.UTF-8 "$here/.local/bin/agros-check" 2>&1; }
out=$(arch_ok "$(date -ud '12 days ago' +%Y/%m/%d)" now)
grep -qF "AgrOS's checks haven't passed for 12 days: Hyprland updates wait until they do" <<<"$out" || fail "checks not passed for 12 days not said: $out"
out=$(arch_ok "$(date -ud '3 days ago' +%Y/%m/%d)" now)
grep -q "checks haven't passed" <<<"$out" && fail "checks that passed 3 days ago said: $out"
out=$(arch_ok "$(date -ud '40 days ago' +%Y/%m/%d)" "@$(date -d '39 days ago' +%s)")
grep -q "checks haven't passed" <<<"$out" && fail "a copy not refreshed since counted to today: $out"
out=$(arch_ok "not a date" "now")
grep -q "checks haven't passed" <<<"$out" && fail "a copy that isn't a date said: $out"
# .pacnew files in /etc (lib.sh's stand-in, AGROS_ETC): named, with how to merge them; as a notification once each (by
# path and time: one a later update leaves again is said again). pacman.conf's AgrOS lines the boot put back
# (auto-update's pacman-conf-repaired): noted too, once
mkdir -p "$AGROS_ETC/pacman.d"
touch "$AGROS_ETC/pacman.conf.pacnew" "$AGROS_ETC/pacman.d/mirrorlist.pacnew"
# shellcheck disable=SC2016  # (expanded by the stand-in)
printf '#!/bin/sh
echo "$*" >>%s/sent
' "$t" >"$t/notify-send"; chmod +x "$t/notify-send"
note() { HOME=$h AUTO_UPDATE_DIR=$t/au NOTIFY_WHEN_UP_TRIES=1 PATH=$t:$PATH "$here/.local/bin/agros-check" --notify 2>&1; }
sent() { grep -c "Config files to look at" "$t/sent" 2>/dev/null; }
out=$(note)
[[ $out == *"beside yours, the package's new version (yours is kept): $AGROS_ETC/pacman.conf.pacnew, $AGROS_ETC/pacman.d/mirrorlist.pacnew. To merge them: sudo pacdiff"* ]] ||
    fail "the .pacnew files not noted, or not how to merge them: $out"
[[ $(sent) == 1 ]] || fail "the .pacnew files not said in a notification: $(cat "$t/sent" 2>/dev/null)"
note >/dev/null
[[ $(sent) == 1 ]] || fail "the same .pacnew files said again at the next login"
touch -d '1 hour ago' "$AGROS_ETC/pacman.conf.pacnew"
note >/dev/null
[[ $(sent) == 2 ]] || fail "a .pacnew a later update left again not said"
echo "2026-11-25 08:01 the upstream gate's Include, AgrOS's repo ([agros])" >"$t/au/pacman-conf-repaired"
out=$(note)
[[ $out == *"pacman.conf had lost AgrOS's lines (the upstream gate's Include, AgrOS's repo (agros); a pacman.conf.pacnew merged whole?): the automatic update put them back (2026-11-25 08:01)"* &&
    $(sent) == 3 ]] || fail "pacman.conf's repair not noted, or not in a notification: $out"
note >/dev/null
[[ $(sent) == 3 ]] || fail "pacman.conf's repair said again"
rm -r "$AGROS_ETC" "$t/au/pacman-conf-repaired"
[[ $(note) != *pacnew* ]] || fail "a .pacnew noted with none left"
echo "ok agros-check"
