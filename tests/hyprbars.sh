#!/usr/bin/env bash
# hyprbars-build: refuses to build after an update the session hasn't restarted for; the patch still applies to the
# hyprland-plugins tag hyprbars-build takes for the installed Hyprland's series, and to their main (the next release:
# a change there that breaks it shows here first). Needs the network. A part it can't check (offline, no Hyprland to
# ask) said on its last line, "ok hyprbars (SKIPPED: ...)", not a plain ok.
# DOTS_BUILD_TESTS=1: also builds the patched hyprbars against the installed Hyprland's headers (a minute or two)
set -euo pipefail
. "$(dirname "$0")/lib.sh"
[[ -f /usr/include/hyprland/src/version.h ]] || { echo "skip hyprbars (no Hyprland headers)"; exit 0; }

# A running Hyprland older than the headers on disk
mkdir -p "$t/bin" "$t/home/.local/share/hyprbars"
cp "$here/.local/share/hyprbars/hyprbars.patch" "$t/home/.local/share/hyprbars/"
printf '#!/bin/sh\n[ "$1" = -i ] && shift 2\n[ "$1" = version ] && echo %s\n' "'{\"commit\":\"0000000000000000000000000000000000000000\",\"version\":\"0.0.0\"}'" >"$t/bin/hyprctl"
chmod +x "$t/bin/hyprctl"
if out=$(HOME=$t/home PATH=$t/bin:$PATH "$here/.local/bin/hyprbars-build" 2>&1); then fail "built against the wrong headers"; fi
grep -q "log out" <<<"$out" || fail "no log-out message: $out"
[[ ! -e $t/home/.local/lib ]] || fail "installed something"

skipped=()
# --prebuild (the pacman hook): the ABI hash it makes from the headers is the one Hyprland reports, so a build it made
# counts at the next login: the installed Hyprland's own (Hyprland --version's "Version ABI string", no session
# needed), else the running one's (when this session runs the headers' Hyprland)
lib=$t/home/.local/lib/hyprbars
mkdir -p "$lib" && touch "$lib/libhyprbars.so"
sum=$(sha256sum "$t/home/.local/share/hyprbars/hyprbars.patch" | cut -d' ' -f1)
abi=$(Hyprland --version 2>/dev/null | sed -n 's/^Version ABI string: *//p' || true)
live=${abi:+${abi%%_*} $abi}
[[ -n $live ]] || live=$(command hyprctl -i 0 version -j 2>/dev/null | jq -r 'select(.commit and .abiHash) | .commit + " " + .abiHash' || true)
if [[ -z $live ]]; then
    skipped+=("ABI hash: no Hyprland --version ABI string nor a running Hyprland")
