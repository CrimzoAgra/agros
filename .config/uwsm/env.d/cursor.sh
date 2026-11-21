# shellcheck shell=sh  # (sourced by uwsm into the session environment)
# The pointer for X11 apps (XWayland: Steam, and Proton and Wine games): Bibata, the desktop's (hypr-vars.lua's
# cursorTheme). Caelestia sets these in Hyprland only (env.lua), and nothing hands them on to the apps (uwsm's finalize,
# which would, isn't run): an X11 app with no theme named took "default", Adwaita's black arrow (Overwatch loading)
export XCURSOR_THEME=Bibata-Modern-Ice XCURSOR_SIZE=24
