#!/usr/bin/env bash
# Faster, cleaner boot. Run with: sudo bash ~/.local/share/boot-tweaks/install.sh
#  1. Splash: same CachyOS animation, but it doesn't wait for the closing animation before
#     showing the login screen (saves ~4 s). Undo: sudo plymouth-set-default-theme -R cachyos-bootanimation
#     Shutting down and restarting say so ("Shutting Down...", "Restarting...", in the system language)
#  2. Login screen update (no text flashing between screens; desktop messages go to the log)
# (The mouse pointer left on the shutdown screen is fixed where it's drawn: hypr-user.lua and the login screen's
# start script draw it as part of the picture, which the splash replaces.)
set -e
[[ $EUID -eq 0 ]] || { echo "Run with sudo"; exit 1; }

src=/usr/share/plymouth/themes/cachyos-bootanimation
dst=/usr/share/plymouth/themes/cachyos-bootanimation-fast
mkdir -p "$dst"
# The shutdown and restart titles in the system language
case $(sed -n 's/^LANG=\(..\).*/\1/p' /etc/locale.conf 2>/dev/null) in
    pt) shut="A encerrar..." restart="A reiniciar..." ;;
    es) shut="Apagando..." restart="Reiniciando..." ;;
    fr) shut="Arrêt en cours..." restart="Redémarrage..." ;;
    de) shut="Wird heruntergefahren..." restart="Neustart..." ;;
    *) shut="Shutting Down..." restart="Restarting..." ;;
esac
# Same images (from the original theme), only the closing animation turned off and the titles added
sed -e 's/^Name=cachyos-bootanimation$/Name=cachyos-bootanimation-fast/' \
    -e '/^\[boot-up\]/,/^\[/ s/^UseEndAnimation=true/UseEndAnimation=false/' \
    -e 's/^TitleFont=.*/TitleFont=Noto Sans Medium 26/' \
    -e "/^\[shutdown\]\$/a _Title=$shut" -e "/^\[reboot\]\$/a _Title=$restart" \
    "$src/cachyos-bootanimation.plymouth" >"$dst/cachyos-bootanimation-fast.plymouth"
grep -A2 -E '^\[(boot-up|shutdown|reboot)\]' "$dst/cachyos-bootanimation-fast.plymouth"
echo "== setting splash theme and rebuilding the boot images (takes a moment)"
plymouth-set-default-theme cachyos-bootanimation-fast
# (not -R: that's plain mkinitcpio, and Limine boots its own copies on the EFI partition, which its tool builds)
if command -v limine-mkinitcpio >/dev/null; then limine-mkinitcpio; else mkinitcpio -P; fi

# The splash draws its text (the titles) only in /usr/share/fonts/Plymouth.ttf and Plymouth-bold.ttf, whatever
# font the theme names. The boot image gets those files; the shutdown splash runs from the system, where they were
# missing, so it showed no text
ln -sf /usr/share/fonts/noto/NotoSans-Medium.ttf /usr/share/fonts/Plymouth.ttf
ln -sf /usr/share/fonts/noto/NotoSans-Bold.ttf /usr/share/fonts/Plymouth-bold.ttf
# The splash goes on into a small image built as the system goes down (mkinitcpio's shutdown-ramfs); Plymouth's own
# hook there copies fonts under their real names only, so the titles were still missing: this hook adds these two
mkdir -p /etc/initcpio/install
cat >/etc/initcpio/install/plymouth-title-font <<'EOF'
#!/bin/bash
# Fonts for the splash's shutdown and restart titles (installed by dotfiles/.local/share/boot-tweaks/install.sh)
build() {
  local f
  for f in /usr/share/fonts/Plymouth.ttf /usr/share/fonts/Plymouth-bold.ttf; do
    [[ -e $f ]] && add_file "$(readlink -f "$f")" "$f"
  done
}
EOF
printf '%s\n' 'w+ /run/initramfs/mkinitcpio-shutdown.conf - - - - HOOKS+=(plymouth-title-font)\n' \
    >/etc/tmpfiles.d/60-plymouth-title-font.conf
systemd-tmpfiles --create /etc/tmpfiles.d/60-plymouth-title-font.conf

echo "== login screen"
bash "$(dirname "$(readlink -f "$0")")/../caelestia-greeter/install.sh"

echo
echo "Done. Reboot to see it."
