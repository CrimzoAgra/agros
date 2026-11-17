#!/usr/bin/env bash
# agros-greeter's run (packages/agros-greeter/run, greetd's command), its paths moved into a throwaway folder and cage,
# dbus-run-session, agreety and the rest stand-ins: the login screen shown the user env names, else (a new install:
# agros-greeter's install ran before the installer made the account, so env names no one, and no login has written its
# theme) the first AgrOS account, never no one ("No user set", no way to log in); in VMware with agros-vmware cage gets
# the vmw-dmabuf shim, in another VM software OpenGL; a login screen that closes without a login falls back to greetd's
# text login
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
mkdir -p "$t/g" "$t/state" "$t/cache" "$t/lib/bin" "$t/bin"
sed -e "s|/etc/greetd/caelestia-greeter|$t/g|g" -e "s|/var/lib/caelestia-greeter|$t/state|g" \
    -e "s|/var/cache/caelestia-greeter|$t/cache|g" -e "s|/var/log/caelestia-greeter.log|$t/log|g" \
    -e "s|/usr/lib/agros|$t/lib|g" -e "s|/sys/module/vmwgfx|$t/vmwgfx|g" -e "s|/dev/tty|$t/tty|g" \
    -e "s|/etc/X11/xorg.conf.d/00-keyboard.conf|$t/kb.conf|g" "$here/packages/agros-greeter/run" >"$t/run"
: >"$t/tty"
# (none of the machine's own files left in it: the icons and /tmp, only read or made anew, aside)
! sed '/^ *#/d' "$t/run" | grep -E '/(etc|var)/|/usr/lib|/dev/tty|/sys/' || fail "run still names one of the machine's files"
# The AgrOS accounts ($USERS, one a line)
# shellcheck disable=SC2016  # (expanded by the stand-in)
printf '#!/bin/sh\n[ "$1" = --list ] && [ -n "$USERS" ] && printf "%%s\\n" $USERS\nexit 0\n' >"$t/lib/bin/agros-each-user"
# The login screen: what it was started with noted (its user, cage's shim, software OpenGL); it says it's up and, unless
# $NO_LOGIN, starts a session (the launch time it writes)
cat >"$t/bin/dbus-run-session" <<EOF
#!/bin/sh
{ echo "user=\$CAELESTIA_GREETER_USER soft=\${LIBGL_ALWAYS_SOFTWARE:-}"; echo "args=\$*"; } >"$t/seen"
: >"\$XDG_RUNTIME_DIR/caelestia-greeter-ready"
[ -n "\${NO_LOGIN:-}" ] || date +%s%N >"$t/state/caelestia-greeter-last-launch"
EOF
# shellcheck disable=SC2016
printf '#!/bin/sh\nexec "$@"\n' >"$t/bin/setsid"
printf '#!/bin/sh\necho "agreety $*" >>%s/calls\n' "$t" >"$t/bin/agreety"
# shellcheck disable=SC2016  # (expanded by the stand-in)
printf '#!/bin/sh\n[ -n "$VM" ]\n' >"$t/bin/systemd-detect-virt"
chmod +x "$t/bin/"* "$t/lib/bin/agros-each-user" "$t/run"
export PATH=$t/bin:$PATH
run() { : >"$t/g/env"; [[ -z ${1:-} ]] || echo "$1" >"$t/g/env"; rm -f "$t/seen" "$t/calls"; "$t/run"; }

# env names the user: that one
USERS="alice bob" run CAELESTIA_GREETER_USER=carol
grep -qx 'user=carol soft=' "$t/seen" || fail "env's user not the one shown: $(cat "$t/seen")"
# env names none (a new install): the first AgrOS account
USERS="alice bob" run
grep -qx 'user=alice soft=' "$t/seen" || fail "no user shown with env naming none (a new install can't log in): $(cat "$t/seen")"
[[ ! -e $t/calls ]] || fail "a login fell back to the text login: $(cat "$t/calls")"
# No account at all: started all the same, no one named
USERS='' run
grep -qx 'user= soft=' "$t/seen" || fail "no accounts: $(cat "$t/seen")"
# VMware's driver with agros-vmware's shim: cage with it; another VM: software OpenGL, no shim
mkdir "$t/vmwgfx" && : >"$t/lib/vmw-dmabuf.so"
VM=1 USERS=alice run
grep -q "^args=.*LD_PRELOAD=$t/lib/vmw-dmabuf.so cage " "$t/seen" && grep -qx 'user=alice soft=' "$t/seen" ||
    fail "VMware: cage not started with the shim: $(cat "$t/seen")"
rmdir "$t/vmwgfx"
VM=1 USERS=alice run
grep -qx 'user=alice soft=1' "$t/seen" && ! grep -q LD_PRELOAD= "$t/seen" || fail "another VM: $(cat "$t/seen")"
# Closed without a login (a crash after its first frame): greetd's text login
NO_LOGIN=1 USERS=alice run >/dev/null
grep -qx 'agreety --cmd hyprland-session' "$t/calls" || fail "no text login after the login screen closed without one"
echo "ok agros-greeter-run"
