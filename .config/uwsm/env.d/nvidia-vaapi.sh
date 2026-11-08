# shellcheck shell=sh  # (sourced by uwsm into the session environment)
# Video decoding on the NVIDIA card (VA-API through libva-nvidia-driver) for the browser: without these LibreWolf decodes
# YouTube on the CPU and the GPU boosts just to draw the frames. Only where that driver is in (on another GPU these would
# break VA-API), and only when the NVIDIA card drives a screen (as the bar's GPU meter, widgets/shell.qml): on a laptop
# that shows the desktop on its other GPU, every video would wake the NVIDIA card and drain the battery, so VA-API is
# left to that GPU. MOZ_DISABLE_RDD_SANDBOX: the decoder process's sandbox blocks the NVIDIA driver
if [ -e /usr/lib/dri/nvidia_drv_video.so ]; then
    _nv_on=
    for _nv_s in /sys/class/drm/card*-*/status; do
        # (read: a builtin, no process per connector; this runs at every login)
        read -r _nv_st 2>/dev/null <"$_nv_s" || continue
        [ "$_nv_st" = connected ] || continue
        _nv_c=${_nv_s%/*}; _nv_c=${_nv_c##*/}
        case $(readlink "/sys/class/drm/${_nv_c%%-*}/device/driver") in */nvidia) _nv_on=1; break ;; esac
    done
    if [ -n "$_nv_on" ]; then
        export LIBVA_DRIVER_NAME=nvidia
        export NVD_BACKEND=direct
        export MOZ_DISABLE_RDD_SANDBOX=1
    fi
    unset _nv_on _nv_s _nv_st _nv_c
fi
