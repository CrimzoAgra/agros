# shellcheck shell=sh  # (sourced by uwsm into the session environment)
# Empty on purpose. VMware's vmw-dmabuf shim reaches Hyprland alone, through agros-vmware's drop-in for its uwsm unit
# (wayland-wm@hyprland.desktop.service.d/agros-vmw-dmabuf.conf). Set here, uwsm handed LD_PRELOAD to the user's systemd
# and every app `uwsm app` started loaded it (32-bit ones printed ld.so's errors). Kept, empty, so agros-links replaces
# the copy in each home with this one rather than leaving the old one setting it