elif [[ ${live%% *} != "$(grep -oP 'GIT_COMMIT_HASH\s+"\K[0-9a-f]+' /usr/include/hyprland/src/version.h)" ]]; then
    skipped+=("ABI hash: the Hyprland asked isn't the headers' one")
else
    echo "${live#* } $sum" >"$lib/built-for"
    out=$(HOME=$t/home "$here/.local/bin/hyprbars-build" --prebuild 2>&1) || fail "--prebuild: $out"
    grep -q "Already built" <<<"$out" || fail "--prebuild's ABI hash isn't Hyprland's (${live#* }): it'd rebuild every time: $out"
fi
# ...and built for another: it builds, offline it gives up at once (no waiting on the network: it held pacman up)
echo "0_aq_0.0 $sum" >"$lib/built-for"
printf '#!/bin/sh\necho "$(basename "$0") $*" >>"%s"\nexit 1\n' "$t/calls" >"$t/bin/curl"
cp "$t/bin/curl" "$t/bin/git"; cp "$t/bin/curl" "$t/bin/sleep"; chmod +x "$t/bin/"*
out=$(HOME=$t/home PATH=$t/bin:$PATH "$here/.local/bin/hyprbars-build" --prebuild 2>&1) && fail "--prebuild offline succeeded: $out"
grep -q "^git .*clone" "$t/calls" || fail "--prebuild didn't build for a new Hyprland: $out"
grep -q "^curl" "$t/calls" && fail "--prebuild waited for the network: $(cat "$t/calls")"
[[ $(cat "$lib/built-for") == "0_aq_0.0 $sum" ]] || fail "--prebuild offline changed the build's stamp"
rm "$t/bin/curl" "$t/bin/git" "$t/bin/sleep"

# Hyprland's main (the next release): --prebuild's hash still made the way its PluginAPI.hpp makes it, from the defines
# its version.h.in has (main dropped hyprlang from both: the hook failed, set -e, on a define gone)
hm=https://raw.githubusercontent.com/hyprwm/Hyprland/main/src
if curl -fsS -m 30 "$hm/version.h.in" -o "$t/version.h.in" && curl -fsS -m 30 "$hm/plugins/PluginAPI.hpp" -o "$t/PluginAPI.hpp"; then
    sed -E 's/"@GIT_TAG@"/"v9.8.7"/; s/"@GIT_COMMIT_HASH@"/"abc123"/; s/"@[A-Z_]+@"/"1.2.3"/; s/@[A-Z_]+@/0/' "$t/version.h.in" >"$t/version.h"
    want=$(python3 - "$t/PluginAPI.hpp" <<'EOF'
import re, sys
m = re.search(r'std::format\("([^"]*_aq_[^"]*)",(.*?)\);', open(sys.argv[1]).read(), re.S)
args = [a.strip() for a in m[2].split(",")] if m else []
vals = ["abc123" if a == "GIT_COMMIT_HASH" else "1.2" if a.startswith("stripPatch(") else "?" + a for a in args]
print(m[1].replace("{}", "{}").format(*vals) if m and m[1].count("{}") == len(vals) else "unparsed")
EOF
)
    echo "$want $sum" >"$lib/built-for"
    out=$(HOME=$t/home HYPRBARS_VERSION_H=$t/version.h "$here/.local/bin/hyprbars-build" --prebuild 2>&1) ||
        fail "--prebuild on Hyprland main's version.h: $out"
    grep -q "Already built" <<<"$out" || fail "--prebuild's hash isn't Hyprland main's ($want): $out"
else
    skipped+=("Hyprland main: offline")
fi

# The patch on this series' tag and on main
ver=$(grep -oP 'GIT_TAG\s+"v\K[0-9.]+' /usr/include/hyprland/src/version.h)
git clone -q --filter=blob:none https://github.com/hyprwm/hyprland-plugins.git "$t/src" 2>/dev/null ||
    { skipped+=("patch: offline"); echo "ok hyprbars (SKIPPED: $(IFS=';'; echo "${skipped[*]}"))"; exit 0; }
commit=$(grep -oP 'GIT_COMMIT_HASH\s+"\K[0-9a-f]+' /usr/include/hyprland/src/version.h)
pin=$(grep -oP "\[\"$commit\", \"\K[0-9a-f]{40}" "$t/src/hyprpm.toml" || true)
for ref in "${pin:-v${ver%.*}.0}" origin/HEAD; do
    git -C "$t/src" rev-parse -q --verify "$ref^{commit}" >/dev/null || fail "hyprland-plugins has no $ref (hyprbars-build looks for it)"
    git -C "$t/src" checkout -q "$ref"
    git -C "$t/src" apply --check "$here/.local/share/hyprbars/hyprbars.patch" || fail "the patch no longer applies to hyprland-plugins $ref"
done
# Built, as hyprbars-build builds it (this series' version, patched; g++ by name), against the installed headers
if [[ -n ${DOTS_BUILD_TESTS:-} ]]; then
    git -C "$t/src" checkout -q "${pin:-v${ver%.*}.0}"
    git -C "$t/src" apply "$here/.local/share/hyprbars/hyprbars.patch"
    out=$(make -C "$t/src/hyprbars" -s CXX=g++ all 2>&1) || fail "the patched hyprbars doesn't build: $(tail -20 <<<"$out")"
    [[ -s $t/src/hyprbars/hyprbars.so ]] || fail "the patched hyprbars built no hyprbars.so: $(tail -5 <<<"$out")"
else
    skipped+=("build: DOTS_BUILD_TESTS=1 to build the patched hyprbars")
fi
if ((${#skipped[@]})); then echo "ok hyprbars (SKIPPED: $(IFS=';'; echo "${skipped[*]}"))"; else echo "ok hyprbars"; fi
