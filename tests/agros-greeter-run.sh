#!/usr/bin/env bash
# agros-greeter's run (packages/agros-greeter/run, greetd's command), its paths moved into a throwaway folder and cage,
# dbus-run-session, agreety and the rest stand-ins: the login screen shown the user env names, else (a new install:
# agros-greeter's install ran before the installer made the account, so env names no one, and no login has written its
# theme) the first AgrOS account, never no one ("No user set", no way to log in); in VMware with agros-vmware cage gets
# the vmw-dmabuf shim, in another VM software OpenGL; a login screen that closes without a login falls back to greetd's
# text login. login-reset (the way back from a broken login screen, from a text console) puts greetd's text login into
# hyprland-session in place, whole, and restarts greetd; --back the login screen's config; not as root, nothing changed
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

# login-reset, its greetd folder a throwaway one; root by a stand-in id ($UID0)
mkdir -p "$t/etc/greetd" && cp "$here/packages/agros-greeter/config.toml" "$t/g/greetd-config.toml"
sed -e "s|/etc/greetd|$t/etc/greetd|g" "$here/packages/agros-greeter/login-reset" >"$t/login-reset"
sed -i "s|$t/etc/greetd/caelestia-greeter|$t/g|g" "$t/login-reset"
# shellcheck disable=SC2016  # (expanded by the stand-ins)
printf '#!/bin/sh\n[ -n "$UID0" ] && echo 0 || echo 1000\n' >"$t/bin/id"
printf '#!/bin/sh\necho "systemctl $*" >>%s/calls\n' "$t" >"$t/bin/systemctl"
chmod +x "$t/login-reset" "$t/bin/id" "$t/bin/systemctl"
echo 'mine' >"$t/etc/greetd/config.toml"; rm -f "$t/calls"
out=$("$t/login-reset") && fail "login-reset ran without root"
[[ $out == "Run: sudo login-reset" && $(cat "$t/etc/greetd/config.toml") == mine && ! -e $t/calls ]] ||
    fail "login-reset without root: $out"
UID0=1 "$t/login-reset"
[[ $(cat "$t/etc/greetd/config.toml") == "$(printf '%s\n' '[terminal]' 'vt = 1' '' '[default_session]' \
    'command = "agreety --cmd hyprland-session"' 'user = "greeter"')" && ! -e $t/etc/greetd/config.toml.new ]] ||
    fail "login-reset's text login: $(cat "$t/etc/greetd/config.toml")"
grep -qx 'systemctl restart greetd' "$t/calls" || fail "greetd not restarted: $(cat "$t/calls")"
UID0=1 "$t/login-reset" --back
cmp -s "$t/etc/greetd/config.toml" "$here/packages/agros-greeter/config.toml" || fail "--back: $(cat "$t/etc/greetd/config.toml")"
# (the text login's command is agros-greeter's, installed as /usr/bin/hyprland-session: uwsm's Hyprland)
grep -qx 'exec uwsm start -e -D Hyprland hyprland.desktop' "$here/packages/agros-greeter/hyprland-session" &&
    grep -q '"$pkgdir/usr/bin/hyprland-session"' "$here/packages/agros-greeter/PKGBUILD" || fail "hyprland-session not uwsm's Hyprland"
echo "ok agros-greeter-run"
