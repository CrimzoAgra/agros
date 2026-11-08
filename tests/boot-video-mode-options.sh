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
echo "ok boot-video-mode-options"
