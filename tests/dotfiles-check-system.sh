#!/usr/bin/env bash
# dotfiles-check's "system files not the repo's any more": what setup installed outside your home (in a stand-in /:
# pacman's hooks, the boot's update and its units, the login screen, NVIDIA early loading, the camera switch...)
# compared by content with what the step would write now (system/render.sh, as setup writes it): nothing said when
# it's all the same, even with the installed files older than the repo's (a fresh clone); a hook missing (added to the
# repo since) or a file that differs said, with the step to run again; on another account than the one setup ran as
# (one user per machine), nothing said about them
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
fail() { echo "FAIL: $*"; exit 1; }
# shellcheck source=/dev/null  # (system/render.sh)
source "$here/system/render.sh"
r=$t/root me=$(id -un)
myhome=$(getent passwd "$me" | cut -d: -f6)
mkdir -p "$r/etc/pacman.d/hooks" "$r/usr/local/bin" "$r/etc/greetd/caelestia-greeter" "$r/etc/mkinitcpio.conf.d" \
    "$r/etc/pam.d" "$r/etc/systemd/system" "$r/etc/udev/rules.d" "$t/bin" "$t/home"
# As setup's system step (and the hardware step, on the Legion) put them there
for in in "$here"/system/pacman-hooks/*.hook.in; do render_hook "$in" "$me" "$myhome" >"$r/etc/pacman.d/hooks/$(basename "$in" .in)"; done
grub_quiet_hook >"$r/etc/pacman.d/hooks/grub-quiet.hook"
render_auto_update "$here" "$me" "$myhome" >"$r/usr/local/bin/auto-update"
a=$here/system/auto-update-setup.sh
for u in auto-update.service auto-update-install.service; do heredoc "$a" "/etc/systemd/system/$u" >"$r/etc/systemd/system/$u"; done
grep -q '^ExecStart=' "$r/etc/systemd/system/auto-update.service" || fail "auto-update.service not found in the setup script"
i=$here/.local/share/caelestia-greeter
# shellcheck disable=SC2016  # (install.sh's own target, as written there)
heredoc "$i/install.sh" '"$dst/run.new"' >"$r/etc/greetd/caelestia-greeter/run"
heredoc "$i/install.sh" /usr/local/bin/login-reset.new >"$r/usr/local/bin/login-reset"
[[ -s $r/etc/greetd/caelestia-greeter/run && -s $r/usr/local/bin/login-reset ]] || fail "the login screen's run or login-reset not found in install.sh"
# (each written beside, then renamed over it, install.sh's and login-reset's config.toml too: cut off, never half a file)
# shellcheck disable=SC2016
! grep -nE '>[[:space:]]*("\$dst/run"|/usr/local/bin/login-reset|/etc/greetd/config\.toml|"\$cfg")([[:space:]]|$)' "$i/install.sh" ||
    fail "install.sh writes the login screen's files in place (above)"
for f in shell.qml best-mode make-theme.sh screenmode.py greetd-pam greetd.pam; do cp "$i/$f" "$r/etc/greetd/caelestia-greeter/"; done
heredoc "$i/install.sh" /etc/pacman.d/hooks/caelestia-greeter-pam.hook >"$r/etc/pacman.d/hooks/caelestia-greeter-pam.hook"
heredoc "$here/system/nvidia-early.sh" /etc/mkinitcpio.conf.d/90-nvidia-early.conf >"$r/etc/mkinitcpio.conf.d/90-nvidia-early.conf"
# (its PAM service as the login screen's greetd-pam makes it from the system's, a stand-in Arch one, the keyring's lines
# after it)
# shellcheck source=/dev/null  # (tests/fixtures/arch-pam.sh)
. "$here/tests/fixtures/arch-pam.sh"
arch_pam "$r/etc/pam.d" "$t/mod"
export PAM_MODULES=$t/mod
echo '-auth optional pam_gnome_keyring.so' >>"$r/etc/pam.d/greetd"
PAM_DIR=$r/etc/pam.d "$i/greetd-pam" >/dev/null || fail "greetd-pam failed on the stand-in Arch stack"
echo '-password optional pam_gnome_keyring.so' >"$r/etc/pam.d/passwd"
c=$here/.local/share/camera-switch
cp "$c/camera-switchd" "$r/usr/local/bin/"
heredoc "$c/install.sh" /etc/systemd/system/camera-switch.service >"$r/etc/systemd/system/camera-switch.service"
heredoc "$c/install.sh" /etc/udev/rules.d/90-camera-switch.rules >"$r/etc/udev/rules.d/90-camera-switch.rules"
# (installed a day before the repo's files were checked out: by content, not by date)
find "$r" -type f -exec touch -d '1 day ago' {} +
# Hyprland, Quickshell: stand-ins (the rest of dotfiles-check isn't this test's)
for s in Hyprland hyprctl qs; do printf '#!/bin/sh\nexit 0\n' >"$t/bin/$s"; done
chmod +x "$t/bin/"*
check() { HOME=$t/home DOTFILES_DIR=$here DOTFILES_CHECK_ROOT=$r PATH=$t/bin:$PATH "$here/.local/bin/dotfiles-check" 2>&1 || true; }

out=$(check)
grep -q "System files" <<<"$out" && fail "installed as the repo has them, still said: $(grep "System files" <<<"$out")"
# A hook added to the repo since (the step run before it was there): missing, said
rm "$r/etc/pacman.d/hooks/hypr-config-check.hook"
out=$(check)
grep -q "System files not the repo's any more (pacman-hooks): run ./setup.sh --only system" <<<"$out" ||
    fail "a missing pacman hook not said: $out"
render_hook "$here/system/pacman-hooks/hypr-config-check.hook.in" "$me" "$myhome" >"$r/etc/pacman.d/hooks/hypr-config-check.hook"
# The boot's update not as the repo would write it now (a change to its setup, or to dotfiles-check's lock holders)
echo "# older" >>"$r/usr/local/bin/auto-update"
echo "x" >>"$r/etc/greetd/caelestia-greeter/run"
echo "x" >>"$r/etc/pacman.d/hooks/grub-quiet.hook"
out=$(check)
grep -q "(login-screen auto-update boot-menu): run ./setup.sh --only system" <<<"$out" || fail "changed system files not said: $out"
render_auto_update "$here" "$me" "$myhome" >"$r/usr/local/bin/auto-update"
# shellcheck disable=SC2016  # (install.sh's own target, as written there)
heredoc "$i/install.sh" '"$dst/run.new"' >"$r/etc/greetd/caelestia-greeter/run"
grub_quiet_hook >"$r/etc/pacman.d/hooks/grub-quiet.hook"
# The login screen's PAM service as greetd had it before (the failure delay on): said
cp "$r/etc/pam.d/greetd" "$t/greetd.ok"
printf '%s\n' '#%PAM-1.0' 'auth include system-local-login' '-auth optional pam_gnome_keyring.so' >"$r/etc/pam.d/greetd"
out=$(check)
grep -q "System files not the repo's any more (login-screen): run ./setup.sh --only system" <<<"$out" ||
    fail "the login screen's PAM service not the repo's, not said: $out"
cp "$t/greetd.ok" "$r/etc/pam.d/greetd"
# system-auth changed (a pambase update) and the login screen's not made again from it (its hook didn't run): said
cp "$r/etc/pam.d/system-auth" "$t/system-auth.ok"
sed -i '/pam_permit.so/i auth       required                    pam_env.so' "$r/etc/pam.d/system-auth"
out=$(check)
grep -q "System files not the repo's any more (login-screen): run ./setup.sh --only system" <<<"$out" ||
    fail "the login screen's PAM service behind system-auth, not said: $out"
cp "$t/system-auth.ok" "$r/etc/pam.d/system-auth"
# The boot's update's unit as an older setup wrote it (the boot's download blocking shutdown): said too
sed -i 's|^ExecStart=|ExecStart=/usr/bin/systemd-inhibit --mode=block |' "$r/etc/systemd/system/auto-update.service"
out=$(check)
grep -q "(auto-update): run ./setup.sh --only system" <<<"$out" || fail "an older auto-update.service not said: $out"
heredoc "$a" /etc/systemd/system/auto-update.service >"$r/etc/systemd/system/auto-update.service"
# The keyring's passwd line missing (set up before it was added); the camera switch's from the hardware step
: >"$r/etc/pam.d/passwd"; echo x >>"$r/usr/local/bin/camera-switchd"; echo x >>"$r/etc/mkinitcpio.conf.d/90-nvidia-early.conf"
out=$(check)
grep -q "(keyring nvidia-early camera-switch): run ./setup.sh --only system hardware" <<<"$out" ||
    fail "the keyring, NVIDIA early loading or the camera switch not said: $out"
# Another account's login (setup ran as someone else: their pacman hooks and boot's update, from their repo): nothing
# said about the system files, even ones that differ (setup run here would only move them to this account)
for in in "$here"/system/pacman-hooks/*.hook.in; do
    render_hook "$in" someone-else /home/someone-else >"$r/etc/pacman.d/hooks/$(basename "$in" .in)"
done
render_auto_update "$here" someone-else /home/someone-else >"$r/usr/local/bin/auto-update"
out=$(check)
grep -q "System files" <<<"$out" && fail "another account's system files said on this one: $(grep "System files" <<<"$out")"
# Only the boot's update to tell whose (no pacman hooks): the same
mv "$r/etc/pacman.d/hooks" "$t/hooks"
out=$(check)
grep -q "System files" <<<"$out" && fail "another account's boot update said on this one: $(grep "System files" <<<"$out")"
mv "$t/hooks" "$r/etc/pacman.d/hooks"
# This account's again, one of them changed: said (the same-user check still on)
for in in "$here"/system/pacman-hooks/*.hook.in; do render_hook "$in" "$me" "$myhome" >"$r/etc/pacman.d/hooks/$(basename "$in" .in)"; done
render_auto_update "$here" "$me" "$myhome" >"$r/usr/local/bin/auto-update"
echo "# older" >>"$r/usr/local/bin/auto-update"
out=$(check)
grep -q "(.*auto-update.*): run ./setup.sh --only system" <<<"$out" || fail "this account's changed boot update not said: $out"
echo "ok dotfiles-check-system"
