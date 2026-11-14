#!/usr/bin/env bash
# system/wired-link-watch, with ip, ethtool, nmcli, setpriv and notify stand-ins, a made-up /sys/class/net and its
# notes in a throwaway folder: nothing on the real network. Three drops (down and back within 15 s) in 2 minutes step
# a card down once: EEE off, then 1 Gbps (above it), then a note; each in its NetworkManager profile, else through
# ethtool (made again when the link comes back without it). Long downs (a cable pulled), drops spread out, a link taken
# down on purpose, Wi-Fi and virtual cards: nothing. Nothing done or said twice; a new card starts fresh; the drops
# the watch's own change brings (the link renegotiated) not counted. Said only to someone logged in (agros-each-user's
# --sessions: not the login screen's greeter)
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
me=$(id -u)
mkdir -p "$t/bin" "$t/run/$me" "$t/run/965" "$t/state"
touch "$t/run/$me/bus" "$t/run/965/bus"  # (965: the greeter's, at the login screen; not a user)
# ip: the events in $t/events; ethtool --show-eee: $t/eee's status (--set-eee and -s change it, and the speed);
# nmcli: GENERAL.CON-UUID is $t/uuid's (none without it); setpriv: runs the command as is
# shellcheck disable=SC2016  # (expanded by the stand-ins)
{
    printf '#!/bin/sh\ncat %s/events\n' "$t" >"$t/bin/ip"
    printf '#!/bin/sh\necho "ethtool $*" >>%s/calls\ncase "$1" in\n--show-eee) echo "	EEE status: $(cat %s/eee)" ;;\n--set-eee) echo disabled >%s/eee ;;\n-s) echo 1000 >%s/sys/$2/speed ;;\nesac\n' "$t" "$t" "$t" "$t" >"$t/bin/ethtool"
    printf '#!/bin/sh\necho "nmcli $*" >>%s/calls\n[ "$1" != -g ] || cat %s/uuid 2>/dev/null\nexit 0\n' "$t" "$t" >"$t/bin/nmcli"
    printf '#!/bin/sh\nwhile [ "${1#--}" != "$1" ]; do shift; done\nexec "$@"\n' >"$t/bin/setpriv"
    printf '#!/bin/sh\necho "notify $*" >>%s/notes\n' "$t" >"$t/bin/notify-send"
    # (agros-each-user --notify's own unit: run here, in the watch's process group; loginctl: each one's session a
    # desktop's, unless $t/tty says it's a text login's, or $t/greeter a greeter's)
    printf '#!/bin/sh\nwhile [ "${1#--}" != "$1" ]; do shift; done\n"$@" &\n' >"$t/bin/systemd-run"
    printf '#!/bin/sh\ncase "$1" in show-user) echo 1 ;; show-session) [ -e %s/tty ] && echo Type=tty || echo Type=wayland; [ -e %s/greeter ] && echo Class=greeter || echo Class=user ;; esac\n' "$t" "$t" >"$t/bin/loginctl"
}
chmod +x "$t/bin/"*
# The cards: enp8s0 (wired, 2.5 Gbps), wlan0 (Wi-Fi), br0 and vmnet8 (virtual: no device)
card() { mkdir -p "$t/sys/$1"; echo 1 >"$t/sys/$1/type"; echo "${3:-aa:bb:cc:dd:ee:01}" >"$t/sys/$1/address"; echo "${2:-2500}" >"$t/sys/$1/speed"; }
card enp8s0; mkdir "$t/sys/enp8s0/device"
card wlan0; mkdir "$t/sys/wlan0/device" "$t/sys/wlan0/wireless"
card br0; card vmnet8
echo enabled >"$t/eee"; echo 3eceeb40-95c0-3c5b-8c65-a77836ba1b9a >"$t/uuid"
base=$(date -d '2026-11-14 10:00:00' +%s)
# ev <second> <dev> up|down|off: one ip monitor line
ev() {
    local f
    case $3 in up) f=BROADCAST,MULTICAST,UP,LOWER_UP ;; down) f=NO-CARRIER,BROADCAST,MULTICAST,UP ;; off) f=BROADCAST,MULTICAST ;; esac
    echo "[$(date -d "@$((base + $1))" +%Y-%m-%dT%H:%M:%S).123456] 2: $2: <$f> mtu 1500 qdisc fq_codel state UP mode DEFAULT group default \\    link/ether aa:bb:cc:dd:ee:01 brd ff:ff:ff:ff:ff:ff"
}
# flaps <dev> <second> <gap> <down for> <count>
flaps() { local i s; for ((i = 0; i < $5; i++)); do s=$(($2 + i * $3)); ev "$s" "$1" down; ev "$s" "$1" down; ev "$((s + $4))" "$1" up; done; }
# (in a session of its own: a note kept for when someone logs in waits in the background, ended with it)
run() {
    local p
    rm -f "$t/calls" "$t/notes"; cat >"$t/events"
    WIRED_SYSFS=$t/sys WIRED_STATE=$t/state WIRED_EACH_USER=$here/.local/bin/agros-each-user AGROS_RUN_USER=$t/run \
        NOTIFY_WHEN_UP_TRIES=1 PATH=$t/bin:$PATH setsid timeout 20 "$here/system/wired-link-watch" >"$t/out" 2>&1 &
    p=$!
    wait "$p" || fail "it failed: $(cat "$t/out")"
    sleep 0.3  # (the notifications are sent in the background)
    kill -- -"$p" 2>/dev/null || true
}
changed() { grep -E 'modify|reapply|connection up|ethtool (-s|--set-eee)' "$t/calls" 2>/dev/null; }
notes() { cat "$t/notes" 2>/dev/null; }

