#!/usr/bin/env bash
# The NVIDIA driver from the start of the boot (in the initramfs), not once the system is up (about 2 s sooner): the
# boot splash comes up on it. (Not for the fans' full speed at power-on: that's during the motherboard's POST, before
# any of this runs.)
# CachyOS's driver tool (chwd) leaves it out of the initramfs; this adds it in a file of its own, which chwd doesn't
# rewrite. Driver and firmware updates rebuild the initramfs by themselves (mkinitcpio's pacman hook), so it stays in
# step with the rest of the driver.
# Run with: sudo bash system/nvidia-early.sh   (setup.sh asks to run it where an NVIDIA driver is installed)
# Remove: sudo rm /etc/mkinitcpio.conf.d/90-nvidia-early.conf, then sudo limine-mkinitcpio (or mkinitcpio -P)
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Run with sudo"; exit 1; }
# For any kernel: one updated since boot took the running one's modules away, where a bare modinfo looks
found=
for k in /usr/lib/modules/*/; do k=${k%/}; modinfo -k "${k##*/}" nvidia >/dev/null 2>&1 && found=1; done
[[ -n $found ]] || { echo "No NVIDIA driver installed: nothing to do"; exit 0; }
command -v mkinitcpio >/dev/null || { echo "No mkinitcpio (another initramfs tool): nothing done"; exit 0; }
mkdir -p /etc/mkinitcpio.conf.d
cat >/etc/mkinitcpio.conf.d/90-nvidia-early.conf <<'EOF'
# NVIDIA driver in the initramfs (installed by dotfiles/system/nvidia-early.sh)
# ("?": a kernel without the driver, another one installed or one it isn't built for yet, still gets its initramfs)
MODULES+=(nvidia? nvidia_modeset? nvidia_uvm? nvidia_drm?)
EOF
# Limine keeps its own copies of the kernels and initramfs on the EFI partition: its tool builds and puts them there
if command -v limine-mkinitcpio >/dev/null; then limine-mkinitcpio; else mkinitcpio -P; fi
echo "Done: the NVIDIA driver loads early from the next boot."
