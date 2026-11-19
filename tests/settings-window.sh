#!/usr/bin/env bash
# The Settings app's window, drawn offscreen (its DOTS_SETTINGS_SHOT picture): on a 1080-high screen every page in its
# list shows, none below the list's end (at 700 high, Startup, Shortcuts and All Caelestia options were, with nothing
# saying more were there); on a 768-high one it fits the screen, and a bar beside the list says it scrolls.
# A long message of a change refused (Capri's keys) wraps under the list, beside an error icon, the list as wide as
# before (it ran under the page, its scroll bar hidden, beside a tick)
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
command -v qs >/dev/null && grep -q 'Material Symbols Rounded' <<<"$(fc-list)" ||
    { echo "ok settings-window (SKIPPED: no Quickshell or Material Symbols font here)"; exit 0; }
# Its command, dots-settings, the repo's, reading the repo's schema and saving nothing of yours (a throwaway HOME: the
# app runs $HOME/.local/bin/dots-settings)
mkdir -p "$t/home/.local/bin"
cat >"$t/home/.local/bin/dots-settings" <<EOF
#!/usr/bin/python3 -I
import importlib.machinery, importlib.util, sys
loader = importlib.machinery.SourceFileLoader("ds", "$here/.local/bin/dots-settings")
ds = importlib.util.module_from_spec(importlib.util.spec_from_loader("ds", loader))
loader.exec_module(ds)
ds.SCHEMA, ds.OPTIONS_QML = "$here/.local/share/dots-settings/schema.json", "$here/.local/share/dots-settings/caelestia-options.qml"
ds.HOME, ds.CONFIG, ds.SETTINGS, ds.CACHE = "$t/home", "$t/dots", "$t/dots/settings.json", "$t/dots/options.json"
ds.main(sys.argv[1:])
EOF
chmod +x "$t/home/.local/bin/dots-settings"
pages=$(jq '.pages | length' "$here/.local/share/dots-settings/schema.json")
# shot <screen height> [app]: the window's picture, on a screen that high (the app: a copy of shell.qml, the repo's)
shot() {
    printf '{"screens": [{"name": "s", "x": 0, "y": 0, "width": 1920, "height": %s, "logicalDpi": 96, "logicalBaseDpi": 96, "dpr": 1}]}' \
        "$1" >"$t/screen.json"
    rm -f "$t/shot.png"
    HOME=$t/home QT_QPA_PLATFORM="offscreen:configfile=$t/screen.json" DOTS_SETTINGS_SHOT=$t/shot.png \
        timeout 60 qs -p "${2:-$here/.config/quickshell/settings/shell.qml}" >"$t/qs.log" 2>&1 || true
    [[ -s $t/shot.png ]] || fail "no picture of the window on a $1-high screen: $(grep -m3 -E 'ERROR|error' "$t/qs.log")"
}
# look <screen height>: "<window height> <page icons in the list> <scroll bar>": the icons counted down the list's
# icon column (a light glyph each, on the dark window, 46 px apart) from below the search field to above the status line, the bar
# by its colour (outlineVariant's fallback, 464750) at the list's right edge
look() {
    python3 -I - "$t/shot.png" <<'P'
import sys
import gi
gi.require_version("GdkPixbuf", "2.0")
from gi.repository import GdkPixbuf
p = GdkPixbuf.Pixbuf.new_from_file(sys.argv[1])
w, h, n, stride, px = p.get_width(), p.get_height(), p.get_n_channels(), p.get_rowstride(), p.get_pixels()
rgb = lambda x, y: tuple(px[y * stride + x * n:y * stride + x * n + 3])
icons, gap = 0, 99  # (a glyph in parts, the lock's: one icon, as the next is 46 px on)
for y in range(140, h - 56):
    if any(sum(rgb(x, y)) > 400 for x in range(30, 58)):
        icons += gap > 12
        gap = 0
    else:
        gap += 1
bar = any(rgb(x, y) == (0x46, 0x47, 0x50) for x in range(226, 240) for y in range(140, h - 56))
print(h, icons, "bar" if bar else "nobar")
P
}
shot 1080
read -r height icons bar < <(look)
((height <= 1080 - 100)) || fail "the window ($height high) doesn't leave room on a 1080-high screen"
((icons == pages)) || fail "$icons of the $pages pages in the list on a 1080-high screen (window $height high): the others below its end"
[[ $bar == nobar ]] || fail "a scroll bar beside a list that fits"
shot 768
read -r height icons bar < <(look)
((height <= 768)) || fail "the window ($height high) taller than a 768-high screen"
((icons < pages)) || fail "every page fits a 768-high screen: the scroll bar not checked"
[[ $bar == bar ]] || fail "no scroll bar beside the list of pages that doesn't fit ($icons of $pages shown)"
# A refusal's message (as the app shows a failed change): the list's search field ends where it did, before the page's
# card (its colour, surfaceContainerHigh's fallback 1e1f26, along its middle row), the message's red (error's fallback,
# ffb4ab, at the status line's 0.7) in more than one line, and the icon beside it red too
mkdir -p "$t/qs" && cp -r "$here/.config/quickshell/settings" "$here/.config/quickshell/common" "$t/qs/"
msg="Screenshot of an area: CTRL + ALT + K is Capri's (her chat): choose other keys"
sed -i "s|^    property string error // |    property string error: \"$msg\" // |" "$t/qs/settings/shell.qml"
grep -q "property string error: \"$msg\"" "$t/qs/settings/shell.qml" || fail "the app's error property not found"
# field: "<search field's right edge> <rows with red in the status line> <red in its icon column>"
field() {
    python3 -I - "$t/shot.png" <<'P'
import sys
import gi
gi.require_version("GdkPixbuf", "2.0")
from gi.repository import GdkPixbuf
p = GdkPixbuf.Pixbuf.new_from_file(sys.argv[1])
w, h, n, stride, px = p.get_width(), p.get_height(), p.get_n_channels(), p.get_rowstride(), p.get_pixels()
rgb = lambda x, y: tuple(px[y * stride + x * n:y * stride + x * n + 3])
red = lambda c: c[0] > 110 and c[0] > c[1] + 35 and c[0] > c[2] + 25
top = next(y for y in range(40, 240) if rgb(100, y) == (0x1e, 0x1f, 0x26))
edge = max(x for x in range(0, 400) if rgb(x, top + 20) == (0x1e, 0x1f, 0x26))
rows = sum(any(red(rgb(x, y)) for x in range(52, 236)) for y in range(h - 120, h))
icon = any(red(rgb(x, y)) for x in range(16, 52) for y in range(h - 120, h))
print(edge, rows, "red" if icon else "grey")
P
}
shot 1080
read -r edge0 _ _ < <(field)
shot 1080 "$t/qs/settings/shell.qml"
read -r edge rows icon < <(field)
((edge == edge0)) || fail "a refusal's long message widened the list of pages: its search field to x $edge, not $edge0"
((rows > 16)) || fail "a refusal's long message in one line ($rows rows with red), cut off, not wrapped"
[[ $icon == red ]] || fail "a refusal's message beside a tick, not an error icon"
echo "ok settings-window"