# Two drops: nothing. Long downs (20 s), drops spread over more than 2 minutes, taken down on purpose: nothing
flaps enp8s0 0 10 2 2 | run
[[ -z $(changed) && -z $(notes) ]] || fail "two drops did something: $(changed) $(notes)"
flaps enp8s0 0 30 20 4 | run
[[ -z $(changed) && -z $(notes) ]] || fail "long downs (a cable pulled) counted: $(changed)"
flaps enp8s0 0 70 2 4 | run
[[ -z $(changed) ]] || fail "drops 70 s apart counted as 3 in 2 minutes: $(changed)"
for s in 0 10 20 30; do ev $s enp8s0 off; ev $((s + 2)) enp8s0 up; done | run
[[ -z $(changed) ]] || fail "a link taken down on purpose counted: $(changed)"
# Wi-Fi, a bridge, VMware's: nothing
{ flaps wlan0 0 5 1 5; flaps br0 0 5 1 5; flaps vmnet8 0 5 1 5; } | run
[[ -z $(changed) && -z $(notes) && ! -e $t/state/aa-bb-cc-dd-ee-01 ]] || fail "a Wi-Fi or virtual card stepped down: $(changed)"

# Three drops: EEE off in the profile, said with the way back; two more right after (re-armed): nothing more
flaps enp8s0 0 10 2 5 | run
[[ $(changed) == "nmcli connection modify uuid 3eceeb40-95c0-3c5b-8c65-a77836ba1b9a ethtool.eee-enabled off"$'\n'"nmcli connection up uuid 3eceeb40-95c0-3c5b-8c65-a77836ba1b9a" ]] ||
    fail "EEE not turned off in the profile (alone, brought up: NetworkManager can't reapply it): $(changed)"
[[ $(notes | wc -l) == 1 && $(notes) == *"power saving off"*'ethtool.eee-enabled ""'* ]] || fail "EEE's step not said once: $(notes)"
grep -qx 'eee nm 3eceeb40-95c0-3c5b-8c65-a77836ba1b9a' "$t/state/aa-bb-cc-dd-ee-01" || fail "EEE's step not noted"
# Still dropping (EEE says enabled again: not done twice): 1 Gbps in the profile
flaps enp8s0 0 10 2 3 | run
[[ $(changed) == *"modify uuid 3eceeb40-95c0-3c5b-8c65-a77836ba1b9a 802-3-ethernet.auto-negotiate yes 802-3-ethernet.speed 1000 802-3-ethernet.duplex full"$'\n'"nmcli device reapply enp8s0" &&
    $(changed) != *eee* ]] || fail "not stepped to 1 Gbps (or EEE again): $(changed)"
