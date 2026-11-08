#!/usr/bin/env bash
# system/boot-video-mode's kernel options rewrite: only whole video= options are replaced, not another option whose
# name ends in "video=" (it was cut to "foo." with its value left on its own)
set -euo pipefail
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
    ('K="video=X:2x2@2 quiet"', ["video=X:1x1@1"], 'K=" quiet video=X:1x1@1"'),
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
# No edid-decode (v4l-utils removed): no modes read, not a crash at every boot
rc=0; out=$(PATH=/nonexistent "$(command -v python3)" "$here/system/boot-video-mode" --check 2>/dev/null) || rc=$?
((rc == 3)) || fail "no screens: not exit 3 (crashed?): $rc"
[[ $out == "no screens with EDID found" ]] || fail "modes read with no edid-decode: $out"
# boot-video-mode.sh's last word, as it runs it (set -euo pipefail, a statement: not in $(...), where errexit is off):
# no screen telling its modes said as nothing set, not "Done"; the modes an earlier run set said as kept, read as
# boot-video-mode reads them (--current: Limine's options line where its settings are, else GRUB's; not a commented
# line, not the other boot loader's file); never failing the step, whichever of the files is there or not
# shellcheck disable=SC2154,SC2016  # ($t: lib.sh's; the stand-ins' own $1)
{
mkdir -p "$t/bin" "$t/etc/default"
printf '#!/bin/sh\nexit 0\n' >"$t/bin/grub-mkconfig"
# (its --check: no screens, or one; --current: the real one)
printf '#!/bin/sh\n[ "$1" = --check ] || exec python3 %s "$@"\necho "no screens with EDID found"; exit 3\n' "$here/system/boot-video-mode" >"$t/none"
printf '#!/bin/sh\n[ "$1" = --check ] || exec python3 %s "$@"\necho video=DP-1:2560x1440@144\n' "$here/system/boot-video-mode" >"$t/one"
chmod +x "$t/bin/grub-mkconfig" "$t/none" "$t/one"
report() {  # report <stand-in> [<its run's exit status>]
    BOOT_VIDEO_MODE_ETC=$t/etc PATH=$t/bin:$PATH bash -euo pipefail -c \
        'source <(sed -n "/^report() {$/,/^}$/p" "$1"); report "$2" "$3"; echo "(the step goes on)"' _ \
        "$here/system/boot-video-mode.sh" "$1" "${2:-0}" </dev/null 2>&1
}
says() {  # says <expected start> <what>
    local out
    out=$(report "$t/none")
    [[ $out == "$1"*"(the step goes on)" && $out != *Done* ]] || fail "$2: $out"
}
# Neither file (systemd-boot...): nothing for it to do, said calmly, also with a screen's mode (not "couldn't be set")
says "Nothing to do: no Limine or GRUB settings here" "no boot config: not said as nothing to do"
out=$(report "$t/one")
[[ $out == "Nothing to do: no Limine or GRUB settings here"*"(the step goes on)" ]] || fail "no boot config with a screen: $out"
# GRUB's alone, with modes set before
echo 'GRUB_CMDLINE_LINUX_DEFAULT="quiet video=Virtual-1:1280x800@60"' >"$t/etc/default/grub"
says "Nothing new to set: no screen reports its modes now (EDID), so the console keeps the ones set before: video=Virtual-1:1280x800@60" \
    "GRUB's modes from before not said"
# Limine's alone, a commented line with old modes in it not read
rm "$t/etc/default/grub"
printf '%s\n' '#KERNEL_CMDLINE[default]+="video=Old-1:1x1@1"' 'KERNEL_CMDLINE[default]+="quiet video=HDMI-A-1:1920x1080@60"' >"$t/etc/default/limine"
says "Nothing new to set: no screen reports its modes now (EDID), so the console keeps the ones set before: video=HDMI-A-1:1920x1080@60" \
    "Limine's modes from before not said (or a commented line's)"
# Both, Limine's (the one used) without modes: the default, not GRUB's leftovers
echo 'KERNEL_CMDLINE[default]+="quiet"' >"$t/etc/default/limine"
echo 'GRUB_CMDLINE_LINUX_DEFAULT="quiet video=Virtual-1:1280x800@60"' >"$t/etc/default/grub"
says "Nothing to set now:" "the unused boot loader's modes taken"
# A screen's mode: "Done" only when the run went through and the boot config has it now; else not set, said, with
# what the console keeps
echo 'KERNEL_CMDLINE[default]+="quiet video=DP-1:2560x1440@144"' >"$t/etc/default/limine"
[[ $(report "$t/one") == $'Done: from the next boot the console uses: video=DP-1:2560x1440@144\n(the step goes on)' ]] ||
    fail "a screen's mode set not said: $(report "$t/one")"
# (written in the config, but its boot entries not made again: limine-update or grub-mkconfig failed) said so, not as
# the modes kept from before
out=$(report "$t/one" 1)
[[ $out == "!! The screens' modes (video=DP-1:2560x1440@144) are in the boot config, but its boot entries couldn't be made again"*"(the step goes on)" &&
    $out != *Done* && $out != *"set before"* ]] || fail "the boot entries not made again, not said so: $out"
echo 'KERNEL_CMDLINE[default]+="quiet video=HDMI-A-1:1920x1080@60"' >"$t/etc/default/limine"
out=$(report "$t/one")
[[ $out == *"couldn't be set"*"keeps the modes set before: video=HDMI-A-1:1920x1080@60"* && $out != *Done* ]] ||
    fail "Done said with the boot config not having the mode: $out"
# boot-video-mode itself: a value with no quotes (KERNEL_CMDLINE[default]+=quiet) gets the modes; a config with no
# options line is a failure (not 0, which read as done)
printf '#!/bin/sh\nexit 0\n' >"$t/bin/limine-update"; chmod +x "$t/bin/limine-update"
run_main() {
    BOOT_VIDEO_MODE_ETC=$t/etc PATH=$t/bin:$PATH python3 - "$here/system/boot-video-mode" <<'P' >/dev/null 2>&1
import importlib.machinery, importlib.util, sys
loader = importlib.machinery.SourceFileLoader("bvm", sys.argv[1])
m = importlib.util.module_from_spec(importlib.util.spec_from_loader("bvm", loader))
loader.exec_module(m)
m.screens = lambda: ["video=DP-1:2560x1440@144"]
sys.exit(m.main())
P
}
echo 'KERNEL_CMDLINE[default]+=quiet' >"$t/etc/default/limine"
run_main || fail "boot-video-mode failed on a value with no quotes"
[[ $(cat "$t/etc/default/limine") == 'KERNEL_CMDLINE[default]+="quiet video=DP-1:2560x1440@144"' ]] ||
    fail "a value with no quotes not given the modes: $(cat "$t/etc/default/limine")"
echo 'TIMEOUT=0' >"$t/etc/default/limine"
run_main && fail "no options line taken as done"
}
echo "ok boot-video-mode-options"
