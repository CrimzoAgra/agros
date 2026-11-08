#!/usr/bin/env bash
# Scripts for hardware not every machine has skip cleanly without it (the tools they'd use stubbed and logged):
# bluetooth-on with no adapter (bluetoothctl would wait for bluetoothd forever), camera-test with no camera, mouse-dpi
# without Solaar. With the hardware there, they're used
set -euo pipefail
. "$(dirname "$0")/lib.sh"
mkdir -p "$t/bin"
for c in rfkill bluetoothctl mpv solaar sleep; do
    printf '#!/bin/sh\necho %s >>"%s/called"\n' "$c" "$t" >"$t/bin/$c"; chmod +x "$t/bin/$c"
done
run() { rm -f "$t/called"; HOME=$t PATH=$t/bin:$PATH timeout 20 "$here/.local/bin/$1" >/dev/null 2>&1; }
called() { grep -qx "$1" "$t/called" 2>/dev/null; }
if ls /sys/class/bluetooth/hci* >/dev/null 2>&1; then
    run bluetooth-on || fail "bluetooth-on failed with an adapter"
    called bluetoothctl || fail "bluetooth-on: the adapter not powered on"
else
    run bluetooth-on || fail "bluetooth-on failed without an adapter"
    ! called bluetoothctl || fail "bluetooth-on: bluetoothctl run without an adapter"
fi
if ls /dev/video* >/dev/null 2>&1; then
    run camera-test || true
    called mpv || fail "camera-test: a camera there, no preview"
else
    if run camera-test; then fail "camera-test: no camera, reported success"; fi
    ! called mpv || fail "camera-test: mpv started with no camera"
fi
rm "$t/bin/solaar"
run mouse-dpi || fail "mouse-dpi failed without Solaar"
# With Solaar and a mouse: the DPI as dots-settings gives it (a value saved that's no longer a choice: its default,
# "Own", the mouse left on its profile), not read from the settings file itself
cat >"$t/bin/solaar" <<S
#!/bin/sh
echo "solaar \$*" >>"$t/called"
case "\$1 \$3" in "show ") echo "  1: Mouse" ;; "config dpi_extended") [ -z "\$4" ] ;; esac
exit 0
S
chmod +x "$t/bin/solaar"
mkdir -p "$t/mdpi"; cp "$here/.local/bin/mouse-dpi" "$t/mdpi/"
for want in '""' '"800"'; do
    # shellcheck disable=SC2016  # (expanded by the stand-in)
    printf '#!/bin/sh\n[ "$1 $2" = "get input.mouse_dpi" ] && echo %s\n' "'$want'" >"$t/mdpi/dots-settings"; chmod +x "$t/mdpi/dots-settings"
    rm -f "$t/called"
    HOME=$t PATH=$t/bin:$PATH timeout 20 "$t/mdpi/mouse-dpi" >/dev/null 2>&1 || fail "mouse-dpi failed"
    if [[ $want == '""' ]]; then
        grep -q "dpi_extended X" "$t/called" && fail "a DPI set with none chosen (Own): $(cat "$t/called")"
    else
        grep -q "dpi_extended X 800" "$t/called" || fail "the chosen DPI not set: $(cat "$t/called")"
    fi
done
# dots-settings' own answer for a value saved that's no longer one of the choices: the default
python3 -I - "$here" "$t" <<'P' || fail "a stale mouse DPI not read as the default"
import importlib.machinery, importlib.util, json, sys
here, t = sys.argv[1:]
loader = importlib.machinery.SourceFileLoader("ds", f"{here}/.local/bin/dots-settings")
ds = importlib.util.module_from_spec(importlib.util.spec_from_loader("ds", loader))
loader.exec_module(ds)
ds.SCHEMA, ds.SETTINGS = f"{here}/.local/share/dots-settings/schema.json", f"{t}/settings.json"
json.dump({"input.mouse_dpi": "12345"}, open(ds.SETTINGS, "w"))
s = ds.all_settings(ds.schema())["input.mouse_dpi"]
sys.exit(0 if ds.current(s, ds.stored()) == s["default"] == "" else 1)
P
echo "ok hardware-skip"