[[ $(notes) == *"1 Gbps"*"2500 Mbit/s"*'802-3-ethernet.speed ""'* ]] || fail "1 Gbps not said: $(notes)"
# Still dropping: the note to check the cable, once; then nothing at all
echo 1000 >"$t/sys/enp8s0/speed"
flaps enp8s0 0 10 2 3 | run
[[ -z $(changed) && $(notes) == *"keeps dropping"*cable* ]] || fail "no note that it still drops: $(changed) $(notes)"
flaps enp8s0 0 10 2 6 | run
[[ -z $(changed) && -z $(notes) ]] || fail "something done or said again after the last step: $(changed) $(notes)"
# The removal: the profile's changes said, with the way back, the notes removed
out=$( (set +e; export AGROS_ROOT=$t/root PATH=$t/bin:$PATH; mkdir -p "$t/root/var/lib/agros"; cp -r "$t/state" "$t/root/var/lib/agros/wired-link"
    . "$here/packages/agros-system/agros-system.install"; post_remove))
[[ $out == *"EEE stays off"*'ethtool.eee-enabled ""'*"only 1 Gbps"*'802-3-ethernet.speed ""'* && ! -e $t/root/var/lib/agros/wired-link ]] ||
    fail "the removal didn't say the profile's changes: $out"

# A new card (another MAC), no NetworkManager profile, EEE already off, at 1 Gbps: straight to the note
echo 1000 >"$t/sys/enp8s0/speed"; echo aa:bb:cc:dd:ee:02 >"$t/sys/enp8s0/address"; echo disabled >"$t/eee"; rm "$t/uuid"
flaps enp8s0 0 10 2 3 | run
[[ -z $(changed) && $(notes) == *"keeps dropping"* ]] || fail "a card with nothing to change not told to check the cable: $(changed) $(notes)"
# Another: through ethtool, and made again when its link comes back without it (a restart)
echo aa:bb:cc:dd:ee:03 >"$t/sys/enp8s0/address"; echo 2500 >"$t/sys/enp8s0/speed"; echo enabled >"$t/eee"
flaps enp8s0 0 10 2 3 | run
[[ $(changed) == "ethtool --set-eee enp8s0 eee off" && $(notes) == *"sudo rm $t/state/aa-bb-cc-dd-ee-03"* ]] ||
    fail "EEE not turned off through ethtool: $(changed) $(notes)"
flaps enp8s0 0 10 2 3 | run
[[ $(changed) == *"ethtool -s enp8s0 speed 1000 duplex full autoneg on"* ]] || fail "1 Gbps not set through ethtool: $(changed)"
echo enabled >"$t/eee"; echo 2500 >"$t/sys/enp8s0/speed"
: | run  # (started again, as after a restart: EEE back on, 2.5 Gbps)
[[ $(changed) == "ethtool --set-eee enp8s0 eee off"$'\n'"ethtool -s enp8s0 speed 1000 duplex full autoneg on" && -z $(notes) ]] ||
    fail "the ethtool steps not made again at start: $(changed)"
echo disabled >"$t/eee"; echo 1000 >"$t/sys/enp8s0/speed"
flaps enp8s0 0 10 2 1 | run
[[ -z $(changed) ]] || fail "the ethtool steps made again while in effect (renegotiating the link): $(changed)"

# The drops the watch's own change brings (within 15 s of it) don't count: three right after EEE off aren't a next step
echo aa:bb:cc:dd:ee:04 >"$t/sys/enp8s0/address"; echo 2500 >"$t/sys/enp8s0/speed"; echo enabled >"$t/eee"
echo 3eceeb40-95c0-3c5b-8c65-a77836ba1b9a >"$t/uuid"
flaps enp8s0 0 5 2 6 | run
[[ $(changed) == *eee-enabled* && $(changed) != *802-3-ethernet.speed* ]] ||
    fail "the drops its own change brought counted toward the next step: $(changed)"

# Only the login screen (its greeter's bus), then nobody: the step made, said in the journal, not to the greeter
rm "$t/run/$me/bus"
echo aa:bb:cc:dd:ee:05 >"$t/sys/enp8s0/address"; echo enabled >"$t/eee"
flaps enp8s0 0 10 2 3 | run
[[ $(changed) == *eee-enabled* && -z $(notes) && $(cat "$t/out") == *"power saving off"* ]] ||
    fail "with only the login screen, the note went to the greeter or wasn't kept: $(notes) $(cat "$t/out")"
rm "$t/run/965/bus"
echo aa:bb:cc:dd:ee:06 >"$t/sys/enp8s0/address"; echo enabled >"$t/eee"
flaps enp8s0 0 10 2 3 | run
[[ $(changed) == *eee-enabled* && -z $(notes) && $(cat "$t/out") == *"power saving off"* ]] ||
    fail "with nobody logged in, the step not made or the note sent anyway: $(notes) $(cat "$t/out")"
