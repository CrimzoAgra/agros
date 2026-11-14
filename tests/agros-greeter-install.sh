#!/usr/bin/env bash
# agros-greeter's install script (packages/agros-greeter/agros-greeter.install) in a throwaway root (AGROS_ROOT), its
# tools stand-ins: install keeps greetd's config and PAM service aside, notes the display manager it takes over from
# and the user it shows (agros-each-user's first); removal puts greetd's config and PAM back and that display manager
# on, or, with none noted, greetd's stock text login (none kept) and a note of how to pick another; what the login
# screen made itself goes
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
r=$t/root
export AGROS_ROOT=$r
g=$r/etc/greetd/caelestia-greeter
mkdir -p "$g/theme" "$r/etc/pam.d" "$r/etc/systemd/system" "$r/usr/lib/agros/bin" "$r/var/lib/caelestia-greeter" "$t/bin"
cp "$here/packages/agros-greeter/config.toml" "$g/greetd-config.toml"
: >"$g/env"
printf '#!/bin/sh\ncase "$1" in --list) printf "%%s\\n" alice bob ;; --as) echo "as $*" >>%s/calls ;; esac\n' "$t" >"$r/usr/lib/agros/bin/agros-each-user"
# greetd-pam: the system's kept aside as greetd.orig, its own written
printf '#!/bin/sh\ncp %s/greetd %s/greetd.orig; echo agros-pam >%s/greetd\n' "$r/etc/pam.d" "$r/etc/pam.d" "$r/etc/pam.d" >"$g/greetd-pam"
for x in systemctl systemd-tmpfiles runuser; do printf '#!/bin/sh\necho "%s $*" >>%s/calls\n' "$x" "$t" >"$t/bin/$x"; done
chmod +x "$t/bin/"* "$g/greetd-pam" "$r/usr/lib/agros/bin/agros-each-user"
export PATH=$t/bin:$PATH
# shellcheck source=../packages/agros-greeter/agros-greeter.install
. "$here/packages/agros-greeter/agros-greeter.install"
pac() { (set +e; "$@"); }
setup() {
    echo 'command = "agreety --cmd /bin/sh"' >"$r/etc/greetd/config.toml"
    echo 'auth include system-login' >"$r/etc/pam.d/greetd"
    rm -f "$t/calls" "$r/etc/greetd/config.toml.agros-orig" "$r/etc/pam.d/greetd.orig"
}

# Taking over from SDDM, and back
setup
ln -sf /usr/lib/systemd/system/sddm.service "$r/etc/systemd/system/display-manager.service"
pac post_install >/dev/null
grep -q caelestia-greeter "$r/etc/greetd/config.toml" && grep -q agreety "$r/etc/greetd/config.toml.agros-orig" ||
    fail "greetd not pointed at the login screen, its own config kept aside"
[[ $(cat "$r/var/lib/agros/display-manager") == sddm.service ]] || fail "SDDM not noted"
grep -qx 'CAELESTIA_GREETER_USER=alice' "$g/env" || fail "not the first AgrOS user shown: $(cat "$g/env")"
grep -qx "as --as alice $g/make-theme.sh $g/theme alice" "$t/calls" || fail "the theme not made as alice through agros-each-user --as: $(cat "$t/calls")"
grep -q '^runuser' "$t/calls" && fail "runuser used (its PAM opens a logind session)"
grep -q pam_gnome_keyring "$r/etc/pam.d/greetd" || fail "the keyring's lines not in greetd's PAM service"
echo x >"$g/theme/theme.json"
out=$(pac post_remove)
grep -q agreety "$r/etc/greetd/config.toml" && [[ ! -e $r/etc/greetd/config.toml.agros-orig ]] || fail "greetd's config not put back"
[[ $(cat "$r/etc/pam.d/greetd") == 'auth include system-login' && ! -e $r/etc/pam.d/greetd.orig ]] || fail "greetd's PAM service not put back"
grep -qx 'systemctl enable -f sddm.service' "$t/calls" && [[ ! -e $r/var/lib/agros/display-manager ]] || fail "SDDM not back on: $(cat "$t/calls")"
[[ -z $out ]] || fail "a note with SDDM back: $out"
[[ ! -e $g/theme && ! -e $r/var/lib/caelestia-greeter ]] || fail "the login screen's own files left"

# greetd the one before (an AgrOS install), with no config of its own kept (installed before that was kept): greetd's
# stock text login, not one pointing at the removed login screen, and how to pick another said
setup
ln -sf /usr/lib/systemd/system/greetd.service "$r/etc/systemd/system/display-manager.service"
pac post_install >/dev/null
[[ ! -e $r/var/lib/agros/display-manager ]] || fail "greetd noted as the one to put back"
rm "$r/etc/greetd/config.toml.agros-orig"
out=$(pac post_remove)
grep -qx 'command = "agreety --cmd /bin/sh"' "$r/etc/greetd/config.toml" && ! grep -q caelestia "$r/etc/greetd/config.toml" ||
    fail "greetd left pointing at the removed login screen: $(cat "$r/etc/greetd/config.toml")"
[[ $out == *"greetd stays the login screen"*"systemctl enable -f"* ]] || fail "no note of how to pick another: $out"
! grep -q 'systemctl enable' <<<"$(grep -v greetd.service "$t/calls")" || fail "a display manager turned on: $(cat "$t/calls")"
# login-reset's text login (into hyprland-session, removed with the package), no config kept: the stock one too
setup
pac post_install >/dev/null
rm "$r/etc/greetd/config.toml.agros-orig"
printf '%s\n' '[default_session]' 'command = "agreety --cmd hyprland-session"' >"$r/etc/greetd/config.toml"
pac post_remove >/dev/null
grep -qx 'command = "agreety --cmd /bin/sh"' "$r/etc/greetd/config.toml" ||
    fail "greetd left starting the removed hyprland-session: $(cat "$r/etc/greetd/config.toml")"
echo "ok agros-greeter-install"
