#!/usr/bin/env bash
# The Caelestia overlay against the installed Caelestia (and its main, fetched), in a throwaway home: every patch still
# fits, runs at once don't lose the folder, one failing patch skips only itself, a broken patch.py leaves the shell as
# it was
set -euo pipefail
. "$(dirname "$0")/lib.sh"
[[ -d /etc/xdg/quickshell/caelestia ]] || { echo "skip caelestia-overlay (Caelestia not installed)"; exit 0; }
run() { HOME=$t XDG_STATE_HOME=$t/state PATH=$t/bin:$PATH DOTS_SETTINGS=$t/bin/dots-settings "$here/.local/bin/caelestia-overlay" 2>&1; }
mkdir -p "$t/.local/share" "$t/bin"
# Your Settings app choices don't reach the test: every feature on, unless $t/off names one
cat >"$t/bin/dots-settings" <<S
#!/bin/sh
if [ -s "$t/off" ]; then echo "{\"caelestia.\$(cat "$t/off")\": false}"; else echo "{}"; fi
S
chmod +x "$t/bin/dots-settings"
# The broken patches below are on purpose: their warnings mustn't reach your desktop
printf '#!/bin/sh\nexit 0\n' >"$t/bin/notify-send"; chmod +x "$t/bin/notify-send"
cp -r "$here/.local/share/caelestia-overlay" "$t/.local/share/"
dst=$t/.config/quickshell/caelestia skipped=$t/state/caelestia-overlay-skipped

out=$(run) || fail "overlay failed: $(tail -3 <<<"$out")"
grep -q '^WARNING\|Traceback' <<<"$out" && fail "patches no longer fit: $(grep '^WARNING' <<<"$out")"
[[ -d $dst && ! -s $skipped ]] || fail "not installed"
# The notification sidebar closes on a curve that doesn't overshoot (opens as before), and its hover edge doesn't open
# it while a pop-up shows, nor afterwards for a pointer that stayed there until it leaves (the window too)
w=$dst/modules/sidebar/Wrapper.qml i=$dst/modules/drawers/Interactions.qml
grep -q 'type: offsetBehavior.targetValue > 0.5 ? Anim.Emphasized : Anim.DefaultSpatial' "$w" ||
    fail "the sidebar's close curve not changed: $(grep -A6 'Behavior on offsetScale' "$w")"
{ [[ $(grep -c 'root.sidebarHoverOpens(showSidebarHover) && !screenState.sidebar' "$i") == 2 ]] &&
    grep -A2 'if (!containsMouse) {' "$i" | grep -q 'sidebarHoverHeld = false'; } || fail "the sidebar's hover edge not gated on pop-ups"
