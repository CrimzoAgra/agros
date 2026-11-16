#!/usr/bin/env bash
# system/boot-video-mode's kernel options rewrite: only whole video= options are replaced, not another option whose
# name ends in "video=" (it was cut to "foo." with its value left on its own)
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
out=$(python3 - "$here/system/boot-video-mode" "$here/.local/share/caelestia-greeter" <<'EOF'
import importlib.machinery, importlib.util, sys
sys.path.insert(0, sys.argv[2])
loader = importlib.machinery.SourceFileLoader("bvm", sys.argv[1])
spec = importlib.util.spec_from_loader("bvm", loader)
m = importlib.util.module_from_spec(spec)
loader.exec_module(m)
for line, video, want in [
    ('K="quiet foo.video=1"', ["video=X:1x1@1"], 'K="quiet foo.video=1 video=X:1x1@1"'),
    ('K="quiet foo.video=1 video=X:2x2@2"', ["video=X:1x1@1"], 'K="quiet foo.video=1 video=X:1x1@1"'),
    # still: the old entry for the same screen replaced, one at the start of the line too
    ('K="video=X:2x2@2 quiet"', ["video=X:1x1@1"], 'K="quiet video=X:1x1@1"'),
]:
    got = m.with_video(line, video)
    if got != want:
        print(f"{line} -> {got}, not {want}")
        sys.exit(1)
    if m.with_video(got, video) != got:
        print(f"not stable: {got} -> {m.with_video(got, video)}")
        sys.exit(1)
EOF
) || fail "$out"
# No edid-decode (v4l-utils removed): no modes read, not a crash at every boot (a screen connected, in a made-up
# /sys/class/drm: the branch taken here too, with no screen)
mkdir -p "$t/root/sys/class/drm/card1-HDMI-A-1"
echo connected >"$t/root/sys/class/drm/card1-HDMI-A-1/status"; : >"$t/root/sys/class/drm/card1-HDMI-A-1/edid"
rc=0; out=$(AGROS_ROOT=$t/root PATH=/nonexistent "$(command -v python3)" "$here/system/boot-video-mode" --check 2>"$t/err") || rc=$?
grep -q "No edid-decode" "$t/err" || fail "no edid-decode: not said (the branch not taken): $(cat "$t/err")"
((rc == 3)) || fail "no screens: not exit 3 (crashed?): $rc"
[[ $out == "no screens with EDID found" ]] || fail "modes read with no edid-decode: $out"
# Two GPUs with the same connector name (card0-HDMI-A-1, card1-HDMI-A-1): one video= entry, not two
out=$(python3 - "$here/system/boot-video-mode" <<'EOF'
import importlib.machinery, importlib.util, os, sys, tempfile, types
loader = importlib.machinery.SourceFileLoader("bvm", sys.argv[1])
spec = importlib.util.spec_from_loader("bvm", loader)
m = importlib.util.module_from_spec(spec)
loader.exec_module(m)
d = tempfile.mkdtemp()
for c in ("card0-HDMI-A-1", "card1-HDMI-A-1"):
    os.makedirs(f"{d}/{c}")
    open(f"{d}/{c}/status", "w").write("connected\n")
m.glob.glob = lambda p: [f"{d}/card0-HDMI-A-1/status", f"{d}/card1-HDMI-A-1/status"]
m.subprocess.run = lambda *a, **k: types.SimpleNamespace(stdout="")
m.best_mode = lambda out: (1920, 1080, 60.0)
print(m.screens())
EOF
)
[[ $out == "['video=HDMI-A-1:1920x1080@60']" ]] || fail "same connector on two GPUs: $out"
# Limine's /etc/default/limine with several KERNEL_CMDLINE[default] lines (a shell script: += adds, a later = sets them
# all again): --quiet-boot adds the missing ones on the last line in effect only (ones on its other lines count as there),
# --remove takes AgrOS's out of every line (not one the lines before AgrOS had), the screens' video= go on that last line
# (out of the others)
lr=$t/limine-root; mkdir -p "$lr/etc/default" "$lr/sys/class/drm"
lim=$lr/etc/default/limine K='KERNEL_CMDLINE[default]'
bvm() { AGROS_ROOT=$lr "$here/system/boot-video-mode" "$@"; }
Q='splash loglevel=3 rd.udev.log_level=3 systemd.show_status=false'
check() {  # <name> <file before> <file after --quiet-boot>
    printf '%s\n' "$2" >"$lim"; cp "$lim" "$lim.agros-orig"
    bvm --quiet-boot || fail "$1: --quiet-boot failed"
    [[ $(cat "$lim") == "$3" ]] || fail "$1: --quiet-boot gave: $(cat "$lim")"
    rc=0; bvm --quiet-boot || rc=$?; ((rc == 3)) || fail "$1: --quiet-boot again changed it (exit $rc)"
    bvm --remove && [[ $(cat "$lim") == "$2" ]] || fail "$1: --remove gave: $(cat "$lim")"
}
check "one +=" "$K+=\"quiet rw\"" "$K+=\"quiet rw $Q\""
check "two +=" "$(printf '%s\n' "$K+=\"quiet nowatchdog\"" "$K+=\" rw\"")" \
    "$(printf '%s\n' "$K+=\"quiet nowatchdog\"" "$K+=\" rw $Q\"")"
