#!/usr/bin/env bash
# ~/.config/uwsm/env.d/nvidia-vaapi.sh (sourced by sh at login), on a stand-in /sys and driver folder: VA-API on the
# NVIDIA card only when that card drives a connected screen (a desktop on it, or a screen plugged into it); a laptop
# showing the desktop on its other GPU keeps VA-API there (the NVIDIA card left asleep); without NVIDIA's VA-API driver,
# nothing. Nothing of its own left in the session's environment
set -euo pipefail
. "$(dirname "$0")/lib.sh"
drm=$t/sys/class/drm
mkdir -p "$t/dri" "$t/bus/drivers/i915" "$t/bus/drivers/nvidia"
sed -e "s|/usr/lib/dri|$t/dri|g" -e "s|/sys/class/drm|$drm|g" "$here/.config/uwsm/env.d/nvidia-vaapi.sh" >"$t/env.sh"
grep -q "$drm" "$t/env.sh" || fail "the screen check not found in nvidia-vaapi.sh"
if command -v shellcheck >/dev/null; then
    out=$(shellcheck -s sh "$here/.config/uwsm/env.d/nvidia-vaapi.sh") || fail "shellcheck: $out"
fi
# card <n> <driver> <connector> <status>: a GPU on that driver with one screen connector
card() {
    mkdir -p "$drm/card$1/device" "$drm/card$1-$3"
    ln -sfn "$t/bus/drivers/$2" "$drm/card$1/device/driver"
    echo "$4" >"$drm/card$1-$3/status"
}
# What the session gets: under sh (bash on Arch) and, when there, dash (a strict POSIX sh)
env_of() {
    local sh=$1
    # shellcheck disable=SC2016  # (expanded by that sh)
    env -u LIBVA_DRIVER_NAME -u NVD_BACKEND -u MOZ_DISABLE_RDD_SANDBOX "$sh" -c \
        '. "$1"; echo "${LIBVA_DRIVER_NAME-}|${NVD_BACKEND-}|${MOZ_DISABLE_RDD_SANDBOX-}|${_nv_on-}${_nv_s-}${_nv_c-}${_nv_st-}"' _ "$t/env.sh"
}
shells=(sh); command -v dash >/dev/null && shells+=(dash)
expect() {
    local s
    for s in "${shells[@]}"; do [[ $(env_of "$s") == "$1" ]] || fail "$2 ($s): $(env_of "$s")"; done
}
on="nvidia|direct|1|"
# A laptop: the built-in screen on the Intel GPU, nothing on the NVIDIA card's HDMI
card 1 i915 eDP-1 connected
card 2 nvidia HDMI-A-1 disconnected
touch "$t/dri/nvidia_drv_video.so"
expect "|||" "hybrid laptop on its iGPU: VA-API sent to the NVIDIA card"
# A screen plugged into the NVIDIA card's HDMI: it draws that one, VA-API on it
echo connected >"$drm/card2-HDMI-A-1/status"
expect "$on" "a screen on the NVIDIA card: VA-API not on it"
# A desktop with only the NVIDIA card
rm -r "$drm"/card1 "$drm"/card1-*
card 0 nvidia DP-1 connected
echo disconnected >"$drm/card2-HDMI-A-1/status"
expect "$on" "NVIDIA-only desktop: VA-API not on it"
# Its VA-API driver not installed: nothing set
rm "$t/dri/nvidia_drv_video.so"
expect "|||" "no NVIDIA VA-API driver, still set"
# No DRM connectors at all (the glob unmatched): nothing set, nothing printed
touch "$t/dri/nvidia_drv_video.so"; rm -r "${drm:?}"/*; mkdir -p "$drm"
[[ -z $(sh -c '. "$1"' _ "$t/env.sh" 2>&1) ]] || fail "messages with no connectors"
expect "|||" "no connectors, still set"
echo "ok nvidia-vaapi"