if command -v node >/dev/null; then
    fn=$(sed -n '/^    function sidebarHoverOpens(atEdge: bool): bool {$/,/^    }$/p' "$i" | sed 's/(atEdge: bool): bool {/(atEdge) {/')
    seq=$(node -e "let sidebarHoverHeld = false; const panels = { notifications: { height: 0 } };
$fn
const r = [];
panels.notifications.height = 120; r.push(sidebarHoverOpens(true));  // a pop-up showing, at the edge
panels.notifications.height = 0; r.push(sidebarHoverOpens(true));    // it's gone, the pointer still there
r.push(sidebarHoverOpens(false));                                    // the pointer leaves the edge
r.push(sidebarHoverOpens(true));                                     // and comes back
console.log(r.join(' '));")
    [[ $seq == "false false false true" ]] || fail "the sidebar's hover edge with a pop-up: $seq (want: false false false true)"
fi
# ...let go of wherever the pointer leaves the edge: every move, before the paths that return early (a detached popout,
# fullscreen) or don't test it (the power menu open, a button held), by the same edge Caelestia's hover tests; and held
# by a pop-up coming up under a pointer resting there
sidebar_edge_released() { # <Interactions.qml>
    local edge fn
    grep -A1 '^    onPositionChanged: event => {$' "$1" | tail -1 | grep -q '^        root.sidebarHoverOpens(root.atSidebarEdge(event.x, event.y));' ||
        { echo "not the first thing each move does: $(grep -A2 'onPositionChanged: event => {' "$1")"; return; }
    edge=$(sed -n 's/^ *const showSidebarHover = \(.*\);$/\1/p' "$1" | sort -u)
    fn=$(sed -n '/^    function atSidebarEdge(x: real, y: real): bool {$/,/^    }$/p' "$1")
    [[ $(wc -l <<<"$edge") == 1 ]] && grep -qF "return $edge;" <<<"$fn" || { echo "its edge isn't the hover's: $fn / $edge"; return; }
    if grep -q sidebarTriggerY <<<"$edge"; then
        grep -qF "$(grep -m1 'const sidebarTriggerY = ' "$1" | sed 's/^ *//')" <<<"$fn" || { echo "its trigger height isn't the hover's: $fn"; return; }
    fi
    grep -A3 'function onHeightChanged() {' "$1" | grep -q 'root.sidebarHoverOpens(root.atSidebarEdge(root.mouseX, root.mouseY))' &&
        grep -q '^        target: root.panels.notifications$' "$1" || echo "not held by a pop-up under a resting pointer"
}
r=$(sidebar_edge_released "$i"); [[ -z $r ]] || fail "the sidebar's hover edge not let go on every path: $r"
# Its grey card hangs from the top border when it slides down from the top: flush with it, top corners square
c=$dst/modules/sidebar/Content.qml
{ grep -q 'topLeftRadius: 0' "$c" && grep -q 'topRightRadius: 0' "$c" && grep -q 'anchors.topMargin: 0' "$w"; } ||
    fail "the sidebar's card not flush with the top border: $(grep -n 'Radius\|topMargin' "$c" "$w")"
# ...and its top stays on the border as the opening curve overshoots (an inward notch at its top-left for a moment)
grep -q 'anchors.topMargin: -notifications.anchors.topMargin - Math.max(0, slide)' "$dst/modules/drawers/Panels.qml" ||
    fail "the sidebar's top not held on the border past the end of its opening"
# Window peek: its pictures in the drawers' window, its service, and the previews that set it (the dock's single
# window and its tiles: that window; the workspace preview: its whole workspace)
{ grep -q 'PeekLayer {' "$dst/modules/drawers/ContentWindow.qml" && [[ -f $dst/modules/drawers/PeekLayer.qml && -f $dst/services/WindowPeek.qml ]] &&
    [[ $(grep -c 'WindowPeek.enter(' "$dst/modules/bar/popouts/DockMenu.qml") == 2 ]] &&
    grep -q 'peeked = root.workspace;' "$dst/modules/bar/popouts/WorkspacePreview.qml" &&
    grep -q 'WindowPeek.enter(peeked)' "$dst/modules/bar/popouts/WorkspacePreview.qml" &&
    grep -q 'dots.peek_screen(' "$dst/services/WindowPeek.qml" && grep -q 'ws.toplevels.values' "$dst/services/WindowPeek.qml"; } ||
    fail "window peek not patched in"
# ...its pictures over the real desktop (wallpaper and widgets: Hyprland fades out the windows there), no picture of
# the wallpaper over it
! grep -q 'Image {' "$dst/modules/drawers/PeekLayer.qml" || fail "window peek's pictures hide the desktop's widgets"
# ...and a hyprctl that failed (Hyprland not ready at the shell's start) tried again, not taken as done
{ grep -q 'if (code === 0) {' "$dst/services/WindowPeek.qml" && grep -A3 'id: retry' "$dst/services/WindowPeek.qml" | grep -q 'interval: 2000'; } ||
    fail "window peek takes a failed hyprctl as done"
# ...each time later, up to a minute (a config without it for good: not a hyprctl every 2 s all session)
grep -q 'retry.interval = Math.min(retry.interval \* 2, 60000);' "$dst/services/WindowPeek.qml" ||
    fail "window peek retries a failing hyprctl every 2 s for good"
sed -n '/^        ScreencopyView {$/,/^        }$/p' "$dst/modules/drawers/PeekLayer.qml" | grep -q '^            layer.enabled: true$' ||
    fail "window peek's picture of a see-through window shows the windows under the shell"

# What the patched files add to qmllint's findings on Caelestia's own (each file against the same one unpatched, both
# with Quickshell's qs.* modules laid out as it does): no member or type the patches use that isn't there (a rename
# upstream that would only show as an error at run time, a feature quietly not working), no property shadowing
# Caelestia's
cat >"$t/lint.py" <<'P'
import os, re, subprocess, sys
src, dst, work = sys.argv[1:]
kinds = ("missing-property", "missing-type", "unresolved-type", "property-override", "redundant-optional-chaining")
def tree(root, out):
    # qs.<dir> modules as Quickshell makes them: a qmldir per folder, its files (copies, so each file's folder is its own)
    for d, _, files in os.walk(root, followlinks=True):
        rel = os.path.relpath(d, root)
        mod = "qs" if rel == "." else "qs." + rel.replace(os.sep, ".")
        od = os.path.join(out, *mod.split("."))
        os.makedirs(od, exist_ok=True)
        lines = [f"module {mod}"]
        for f in sorted(files):
            if not f.endswith((".qml", ".js")):
                continue
            text = open(os.path.join(d, f), encoding="utf-8").read()
            open(os.path.join(od, f), "w", encoding="utf-8").write(text)
            if f.endswith(".qml") and f[0].isupper():
                lines.append(("singleton " if "pragma Singleton" in text else "") + f"{f[:-4]} 1.0 {f}")
        open(os.path.join(od, "qmldir"), "w").write("\n".join(lines) + "\n")
def lint(root, rel):
    path = os.path.join(root, "qs", rel)
    if not os.path.exists(path):
        return set()
    out = subprocess.run(["/usr/lib/qt6/bin/qmllint", "-I", root, path], stdout=subprocess.PIPE,
                         stderr=subprocess.STDOUT, text=True).stdout
    # (the finding without its place: a line number moved by a patch isn't a new one)
    return {re.sub(r"^\S+:\d+:\d+: ", "", l.split(": ", 1)[1]) for l in out.splitlines()
            if l.startswith("Warning: ") and l.endswith(tuple(f"[{k}]" for k in kinds))}
tree(src, f"{work}/src"); tree(dst, f"{work}/dst")
for d, _, files in os.walk(dst):
    for f in files:
        full = os.path.join(d, f)
        if f.endswith(".qml") and not os.path.islink(full):
            rel = os.path.relpath(full, dst)
            for w in sorted(lint(f"{work}/dst", rel) - lint(f"{work}/src", rel)):
                print(f"{rel}: {w}")
P
# lint_new <Caelestia> <patched copy>: those findings, one a line (none: qmllint not installed)
lint_new() { [[ ! -x /usr/lib/qt6/bin/qmllint ]] || python3 -I "$t/lint.py" "$1" "$2" "$(mktemp -d -p "$t")"; }
new=$(lint_new /etc/xdg/quickshell/caelestia "$dst")
[[ -z $new ]] || fail "the patched QML uses what Caelestia doesn't have (qmllint): $new"

# The lock's own PAM config (Caelestia's assets/pam.d/passwd, read from the shell's folder): pam_unix and pam_faillock without
# their failure delay (a wrong password said at once), pam_faillock's lines kept; the installed Caelestia's left as it is
p=$dst/assets/pam.d/passwd
[[ -f $p && ! -L $p ]] || fail "the lock's PAM config not the overlay's"
grep -qE '^auth\s.*pam_unix\.so.*\bnodelay\b' "$p" || fail "the lock's pam_unix still has its failure delay: $(cat "$p")"
[[ $(grep -c pam_faillock.so "$p") == 3 && $(grep -cE '^auth\s.*pam_faillock\.so.*\bnodelay$' "$p") == 3 ]] ||
    fail "the lock's pam_faillock lines not kept, or still with their failure delay: $(cat "$p")"
diff <(sed 's/ nodelay$//' "$p") /etc/xdg/quickshell/caelestia/assets/pam.d/passwd >/dev/null ||
    fail "the lock's PAM config changed beyond nodelay: $(diff <(sed 's/ nodelay$//' "$p") /etc/xdg/quickshell/caelestia/assets/pam.d/passwd)"
# ...and against Caelestia's main (its assets/pam.d/passwd as of 2026-11), patch.py on a copy of that file alone
mkdir -p "$t/main/assets/pam.d" "$t/main-dst/assets/pam.d"
printf '%s\n' '#%PAM-1.0' '' 'auth    required                    pam_faillock.so     preauth' \
    'auth    [success=1 default=bad]     pam_unix.so         nullok' 'auth    [default=die]               pam_faillock.so     authfail' \
    'auth    required                    pam_faillock.so     authsucc' >"$t/main/assets/pam.d/passwd"
ln -s "$t/main/assets/pam.d/passwd" "$t/main-dst/assets/pam.d/passwd"
out=$(DOTS_SETTINGS=$t/bin/dots-settings python3 "$here/.local/share/caelestia-overlay/patch.py" "$t/main" "$t/main-dst" 2>&1) || true
{ grep -q "^Patched: lock screen: a wrong password said at once" <<<"$out" &&
    grep -qE '^auth\s.*pam_unix\.so\s+nullok nodelay$' "$t/main-dst/assets/pam.d/passwd" &&
    grep -qE '^auth\s.*pam_faillock\.so\s+preauth nodelay$' "$t/main-dst/assets/pam.d/passwd"; } ||
    fail "the lock's PAM change doesn't fit Caelestia's main: $(grep 'wrong password' <<<"$out")"

# Every member of Caelestia's services (Hypr.focusWorkspace, Colours.palette...) the overlay's code uses is still there:
# a renamed one patches in fine and reads as undefined without an error (with Hypr.usingLua gone, as Caelestia plans,
# the dock's clicks went down a branch for the old config language)
gone=$(python3 -I - /etc/xdg/quickshell/caelestia "$here/.local/share/caelestia-overlay" <<'P'
import glob, os, re, sys
src, overlay = sys.argv[1:]
used = {}
for f in glob.glob(overlay + "/*.qml") + [overlay + "/patch.py"]:
    code = re.sub(r"//.*|^\s*#.*", "", open(f, encoding="utf-8").read(), flags=re.M)  # (not comments)
    for m in re.finditer(r"\b([A-Z]\w*)\.([a-z]\w*)\b", code):
        used.setdefault(m.group(1), set()).add(m.group(2))
gone = []
for path in glob.glob(src + "/services/*.qml"):
    name, text = os.path.basename(path)[:-4], open(path, encoding="utf-8").read()
    if name in used and "Singleton" in text:
        have = set(re.findall(r"^\s*(?:readonly |required |default )*(?:property\s+\S+\s+|function\s+|signal\s+)(\w+)", text, re.M))
        gone += [f"{name}.{m}" for m in sorted(used[name] - have - {"qml"})]  # (services/Hypr.qml: a file name)
print(*gone)
P
)
[[ -z $gone ]] || fail "the overlay uses what Caelestia no longer has: $gone"

# Each feature off alone: the others still fit (one that needs it goes off with it, saying so)
src=/etc/xdg/quickshell/caelestia
for f in $(python3 "$here/.local/share/caelestia-overlay/patch.py" --list | python3 -c 'import json, sys; print(*(f["id"] for f in json.load(sys.stdin)))'); do
    echo "$f" >"$t/off"; rm -rf "$t/one"; cp -as "$src" "$t/one"
    out=$(DOTS_SETTINGS=$t/bin/dots-settings python3 "$here/.local/share/caelestia-overlay/patch.py" "$src" "$t/one" 2>&1) ||
        fail "with $f off: $(grep '^WARNING' <<<"$out")"
    # The dock off: the rest of the bar as it was (its place kept as space, Caelestia's own entries all there)
    if [[ $f == dock ]]; then
        bar=$t/one/modules/bar/Bar.qml
        grep -A3 'roleValue: "dock"' "$bar" | grep -q 'Layout.fillHeight: true' || fail "dock off: its place isn't kept as space"
        for e in logo workspaces tray clock statusIcons power; do
            grep -q "roleValue: \"$e\"" "$bar" || fail "dock off: the bar lost its $e"
        done
        grep -q 'Dock {' "$bar" && fail "dock off: the dock is still in the bar"
    fi
    # The sidebar from the right as Caelestia has it: its hover edge (down the right edge) let go on every path too
    if [[ $f == sidebar_from_top ]]; then
        r=$(sidebar_edge_released "$t/one/modules/drawers/Interactions.qml")
        [[ -z $r ]] && grep -q 'const sidebarTriggerY = ' "$t/one/modules/drawers/Interactions.qml" ||
            fail "sidebar from top off: its hover edge not let go on every path: $r"
    fi
done
rm -rf "$t/one" "$t/off"
# Window peek works on the dock's and the workspace preview's popouts: with one of them off it's still in, with both
# off it's off too (said so), not a patch that no longer fits
cat >"$t/bin/two-off" <<'S'
#!/bin/sh
echo '{"caelestia.dock": false, "caelestia.workspace_preview": false}'
S
chmod +x "$t/bin/two-off"; rm -rf "$t/one"; cp -as "$src" "$t/one"
out=$(DOTS_SETTINGS=$t/bin/two-off python3 "$here/.local/share/caelestia-overlay/patch.py" "$src" "$t/one" 2>&1) ||
    fail "with the dock and the workspace preview off: $(grep '^WARNING' <<<"$out")"
grep -q '^Off: window peek.*(needs bar dock or workspace previews on hover)$' <<<"$out" ||
    fail "window peek not off with both its previews off: $(grep 'window peek' <<<"$out")"
rm -rf "$t/one"

for _ in 1 2 3; do run >/dev/null & done; wait
[[ -f $dst/shell.qml ]] || fail "runs at once lost the folder"
[[ $(ls "$t/.config/quickshell") == $'caelestia\ncaelestia.lock' ]] || fail "temp folders left: $(ls "$t/.config/quickshell")"

# One patch that crashes (not a missing anchor): only it is skipped
p=$t/.local/share/caelestia-overlay/patch.py
cp "$p" "$t/patch.orig"
python3 - "$p" <<'P'
import re, sys
s = open(sys.argv[1]).read()
first = re.search(r"^FEATURES = [([]\n\s*\(\"[^\"]+\", (\w+)\)", s, re.M).group(1)
s = s.replace(f"def {first}(", f"def {first}(*a):\n    raise OSError('boom')\n\ndef _unused_{first}(", 1)
open(sys.argv[1], "w").write(s)
P
out=$(run) || true
[[ $(grep -c '^WARNING' <<<"$out") == 1 ]] || fail "a crashing patch didn't skip only itself: $out"
(($(grep -c '^Patched' <<<"$out") > 20)) || fail "a crashing patch dropped the others"

# patch.py itself broken (failing once it has patched: its copies left in the new folder): Caelestia as it comes (links
# only, no patched copies, old or new), and said so
cp "$t/patch.orig" "$p"; run >/dev/null
sed -i 's/^sys\.exit(0 if ok else 1)$/raise RuntimeError("broken")/' "$p"; touch "$dst/marker"
grep -q 'RuntimeError("broken")' "$p" || fail "test setup: patch.py's last line not found"
if run >/dev/null; then fail "a broken patch.py reported success"; fi
[[ -e $dst/marker ]] && fail "a broken patch.py kept the old patched folder"
[[ -z $(find "$dst" -type f) ]] || fail "a broken patch.py left patched files: $(find "$dst" -type f | head -3)"
[[ -L $dst/shell.qml ]] || fail "a broken patch.py left no shell"
grep -q "without your changes" "$skipped" || fail "a broken patch.py wasn't reported"

# Every patch fitting but leaving QML that doesn't parse (a whole shell that wouldn't start): Caelestia as it comes
if command -v /usr/lib/qt6/bin/qmllint qmllint6 >/dev/null 2>&1; then
    cp -r "$here/.local/share/caelestia-overlay/." "$t/.local/share/caelestia-overlay/"
    mv "$t/.local/share/caelestia-overlay/patch.py" "$t/.local/share/caelestia-overlay/real_patch.py"
    cat >"$t/.local/share/caelestia-overlay/patch.py" <<'P'
import pathlib, subprocess, sys
r = subprocess.run([sys.executable, str(pathlib.Path(__file__).with_name("real_patch.py")), *sys.argv[1:]])
f = next(p for p in pathlib.Path(sys.argv[2]).rglob("*.qml") if p.is_file() and not p.is_symlink())
f.write_text(f.read_text() + "\n}}} {{ broken\n")
sys.exit(r.returncode)
P
    out=$(run) && fail "broken QML wasn't caught: $(tail -3 <<<"$out")"
    [[ -z $(find "$dst" -type f) ]] || fail "broken QML was kept: $(find "$dst" -type f | head -3)"
    grep -q "broken QML" "$skipped" || fail "broken QML wasn't reported: $(cat "$skipped")"
fi
# Caelestia's main (its next release: a change there that a patch no longer fits shows here first), its QML as it installs
# it (the folders its CMakeLists.txt installs): every patch fits, and adds nothing to qmllint's findings. Needs the network
if timeout 120 git clone -q --depth 1 https://github.com/caelestia-dots/shell "$t/head-git" 2>/dev/null; then
    dirs=$(sed -n 's/^ *foreach(dir \(.*\))$/\1/p' "$t/head-git/CMakeLists.txt")
    [[ -n $dirs ]] || fail "Caelestia's main: the folders it installs not found in its CMakeLists.txt"
    mkdir "$t/head-src"
    for d in $dirs shell.qml; do cp -r "$t/head-git/$d" "$t/head-src/"; done
    cp -as "$t/head-src" "$t/head-dst"
    out=$(DOTS_SETTINGS=$t/bin/dots-settings python3 "$here/.local/share/caelestia-overlay/patch.py" "$t/head-src" "$t/head-dst" 2>&1) ||
        fail "patches no longer fit Caelestia's main: $(grep '^WARNING\|Traceback' <<<"$out")"
    new=$(lint_new "$t/head-src" "$t/head-dst")
    [[ -z $new ]] || fail "on Caelestia's main, the patched QML uses what it doesn't have (qmllint): $new"
    echo "ok caelestia-overlay"
else
    echo "ok caelestia-overlay (SKIPPED: Caelestia's main: no network)"
fi
