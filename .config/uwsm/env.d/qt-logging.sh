# shellcheck shell=sh  # (sourced by uwsm into the session environment)
# Qt's Wayland text input warns "Trying to disable ... but 0x0 is focused" each time a Quickshell window that took the
# keyboard closes (the switcher, hundreds a day): a harmless Qt bug, silenced for the desktop's Qt apps
export QT_LOGGING_RULES="${QT_LOGGING_RULES:+$QT_LOGGING_RULES;}qt.qpa.wayland.textinput.warning=false"
