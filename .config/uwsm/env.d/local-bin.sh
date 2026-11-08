# shellcheck shell=sh  # (sourced by uwsm into the session environment)
# ~/.local/bin (these dotfiles' scripts) on the desktop's PATH: uwsm builds Hyprland's environment from the login's,
# whose PATH replaces the one environment.d gives systemd (10-local-bin.conf), so it's added again here. (env.d: uwsm
# loads every file in it; ~/.config/uwsm/env itself is Caelestia's)
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH" ;; esac
