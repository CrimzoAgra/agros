# shellcheck shell=sh  # (sourced by uwsm into the session environment)
# Video decoding on the NVIDIA card (VA-API through libva-nvidia-driver) for the browser: without these LibreWolf decodes
# YouTube on the CPU and the GPU boosts just to draw the frames. Only where that driver is in (on another GPU these would
# break VA-API), and only when the NVIDIA card drives a screen (nvidia-screen, as the desktop widgets' stats panel): on
# a laptop that shows the desktop on its other GPU, every video would wake the NVIDIA card and drain the battery, so
# VA-API is left to that GPU. MOZ_DISABLE_RDD_SANDBOX: the decoder process's sandbox blocks the NVIDIA driver
# (nvidia-screen by its installed path first: this is read as the session starts, maybe before agros-links has linked a
# helper an update brought into ~/.local/bin; there, for a home set up without the package)
if [ -e /usr/lib/dri/nvidia_drv_video.so ]; then
    for _nv in /usr/lib/agros/bin/nvidia-screen "$HOME/.local/bin/nvidia-screen"; do
        [ -x "$_nv" ] && break
    done
    if "$_nv" 2>/dev/null; then
        export LIBVA_DRIVER_NAME=nvidia
        export NVD_BACKEND=direct
        export MOZ_DISABLE_RDD_SANDBOX=1
    fi
    unset _nv
fi
