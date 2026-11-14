#!/usr/bin/env bash
# agros-vmware's drop-in for Hyprland's uwsm unit (packages/agros-vmware/hyprland-vmw-dmabuf.conf): only its environment,
# no ExecStart= (uwsm's own drop-in, 50_custom.conf, sorts before it: a reset there dropped Hyprland's command), clean for
# systemd beside uwsm's; its ExecStartPre writes the shim's LD_PRELOAD only where vmwgfx is loaded, the session's kept
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
conf=$here/packages/agros-vmware/hyprland-vmw-dmabuf.conf
grep -q '^ExecStart=' "$conf" && fail "the drop-in sets ExecStart= (it drops uwsm's command for Hyprland)"
# systemd-analyze verify, beside uwsm's unit and its runtime drop-in (where uwsm is installed)
if [[ -f /usr/lib/systemd/user/wayland-wm@.service ]] && command -v systemd-analyze >/dev/null; then
    u=$t/units d=$t/units/wayland-wm@hyprland.desktop.service.d
    mkdir -p "$d"
    cp /usr/lib/systemd/user/wayland-wm@.service "$u/"
    cp "$conf" "$d/agros-vmw-dmabuf.conf"
    printf '[Service]\nExecStart=\nExecStart=/usr/bin/uwsm aux exec -- %%I /usr/bin/start-hyprland\n' >"$d/50_custom.conf"
    out=$(cd "$u" && SYSTEMD_UNIT_PATH="$u:" systemd-analyze --user --man=no verify "$u/wayland-wm@hyprland.desktop.service" 2>&1) ||
        fail "systemd-analyze verify: $out"
    [[ -z $out ]] || fail "systemd-analyze verify: $out"
fi
# Its ExecStartPre run as sh would (%t: a runtime folder here, vmwgfx: a file here)
pre=$(sed -n 's/^ExecStartPre=//p' "$conf" | sed "s|%t|$t/run|g; s|/sys/module/vmwgfx|$t/vmwgfx|g; s/\\$\\$/\$/g")
[[ -n $pre ]] || fail "no ExecStartPre"
env=$t/run/agros-vmw-dmabuf.env so=/usr/lib/agros/vmw-dmabuf.so
mkdir -p "$t/run"
pre() { eval "${1:-} $pre" 2>/dev/null; }  # (ld.so: the made-up preloads not there)
pre; [[ ! -e $env ]] || fail "the shim set outside VMware: $(cat "$env")"
touch "$t/vmwgfx"
pre; [[ $(cat "$env") == "LD_PRELOAD=$so" ]] || fail "not the shim in VMware: $(cat "$env")"
pre LD_PRELOAD=/x.so; [[ $(cat "$env") == "LD_PRELOAD=$so:/x.so" ]] || fail "the session's LD_PRELOAD not kept: $(cat "$env")"
# (the file from the last start already read in: the shim not added twice)
pre LD_PRELOAD=$so:/x.so; [[ $(cat "$env") == "LD_PRELOAD=$so:/x.so" ]] || fail "the shim added twice: $(cat "$env")"
rm "$t/vmwgfx"
pre; [[ ! -e $env ]] || fail "the shim left set after leaving VMware: $(cat "$env")"
echo "ok agros-vmware-dropin"
