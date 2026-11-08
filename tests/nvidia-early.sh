#!/usr/bin/env bash
# agros-nvidia's drop-in: a kernel without the NVIDIA driver (another kernel installed, or this machine's
# without it, as here) still gets its initramfs, the modules optional: mkinitcpio run on its MODULES line, for the
# running kernel, into a throwaway image
set -euo pipefail
. "$(dirname "$0")/lib.sh"
line=$(sed -n 's/^MODULES+=/MODULES=/p' "$here/packages/agros-nvidia/90-agros-nvidia-early.conf")
[[ $line == MODULES=\(*nvidia*\) ]] || fail "the drop-in's MODULES line not found: $line"
command -v mkinitcpio >/dev/null && [[ -d /usr/lib/modules/$(uname -r) ]] || { echo "skip nvidia-early (no mkinitcpio)"; exit 0; }
modinfo nvidia >/dev/null 2>&1 && { echo "skip nvidia-early (this kernel has the driver)"; exit 0; }
printf '%s\nHOOKS=(base)\n' "$line" >"$t/mkinitcpio.conf"
out=$(mkinitcpio -c "$t/mkinitcpio.conf" -k "$(uname -r)" -g "$t/initramfs.img" 2>&1) ||
    fail "a kernel without the driver gets no initramfs: $(grep -i error <<<"$out" | head -3)"
echo "ok nvidia-early"
