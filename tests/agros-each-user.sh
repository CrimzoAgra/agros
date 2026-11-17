#!/usr/bin/env bash
# agros-each-user <command>: run as each AgrOS user whose ~/.local/bin has it (getent's accounts, two homes of this user
# here, and setpriv: stand-ins); none at all during a new system's install (AGROS_NO_USER_HOOKS: the installer's
# packages' hooks)
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
mkdir -p "$t/bin" "$t/u1/.local/bin" "$t/u2" "$t/lib/bin"
me=$(id -un)
# (AgrOS's programs: in $t/lib/bin, as in /usr/lib/agros/bin, each home's ~/.local/bin linking to them)
export AGROS_LIB=$t/lib
ours() { local h; chmod +x "$t/lib/bin/$1"; for h in "${@:2}"; do mkdir -p "$h/.local/bin" && ln -sfn "$t/lib/bin/$1" "$h/.local/bin/$1"; done; }
printf '#!/bin/sh\necho "%s:x:%s:%s::%s:/bin/bash"\necho "%s:x:%s:%s::%s:/bin/bash"\n' "$me" "$UID" "$UID" "$t/u1" "$me" "$UID" "$UID" "$t/u2" >"$t/bin/getent"
# (setpriv: its options dropped, the command run as this user)
printf '#!/bin/sh\nwhile [ "${1#--}" != "$1" ]; do shift; done\nexec "$@"\n' >"$t/bin/setpriv"
# (the command notes its arguments, and whether it has a terminal or anything on its stdin: it mustn't, a user's
# command run from root's pacman)
printf '#!/bin/sh\necho "ran $*" >>"%s/ran"\n(exec </dev/tty) 2>/dev/null && echo tty >>"%s/ran"\n[ -t 1 ] && echo tty1 >>"%s/ran"\n[ -t 2 ] && echo tty2 >>"%s/ran"\nread -r x && echo "stdin $x" >>"%s/ran"\nexit 0\n' "$t" "$t" "$t" "$t" "$t" >"$t/lib/bin/hook-cmd"
chmod +x "$t/bin/"*; ours hook-cmd "$t/u1"
echo typed | script -qec "PATH=$t/bin:\$PATH $here/.local/bin/agros-each-user hook-cmd --prebuild" /dev/null >/dev/null ||
    fail "a run for each user failed"
[[ $(cat "$t/ran") == "ran --prebuild" ]] || fail "not run once, for the user who has it: $(cat "$t/ran" 2>/dev/null)"
rm "$t/ran"
AGROS_NO_USER_HOOKS=1 PATH=$t/bin:$PATH "$here/.local/bin/agros-each-user" hook-cmd --prebuild || fail "the install's skip failed"
[[ ! -e $t/ran ]] || fail "run for a user during an install (AGROS_NO_USER_HOOKS)"
# One user's command reading a descriptor it was handed (the list's, fd 4, once) doesn't take the next users with it
printf '#!/bin/sh\n(cat <&4) >/dev/null 2>&1\necho ran >>"%s/ran2"\n' "$t" >"$t/lib/bin/other-cmd"
ours other-cmd "$t/u1" "$t/u2"
PATH=$t/bin:$PATH "$here/.local/bin/agros-each-user" other-cmd || fail "a run of other-cmd failed"
[[ $(paste -sd, "$t/ran2") == "ran,ran" ]] || fail "a user's command read the next users away: $(cat "$t/ran2")"
# (only that value: any other, 0 too, runs it)
AGROS_NO_USER_HOOKS=0 PATH=$t/bin:$PATH "$here/.local/bin/agros-each-user" hook-cmd --prebuild || fail "a run with AGROS_NO_USER_HOOKS=0 failed"
[[ -e $t/ran ]] || fail "not run with AGROS_NO_USER_HOOKS=0 (only 1 skips it)"
# gone <pattern>: no process whose command line is <pattern> (grep -E, whole) left, within 5 seconds (a stop takes a
# moment, longer beside the other tests: a fixed wait failed this now and then)
gone() { local _; for _ in {1..50}; do grep -qxE "$1" <<<"$(ps -eo args=)" || return 0; sleep 0.1; done; return 1; }
# --as stopped by its caller (auto-update's timeout round a user's Flatpak reinstall): the command stopped with it, though
# in a session of its own; its exit status passed back otherwise
PATH=$t/bin:$PATH timeout 1 "$here/.local/bin/agros-each-user" --as "$me" sleep 37.7 && fail "a timed-out --as reported success"
gone 'sleep 37\.7' || fail "a command run with --as left running after its caller's timeout"
PATH=$t/bin:$PATH "$here/.local/bin/agros-each-user" --as "$me" sh -c 'exit 3' && fail "--as lost its command's failure"
[[ $(PATH=$t/bin:$PATH "$here/.local/bin/agros-each-user" --as "$me" echo out) == out ]] || fail "--as lost its command's output"
# ...a command's own children too (its whole session); and the run over every user stopped with it, not on to the next
# user's command
PATH=$t/bin:$PATH timeout 1 "$here/.local/bin/agros-each-user" --as "$me" sh -c 'sleep 37.6; :' && fail "a timed-out --as (sh -c) reported success"
printf '#!/bin/sh
echo slow >>"%s/slow"
exec sleep 37.9
' "$t" >"$t/lib/bin/slow-cmd"
ours slow-cmd "$t/u1" "$t/u2"
start=$SECONDS
PATH=$t/bin:$PATH timeout 1 "$here/.local/bin/agros-each-user" slow-cmd && fail "a timed-out run over the users reported success"
((SECONDS - start < 4)) && [[ $(wc -l <"$t/slow") == 1 ]] || fail "a stopped run over the users went on to the next one: $(cat "$t/slow")"
gone 'sleep 37\.[69]' || fail "a stopped command, or its child, left running"
# Only AgrOS's own program: a user's file of their own by that name (or a link elsewhere) not run, said; the others'
# links run it
printf '#!/bin/sh\necho ran >>"%s/ran3"\n' "$t" >"$t/lib/bin/own-cmd"
ours own-cmd "$t/u1"
printf '#!/bin/sh\necho mine >>"%s/ran3"\nexec sleep 37.8\n' "$t" >"$t/u2/.local/bin/own-cmd"; chmod +x "$t/u2/.local/bin/own-cmd"
out=$(PATH=$t/bin:$PATH "$here/.local/bin/agros-each-user" own-cmd 2>&1) || fail "a run skipping a user's own file failed: $out"
[[ $(cat "$t/ran3") == ran && $out == *"$me's ~/.local/bin/own-cmd isn't AgrOS's: not run"* ]] ||
    fail "a user's own file run by root's hook, or its skip not said: $(cat "$t/ran3") / $out"
