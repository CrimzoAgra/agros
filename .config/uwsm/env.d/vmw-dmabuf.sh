# shellcheck shell=sh  # (sourced by uwsm into the session environment)
# In a VMware virtual machine (its vmwgfx driver loaded): Hyprland with agros-vmware's vmw-dmabuf shim, so it accepts
# the apps' GPU buffers on VMware's virtual GPU and the whole desktop draws there (without it every GPU app was
# dropped, or ran on the CPU). Only Hyprland: hypr-vars.lua clears it again for the apps it starts. Nowhere else
if [ -e /sys/module/vmwgfx ] && [ -e /usr/lib/agros/vmw-dmabuf.so ]; then
    export LD_PRELOAD=/usr/lib/agros/vmw-dmabuf.so
fi