check "a later =" "$(printf '%s\n' "$K+=\"quiet splash\"" "$K=\"rw\"" "$K+=\" loglevel=7\"")" \
    "$(printf '%s\n' "$K+=\"quiet splash\"" "$K=\"rw\"" "$K+=\" loglevel=7 quiet splash rd.udev.log_level=3 systemd.show_status=false\"")"
# --remove: the video= on a line no longer in effect (an older AgrOS put them on the first) out too, its QUIET ones (doing
# nothing there) left; those on the lines in effect out, a += line's leading space kept
printf '%s\n' "$K+=\"rw\"" >"$lim.agros-orig"
printf '%s\n' "$K+=\"rw quiet video=DP-1:1x1@1\"" "$K=\"rw\"" "$K+=\" splash nowatchdog\"" >"$lim"
bvm --remove && [[ $(cat "$lim") == "$(printf '%s\n' "$K+=\"rw quiet\"" "$K=\"rw\"" "$K+=\" nowatchdog\"")" ]] ||
    fail "--remove over several lines gave: $(cat "$lim")"
# The screens' modes: on the last line in effect, out of an earlier one; --current reads the lines in effect
mkdir -p "$t/edid" "$lr/sys/class/drm/card1-DP-1"
echo connected >"$lr/sys/class/drm/card1-DP-1/status"
printf '#!/bin/sh\necho "DTD 1:  2560x1440   165.000000 Hz"\n' >"$t/edid/edid-decode"
printf '#!/bin/sh\necho "limine-update" >>%s/edid/calls\n' "$t" >"$t/edid/limine-update"
chmod +x "$t/edid/"*
printf '%s\n' "$K+=\"video=DP-1:1x1@1 quiet\"" "$K+=\" rw\"" >"$lim"
PATH=$t/edid:$PATH bvm >/dev/null || fail "boot-video-mode with two += lines failed"
[[ $(cat "$lim") == "$(printf '%s\n' "$K+=\"quiet\"" "$K+=\" rw video=DP-1:2560x1440@165\"")" ]] ||
    fail "the screens' modes over two lines: $(cat "$lim")"
[[ $(bvm --current) == "video=DP-1:2560x1440@165" ]] || fail "--current: $(bvm --current)"
rm -f "$t/edid/calls"; PATH=$t/edid:$PATH bvm >/dev/null
[[ ! -e $t/edid/calls ]] || fail "the same screens rewrote the boot entries"
# GRUB's: the menu made in that root's /boot (AGROS_ROOT), never the machine's own
gr=$t/grub-root; mkdir -p "$gr/etc/default" "$gr/sys/class/drm/card1-DP-1"
echo connected >"$gr/sys/class/drm/card1-DP-1/status"
echo 'GRUB_CMDLINE_LINUX_DEFAULT="quiet"' >"$gr/etc/default/grub"
printf '#!/bin/sh\necho "grub-mkconfig $*" >>%s/edid/calls\n' "$t" >"$t/edid/grub-mkconfig"
chmod +x "$t/edid/grub-mkconfig"
AGROS_ROOT=$gr PATH=$t/edid:$PATH "$here/system/boot-video-mode" >/dev/null || fail "boot-video-mode on GRUB failed"
grep -qx "grub-mkconfig -o $gr/boot/grub/grub.cfg" "$t/edid/calls" || fail "GRUB's menu not made in AGROS_ROOT: $(cat "$t/edid/calls")"
echo "ok boot-video-mode-options"