rm "$t/ran3" "$t/u2/.local/bin/own-cmd"; ln -s "$t/u2/elsewhere" "$t/u2/.local/bin/own-cmd"; cp "$t/lib/bin/own-cmd" "$t/u2/elsewhere"
PATH=$t/bin:$PATH "$here/.local/bin/agros-each-user" own-cmd 2>/dev/null || fail "a run skipping a link elsewhere failed"
[[ $(cat "$t/ran3") == ran ]] || fail "a link to a file outside AgrOS run by root's hook: $(cat "$t/ran3")"
# Each user's run under a time limit (pacman waits on it, its lock held): stopped, said, failed; the next user's still
# run. One that ignores the stop (TERM) killed 10 s later
printf '#!/bin/sh\necho late >>"%s/late"\nexec sleep 37.2\n' "$t" >"$t/lib/bin/late-cmd"
ours late-cmd "$t/u1" "$t/u2"
start=$SECONDS
out=$(AGROS_EACH_USER_LIMIT=1 PATH=$t/bin:$PATH "$here/.local/bin/agros-each-user" late-cmd 2>&1) && fail "a run past its time limit reported success"
((SECONDS - start < 8)) && [[ $(wc -l <"$t/late") == 2 && $out == *"late-cmd as $me still ran after 1 s: stopped"* ]] ||
    fail "a run past its time limit not stopped and said, or the next user's not run: $(cat "$t/late") / $out ($((SECONDS - start)) s)"
gone 'sleep 37\.2' || fail "a run past its time limit left running"
# ...a hook's own, shorter one (--limit: the hyprbars build's, a user's home able to hang it)
rm -f "$t/late"
out=$(PATH=$t/bin:$PATH "$here/.local/bin/agros-each-user" --limit 1 late-cmd 2>&1) && fail "a run past its --limit reported success"
[[ $(wc -l <"$t/late") == 2 && $out == *"late-cmd as $me still ran after 1 s: stopped"* ]] ||
    fail "a run past its --limit not stopped and said: $(cat "$t/late") / $out"
gone 'sleep 37\.2' || fail "a run past its --limit left running"
printf '#!/bin/sh\ntrap "" TERM\nsleep 37.1\n' >"$t/lib/bin/stubborn-cmd"
ours stubborn-cmd "$t/u1"
AGROS_EACH_USER_LIMIT=1 PATH=$t/bin:$PATH "$here/.local/bin/agros-each-user" stubborn-cmd 2>/dev/null && fail "a run that ignored its stop reported success"
gone 'sleep 37\.1' || fail "a run that ignored its stop left running"
# Its output without control characters (a user's escapes on root's terminal), tabs and newlines kept; stderr's too
printf '#!/bin/sh\nprintf "a\\033]0;title\\007b\\tc\\r\\n"\nprintf "\\033[2Jd\\n" >&2\n' >"$t/lib/bin/esc-cmd"
ours esc-cmd "$t/u1"
out=$(PATH=$t/bin:$PATH "$here/.local/bin/agros-each-user" esc-cmd 2>"$t/esc-err")
[[ $out == $'a]0;titleb\tc' && $(cat "$t/esc-err") == '[2Jd' ]] ||
    fail "a command's control characters let through: $(od -c <<<"$out" | head -3) / $(od -c <"$t/esc-err" | head -2)"
