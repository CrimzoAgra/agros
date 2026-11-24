#!/usr/bin/env bash
# XWayland's primary screen: the Settings app's main screen, else the one with workspace 1; nothing outside Hyprland
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
mkdir -p "$t/bin" "$t/home/.config/dots"
cat >"$t/bin/hyprctl" <<'EOF'
#!/bin/sh
case $2 in
monitors) echo '[{"name":"DP-1","description":"X Big 1"},{"name":"HDMI-A-1","description":"Y Small 2"}]' ;;
workspaces) echo '[{"id":1,"monitor":"HDMI-A-1"},{"id":11,"monitor":"DP-1"}]' ;;
esac
EOF
printf '#!/bin/sh\necho "$*" >>"%s/xrandr"\n' "$t" >"$t/bin/xrandr"
chmod +x "$t/bin/hyprctl" "$t/bin/xrandr"
run() { : >"$t/xrandr"; HOME=$t/home PATH=$t/bin:$PATH "$here/.local/bin/xwayland-primary"; cat "$t/xrandr"; }
[[ $(run) == "--output HDMI-A-1 --primary" ]] || fail "no main screen set: not the one with workspace 1: $(run)"
echo '{"screens.main":"X Big 1"}' >"$t/home/.config/dots/settings.json"
[[ $(run) == "--output DP-1 --primary" ]] || fail "the Settings app's main screen not primary: $(run)"
printf '#!/bin/sh\nexit 1\n' >"$t/bin/hyprctl"
[[ -z $(run) ]] || fail "outside Hyprland it still set one: $(run)"
echo "ok xwayland-primary"
