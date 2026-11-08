#!/usr/bin/env bash
# Unlocks the passwords keyring (GNOME Keyring) with your login password, so apps like
# Proton VPN and Discord don't ask for the keyring password after you log in.
# Run with: sudo bash system/keyring-setup.sh
# (setup.sh also masks the keyring's own user services, so the one started at login is the one used.)
set -e
[[ $EUID -eq 0 ]] || { echo "Run with sudo"; exit 1; }
pam=/etc/pam.d/greetd
[[ -f $pam ]] || { echo "$pam not found (is greetd installed?)"; exit 1; }
pacman -S --needed --noconfirm gnome-keyring libsecret
if grep -q pam_gnome_keyring "$pam"; then
    echo "Already set up."
else
    cp -n "$pam" "$pam.orig"
    printf '%s\n' '-auth       optional     pam_gnome_keyring.so' \
        '-session    optional     pam_gnome_keyring.so auto_start' >>"$pam"
    echo "Keyring unlocks at login."
fi
# Its password changed with yours (passwd), or the next login can't unlock it
if [[ -f /etc/pam.d/passwd ]] && ! grep -q pam_gnome_keyring /etc/pam.d/passwd; then
    echo '-password   optional     pam_gnome_keyring.so' >>/etc/pam.d/passwd
fi