# Its output from a terminal (through this's pipes) all out, in order, before the caller's next line
# (a lot of it: the pipes still emptying when this returned, the caller's line came first)
for _ in 1 2 3 4 5; do
    script -qec "PATH=$t/bin:\$PATH $here/.local/bin/agros-each-user --as $me sh -c 'seq 20000; echo LAST >&2'; echo AFTER" "$t/typescript" >/dev/null
    got=$(tr -d '\r' <"$t/typescript" | grep -x '20000\|LAST\|AFTER' | paste -sd,)
    # (both to the one terminal: in the order written, LAST whole on a line of its own)
    [[ $got == "20000,LAST,AFTER" ]] ||
        fail "a command's output lost, or after the caller's next line: $(tr -d '\r' <"$t/typescript" | grep -x '20000\|LAST\|AFTER' | paste -sd,)"
done
# ...stopped by INT or HUP the same; and what it started in a group of its own (a timeout inside it) stopped too
for s in INT HUP; do
    PATH=$t/bin:$PATH timeout -s "$s" 1 "$here/.local/bin/agros-each-user" --as "$me" sleep 37.5 && fail "an --as stopped by $s reported success"
    gone 'sleep 37\.5' || fail "a command run with --as left running after its caller's $s"
done
PATH=$t/bin:$PATH timeout 1 "$here/.local/bin/agros-each-user" --as "$me" sh -c 'timeout 100 sleep 37.4; echo after' &&
    fail "a timed-out --as (a timeout inside) reported success"
gone 'sleep 37\.4' || fail "a command's own timeout (a group of its own) left running after its caller's timeout"
# Its output all out to a reader slower than the few seconds what it leaves gets (CI's terminal: the last lines lost)
got=$({ PATH=$t/bin:$PATH "$here/.local/bin/agros-each-user" --as "$me" sh -c 'seq 100000; echo LAST'; } | { sleep 5; cat; } | grep -cx '100000\|LAST' || true)
[[ $got == 2 ]] || fail "a command's output cut off for a slow reader"
# What a command leaves running (a notification waiting for the desktop) kept, but not waited for while it holds the
# output: a few seconds at most
start=$SECONDS
[[ $(PATH=$t/bin:$PATH "$here/.local/bin/agros-each-user" --as "$me" sh -c 'sleep 37.3 & echo done') == "done" ]] ||
    fail "a command's output lost while what it left holds the pipe"
((SECONDS - start < 6)) || fail "--as waited $((SECONDS - start)) s for what its command left running"
left=$(ps -eo pid=,args= | awk '$2 == "sleep" && $3 == "37.3" { print $1 }')
[[ -n $left ]] || fail "what a command left running was stopped"
kill $left
# None of its caller's descriptors (root's open /boot, at shutdown) but those --fd names
fds() { PATH=$t/bin:$PATH "$here/.local/bin/agros-each-user" --as "$me" "$@" sh -c 'ls /proc/$$/fd | sort -n | paste -sd" "' 7</dev/null 8</dev/null; }
[[ $(fds) == "0 1 2" ]] || fail "a command run with --as got its caller's descriptors: $(fds)"
[[ $(fds --fd 7) == "0 1 2 7" ]] || fail "--fd 7 not handed on alone: $(fds --fd 7)"
# --sessions: the bus of each one logged in to a desktop (AGROS_RUN_USER: the run folders), not a text login's, nor a
# bus that's a link (theirs to point at another's); --notify-wait tells them through it, as them
mkdir -p "$t/h" "$t/run/$UID"
cp "$here/.local/bin/agros-each-user" "$t/h/"
printf '#!/bin/sh
echo "told $DBUS_SESSION_BUS_ADDRESS $XDG_RUNTIME_DIR $*" >>"%s/told"
' "$t" >"$t/h/notify-when-up"
printf '#!/bin/sh
case $1 in show-user) echo s1 ;; show-session) printf "Type=%%s\nClass=user\n" "$SESSION_TYPE" ;; esac
' >"$t/bin/loginctl"
chmod +x "$t/h/"* "$t/bin/loginctl"
sess() { SESSION_TYPE=$1 AGROS_RUN_USER=$t/run PATH=$t/bin:$PATH "$t/h/agros-each-user" --sessions | sort -u; }
touch "$t/run/$UID/bus"
[[ $(sess wayland) == "$t/run/$UID/bus" ]] || fail "a desktop's session bus not listed: $(sess wayland)"
[[ -z $(sess tty) ]] || fail "a text login's bus listed: $(sess tty)"
rm "$t/run/$UID/bus" && ln -s "$t/elsewhere" "$t/run/$UID/bus" && touch "$t/elsewhere"
[[ -z $(sess wayland) ]] || fail "a bus that's a link listed: $(sess wayland)"
rm "$t/run/$UID/bus" && touch "$t/run/$UID/bus"
SESSION_TYPE=wayland AGROS_RUN_USER=$t/run PATH=$t/bin:$PATH "$t/h/agros-each-user" --notify-wait --user "$me" -a X hello ||
    fail "--notify-wait told no one"
grep -qx "told unix:path=$t/run/$UID/bus $t/run/$UID -a X hello" "$t/told" || fail "--notify-wait didn't tell through that bus: $(cat "$t/told")"
echo "ok agros-each-user"