[[ $(AGROS_RUN_USER=$t/run "$here/.local/bin/agros-each-user" --sessions) == "" ]] || fail "--sessions listed someone"
touch "$t/run/$me/bus" "$t/run/965/bus"
sessions() { AGROS_RUN_USER=$t/run PATH=$t/bin:$PATH "$here/.local/bin/agros-each-user" --sessions; }
[[ $(sessions) == "$t/run/$me/bus" ]] || fail "--sessions isn't this user's bus alone: $(sessions)"
# A session with no desktop (a text or SSH login; their bus there all the same): nobody to tell
touch "$t/tty"
[[ -z $(sessions) ]] || fail "--sessions counted a text login as a desktop: $(sessions)"
rm "$t/tty"
# A greeter's session under a user's uid (a login screen run as a regular account; class greeter, a Wayland one): nobody
touch "$t/greeter"
[[ -z $(sessions) ]] || fail "--sessions counted a greeter's session (class greeter) as a desktop: $(sessions)"
rm "$t/greeter"
# A bus that's a link (to another's socket, a root file): not the user's, skipped
mv "$t/run/$me/bus" "$t/run/$me/real-bus"; ln -s real-bus "$t/run/$me/bus"
[[ -z $(sessions) ]] || fail "--sessions took a link for the user's bus: $(sessions)"
rm "$t/run/$me/bus"; mv "$t/run/$me/real-bus" "$t/run/$me/bus"
# --notify-wait: as the user, in the account's group, whatever group the bus file has (theirs to change)
other=$(id -G | tr ' ' '\n' | grep -vx "$(id -g)" | head -1 || true)
[[ -z $other ]] || chgrp "$other" "$t/run/$me/bus"
printf '#!/bin/sh\necho "setpriv $*" >>%s/as\n' "$t" >"$t/bin/setpriv"
rm -f "$t/as"
AGROS_RUN_USER=$t/run PATH=$t/bin:$PATH "$here/.local/bin/agros-each-user" --notify-wait -a X hello || true
grep -q "^setpriv --reuid=$me --regid=$(id -g) --init-groups " "$t/as" || fail "--notify-wait not as the user in the account's group: $(cat "$t/as" 2>/dev/null)"
[[ -n $other ]] || echo "(no second group here: the bus file's group not changed)"
# The command run for each user: its stdin not the list of users
# (two users: this one twice, each home with the command)
for h in home home2; do
    mkdir -p "$t/$h/.local/bin"
    printf '#!/bin/sh\ncat >>%s/stdin\n' "$t" >"$t/$h/.local/bin/agros-test-cmd"; chmod +x "$t/$h/.local/bin/agros-test-cmd"
done
printf '#!/bin/sh\nwhile [ "${1#--}" != "$1" ]; do shift; done\nexec "$@"\n' >"$t/bin/setpriv"
printf '#!/bin/sh\n[ "$1" = passwd ] && printf "%%s\\n" "%s:x:%s:%s::%s:/bin/bash" "%s:x:%s:%s::%s:/bin/bash"\n' \
    "$(id -un)" "$me" "$(id -g)" "$t/home" "$(id -un)" "$me" "$(id -g)" "$t/home2" >"$t/bin/getent"; chmod +x "$t/bin/getent"
echo input | PATH=$t/bin:$PATH "$here/.local/bin/agros-each-user" agros-test-cmd
[[ $(cat "$t/stdin") == input ]] || fail "a user's command read the list of users: $(cat "$t/stdin")"
rm "$t/bin/getent"
# --as: setpriv to the user, its environment reset, never PAM (runuser, su or sudo: a logind session)
printf '#!/bin/sh\necho "setpriv $*" >%s/as\n' "$t" >"$t/bin/setpriv"
PATH=$t/bin:$PATH "$here/.local/bin/agros-each-user" --as "$(id -un)" true
[[ $(cat "$t/as") == "setpriv --reuid=$me --regid=$(id -g) --init-groups --reset-env true" ]] || fail "--as: $(cat "$t/as")"
grep -qwE 'runuser|sudo|su' <<<"$(grep -vE '^ *#' "$here/.local/bin/agros-each-user")" && fail "agros-each-user goes through PAM"
echo "ok wired-link-watch"
