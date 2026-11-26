#!/usr/bin/env bash
# hyprbars-build: refuses to build after an update the session hasn't restarted for; the patch still applies to the
# hyprland-plugins tag hyprbars-build takes for the installed Hyprland's series, and to their main (the next release:
# a change there that breaks it shows here first, said with ahead, lib.sh: not a failure). Needs the network. A part it
# can't check (offline, no Hyprland to ask) said on its last line, "ok hyprbars (SKIPPED: ...)", not a plain ok.
# DOTS_BUILD_TESTS=1: also builds the patched hyprbars against the installed Hyprland's headers (a minute or two)
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
# --login with this account's build not made for the running Hyprland yet (an update, offline then): the packaged one
# (agros-hyprbars) loaded only when it was built for that Hyprland (its commit in it). Another build's fails the plugin's
# own check, with a red "Version mismatch" error on screen at every login. (The build after it fails at once here: the
# headers aren't the running Hyprland's)
mkdir -p "$t/pkg" "$t/lbin" "$t/lhome/.local/share/hyprbars" "$t/lhome/.cache"
cp "$here/.local/share/hyprbars/hyprbars.patch" "$t/lhome/.local/share/hyprbars/"
printf 'ELF\0%s\0' 1111111111111111111111111111111111111111 >"$t/pkg/libhyprbars.so"
# ($LOADED: a plugin loaded is listed after it, as Hyprland lists it)
# shellcheck disable=SC2016  # (expanded by the stand-in)
printf '#!/bin/sh\necho "$*" >>%s/login-calls\n[ "$3" = version ] && echo "{\\"commit\\":\\"$COMMIT\\",\\"version\\":\\"0.57.2\\",\\"abiHash\\":\\"${COMMIT}_aq_0.12\\"}"\n[ "$3" = plugin ] && [ "$4" = list ] && { [ -n "$LOADED" ] && grep -q "plugin load" %s/login-calls && echo "[{\\"name\\":\\"hyprbars\\",\\"version\\":\\"1.0-dotfiles\\"}]" || echo "[]"; }\nexit 0\n' \
    "$t" "$t" >"$t/lbin/hyprctl"
printf '#!/bin/sh\nexit 0\n' >"$t/lbin/notify-send"
chmod +x "$t/lbin/"*
login() { HOME=$t/lhome HYPRBARS_LIVE=$t/nolive HYPRBARS_PACKAGED=$t/pkg/libhyprbars.so PATH=$t/lbin:$PATH COMMIT=$1 \
    "$here/.local/bin/hyprbars-build" --login >/dev/null 2>&1; }
login 1111111111111111111111111111111111111111 || fail "--login failed"
grep -qx -- "-i 0 plugin load $t/pkg/libhyprbars.so" "$t/login-calls" || fail "--login: the packaged one built for this Hyprland not loaded: $(cat "$t/login-calls")"
: >"$t/login-calls"
login 2222222222222222222222222222222222222222 || fail "--login on another Hyprland failed"
grep -q 'plugin load' "$t/login-calls" && fail "--login: the packaged one loaded on a Hyprland it wasn't built for: $(cat "$t/login-calls")"
# ...nor on the same commit rebuilt against other libraries (its ABI hash, which the package's stamp beside it has)
echo "1111111111111111111111111111111111111111_aq_0.11 x" >"$t/pkg/libhyprbars.so.built-for"
: >"$t/login-calls"
login 1111111111111111111111111111111111111111 || fail "--login on a rebuilt Hyprland failed"
grep -q 'plugin load' "$t/login-calls" && fail "--login: the packaged one loaded on a Hyprland rebuilt against other libraries"
echo "1111111111111111111111111111111111111111_aq_0.12 x" >"$t/pkg/libhyprbars.so.built-for"
: >"$t/login-calls"
login 1111111111111111111111111111111111111111 || fail "--login with the packaged stamp failed"
grep -qx -- "-i 0 plugin load $t/pkg/libhyprbars.so" "$t/login-calls" || fail "--login: the packaged one, its stamp this Hyprland's, not loaded"
# The packaged one this very build (its stamp: this Hyprland's ABI hash and this patch): loaded, and nothing built (a
# new account's first login compiled the same plugin again, and offline said its bars had no highlight)
echo "1111111111111111111111111111111111111111_aq_0.12 $(sha256sum "$t/lhome/.local/share/hyprbars/hyprbars.patch" | cut -d' ' -f1)" \
    >"$t/pkg/libhyprbars.so.built-for"
: >"$t/login-calls"
rm -f "$t/lhome/.cache/hyprbars-build.log"
LOADED=1 login 1111111111111111111111111111111111111111 || fail "--login with the packaged one this very build failed"
grep -qx -- "-i 0 plugin load $t/pkg/libhyprbars.so" "$t/login-calls" || fail "--login: the packaged one, this very build, not loaded"
[[ ! -e $t/lhome/.cache/hyprbars-build.log ]] ||
    fail "--login built again what the packaged one already is: $(cat "$t/lhome/.cache/hyprbars-build.log")"
rm "$t/pkg/libhyprbars.so.built-for"
# On the live USB: at login the packaged one is loaded (the installer's title bar), again only when it was built for
# that Hyprland; nothing built; otherwise nothing at all
mkdir -p "$t/live"
live() { HOME=$t/livehome HYPRBARS_LIVE=$t/live HYPRBARS_PACKAGED=$t/pkg/libhyprbars.so PATH=$t/lbin:$PATH COMMIT=$1 \
    "$here/.local/bin/hyprbars-build" "${@:2}"; }
: >"$t/login-calls"
live 1111111111111111111111111111111111111111 --login || fail "live USB, --login: failed"
grep -qx -- "-i 0 plugin load $t/pkg/libhyprbars.so" "$t/login-calls" || fail "live USB: the packaged one not loaded: $(cat "$t/login-calls")"
: >"$t/login-calls"
live 2222222222222222222222222222222222222222 --login || fail "live USB, --login on another Hyprland: failed"
grep -q 'plugin load' "$t/login-calls" && fail "live USB: the packaged one loaded on a Hyprland it wasn't built for"
: >"$t/login-calls"
live 1111111111111111111111111111111111111111 || fail "live USB, a build: failed"
[[ ! -s $t/login-calls && ! -e $t/livehome ]] || fail "live USB: a build tried: $(cat "$t/login-calls")"
# --prebuild (root's pacman hook, for each user, waiting on it with its lock held): AgrOS's patch as packaged (beside
# the script), never the one in the user's home, theirs to change (a patch to the Makefile could hang the update); nor
# their git settings (below, with the headers). Here a build for this Hyprland and AgrOS's patch is found made,
# whatever the home's patch says (a made-up version.h: no headers needed)
mkdir -p "$t/ph/.local/share/hyprbars" "$t/ph/.local/lib/hyprbars"
echo 'evil' >"$t/ph/.local/share/hyprbars/hyprbars.patch"
printf '#define %s "%s"\n' GIT_COMMIT_HASH abc GIT_TAG v0.1.0 AQUAMARINE_VERSION 0.1.0 HYPRUTILS_VERSION 0.1.0 \
    HYPRGRAPHICS_VERSION 0.1.0 HYPRCURSOR_VERSION 0.1.0 >"$t/ph.h"
: >"$t/ph/.local/lib/hyprbars/libhyprbars.so"
echo "abc_aq_0.1_hu_0.1_hg_0.1_hc_0.1 $(sha256sum "$here/.local/share/hyprbars/hyprbars.patch" | cut -d' ' -f1)" \
    >"$t/ph/.local/lib/hyprbars/built-for"
out=$(HOME=$t/ph HYPRBARS_LIVE=$t/nolive HYPRBARS_VERSION_H=$t/ph.h "$here/.local/bin/hyprbars-build" --prebuild 2>&1) ||
    fail "--prebuild failed: $out"
[[ $out == *"Already built"* ]] || fail "--prebuild took the patch in the user's home, not AgrOS's: $out"
# ...and with none of the user's own, the packaged one (updated with that Hyprland) this very build, its stamp says:
# nothing built (each user's clone and compile of the same plugin held the shutdown's install up)
rm "$t/ph/.local/lib/hyprbars/libhyprbars.so" "$t/ph/.local/lib/hyprbars/built-for"
mkdir -p "$t/phpkg" "$t/phbin"
: >"$t/phpkg/libhyprbars.so"
echo "abc_aq_0.1_hu_0.1_hg_0.1_hc_0.1 $(sha256sum "$here/.local/share/hyprbars/hyprbars.patch" | cut -d' ' -f1)" \
    >"$t/phpkg/libhyprbars.so.built-for"
printf '#!/bin/sh\necho "git $*" >>%s/ph-git\nexit 1\n' "$t" >"$t/phbin/git"
chmod +x "$t/phbin/git"
out=$(HOME=$t/ph HYPRBARS_LIVE=$t/nolive HYPRBARS_VERSION_H=$t/ph.h HYPRBARS_PACKAGED=$t/phpkg/libhyprbars.so \
    PATH=$t/phbin:$PATH "$here/.local/bin/hyprbars-build" --prebuild 2>&1) || fail "--prebuild with the packaged one this very build: $out"
[[ ! -e $t/ph-git && $out == *"nothing to build"* ]] || fail "--prebuild built what the packaged one already is: $out"
# (agros-hyprbars' own build, which makes the packaged one, compares with none: an installed one skipped its build)
# shellcheck disable=SC2016  # (the PKGBUILD's text)
grep -qF 'HYPRBARS_PACKAGED=/nonexistent "$_root/.local/bin/hyprbars-build" --prebuild' "$here/packages/agros-hyprbars/PKGBUILD" ||
    fail "agros-hyprbars' build may take an installed packaged one for the build it makes"
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
cp "$t/bin/curl" "$t/bin/sleep"
# (git: with the git settings it ran with, the home's own ~/.gitconfig here (a hook of the user's): not used)
# shellcheck disable=SC2016  # (expanded by the stand-in)
printf '#!/bin/sh\necho "git $* (settings: ${GIT_CONFIG_GLOBAL:-home})" >>"%s"\nexit 1\n' "$t/calls" >"$t/bin/git"
printf '[core]\n\tfsmonitor = true\n' >"$t/home/.gitconfig"; chmod +x "$t/bin/"*
out=$(HOME=$t/home PATH=$t/bin:$PATH "$here/.local/bin/hyprbars-build" --prebuild 2>&1) && fail "--prebuild offline succeeded: $out"
grep -q "^git .*clone" "$t/calls" || fail "--prebuild didn't build for a new Hyprland: $out"
grep -q "^git .*clone.*(settings: /dev/null)$" "$t/calls" || fail "--prebuild's clone ran with the user's git settings: $(cat "$t/calls")"
rm "$t/home/.gitconfig"
grep -q "^curl\|^sleep" "$t/calls" && fail "--prebuild waited for the network, or between tries: $(cat "$t/calls")"
[[ $(cat "$lib/built-for") == "0_aq_0.0 $sum" ]] || fail "--prebuild offline changed the build's stamp"
rm "$t/bin/curl" "$t/bin/git" "$t/bin/sleep"

# Hyprland's main (the next release): --prebuild's hash still made the way its PluginAPI.hpp makes it, from the defines
# its version.h.in has (main dropped hyprlang from both: the hook failed, set -e, on a define gone). Said, not a failure
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
    if ! out=$(HOME=$t/home HYPRBARS_VERSION_H=$t/version.h "$here/.local/bin/hyprbars-build" --prebuild 2>&1); then
        ahead "--prebuild fails on Hyprland main's version.h: $(tail -n3 <<<"$out" | paste -sd' ')"
    elif ! grep -q "Already built" <<<"$out"; then
        ahead "--prebuild's hash isn't Hyprland main's ($want): $(tail -n3 <<<"$out" | paste -sd' ')"
    fi
else
    ahead "Hyprland's main couldn't be fetched: not checked"
fi

# The patch on this series' tag and on main
ver=$(grep -oP 'GIT_TAG\s+"v\K[0-9.]+' /usr/include/hyprland/src/version.h)
# (offline: skipped here, but not on CI, where a pass approves that Hyprland for AgrOS's machines: the upstream gate)
git clone -q --filter=blob:none https://github.com/hyprwm/hyprland-plugins.git "$t/src" 2>/dev/null || {
    [[ -z ${CI:-} ]] || fail "hyprland-plugins couldn't be fetched: the patch not checked"
    skipped+=("patch: offline"); ok_line hyprbars "SKIPPED: $(IFS=';'; echo "${skipped[*]}")"; exit 0; }
commit=$(grep -oP 'GIT_COMMIT_HASH\s+"\K[0-9a-f]+' /usr/include/hyprland/src/version.h)
pin=$(grep -oP "\[\"$commit\", \"\K[0-9a-f]{40}" "$t/src/hyprpm.toml" || true)
ref=${pin:-v${ver%.*}.0}
git -C "$t/src" rev-parse -q --verify "$ref^{commit}" >/dev/null || fail "hyprland-plugins has no $ref (hyprbars-build looks for it)"
git -C "$t/src" checkout -q "$ref"
git -C "$t/src" apply --check "$here/.local/share/hyprbars/hyprbars.patch" || fail "the patch no longer applies to hyprland-plugins $ref"
# (their main: said, not a failure)
git -C "$t/src" checkout -q origin/HEAD && git -C "$t/src" apply --check "$here/.local/share/hyprbars/hyprbars.patch" 2>/dev/null ||
    ahead "the patch no longer applies to hyprland-plugins' main"
# The bar resizes its window one way only, the patch's resizeEdgeAt (its edges, windows.lua's drag hooks): a resize
# hyprbars starts of its own on main (upstream's startTopEdgeResize, after v0.57.0, took the presses resizeEdgeAt turned
# down) is said, unless the patch shadows it. resizers <ref>: "file:function" of each resize start in the patched
# hyprbars, the shadowed ones left out
resizers() {
    git -C "$t/src" checkout -q -f "$1" && git -C "$t/src" apply "$here/.local/share/hyprbars/hyprbars.patch" 2>/dev/null || return 1
    python3 -I - "$t/src/hyprbars" <<'PY' || return 1
import glob, os, re, sys
for f in sorted(glob.glob(os.path.join(sys.argv[1], "*.cpp"))):
    text = open(f, encoding="utf-8").read()
    shadowed = set(re.findall(r"const auto (\w+) = \[\]\(auto&&\.\.\.\) \{ return false; \};", text))
    func = None
    for line in text.splitlines():
        if m := re.match(r"[A-Za-z].*?(\w+)\([^;]*\)\s*(?:const\s*)?\{\s*$", line):
            func = m[1]  # (the function a line is in: the last definition started at the line's start)
        if "beginDragTarget" in line and "MBIND_RESIZE" in line and func not in shadowed:
            print(f"{os.path.basename(f)}:{func}")
PY
    git -C "$t/src" reset -q --hard
}
tag_resizers=$(resizers "$ref") || fail "the resize check failed on hyprland-plugins $ref"
if main_resizers=$(resizers origin/HEAD); then
    new=$(comm -13 <(sort -u <<<"$tag_resizers") <(sort -u <<<"$main_resizers"))
    [[ -z $new ]] || ahead "hyprbars on hyprland-plugins' main starts a resize the patch doesn't own: $(paste -sd' ' <<<"$new")"
fi

# Upstream's fixes after v0.57.0 the patch carries for the tag (on main they're upstream's own; the patch's copies
# must still apply there): the stencil write mask set before the bar's stencil is cleared (#717: else blur left it at 0
# and rounded bars flickered), and a press the bar took gets its release wherever that lands, every new press starting
# clear (#722 and more: a window minimised from its button had the release of the next click in it swallowed).
# missing_fixes <ref>: what's missing in the patched barDeco.cpp, one per line
missing_fixes() {
    git -C "$t/src" checkout -q -f "$1" && git -C "$t/src" apply "$here/.local/share/hyprbars/hyprbars.patch" 2>/dev/null || return 1
    python3 -I - "$t/src/hyprbars/barDeco.cpp" <<'PY' || return 1
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
def body(name):
    m = re.search(r"^\S.*CHyprBar::" + name + r"\(.*?\n(.*?)^\}", text, re.S | re.M)
    return m[1] if m else ""
code = [l.strip() for l in text.splitlines() if l.strip() and not l.strip().startswith("//")]
clear = code.index("glClear(GL_STENCIL_BUFFER_BIT);") if "glClear(GL_STENCIL_BUFFER_BIT);" in code else 0
if "glStencilMask(0xFF);" not in code[max(0, clear - 3):clear]:
    print("#717: no glStencilMask(0xFF) before the bar's stencil clear")
button = body("onMouseButton")
if not 0 <= button.find("m_bCancelledDown") < button.find("inputIsValid()"):
    print("#722: onMouseButton leaves a taken press's release to inputIsValid")
valid = body("inputIsValid")
if "WINDOWATCURSOR && WINDOWATCURSOR != m_pWindow" not in valid and "|| WINDOWATCURSOR)" not in valid:
    print("#722: inputIsValid gives a press on a window over the focused one's bar to that bar")
down = body("handleDownEvent")
if not 0 <= down.find("m_bCancelledDown = false;") < down.find("return"):
    print("#722: handleDownEvent doesn't start a new press clear")
PY
    git -C "$t/src" reset -q --hard
}
missing=$(missing_fixes "$ref") || fail "the upstream fixes check failed on hyprland-plugins $ref"
[[ -z $missing ]] || fail "the patched hyprbars ($ref) lacks: $(paste -sd';' <<<"$missing")"
if missing=$(missing_fixes origin/HEAD); then
    [[ -z $missing ]] || ahead "the patched hyprbars on hyprland-plugins' main lacks: $(paste -sd';' <<<"$missing")"
fi

# Built, as hyprbars-build builds it (this series' version, patched; g++ by name), against the installed headers
if [[ -n ${DOTS_BUILD_TESTS:-} ]]; then
    git -C "$t/src" checkout -q "${pin:-v${ver%.*}.0}"
    git -C "$t/src" apply "$here/.local/share/hyprbars/hyprbars.patch"
    out=$(make -C "$t/src/hyprbars" -s CXX=g++ all 2>&1) || fail "the patched hyprbars doesn't build: $(tail -20 <<<"$out")"
    [[ -s $t/src/hyprbars/hyprbars.so ]] || fail "the patched hyprbars built no hyprbars.so: $(tail -5 <<<"$out")"
else
    skipped+=("build: DOTS_BUILD_TESTS=1 to build the patched hyprbars")
fi
note=
((${#skipped[@]} == 0)) || note="SKIPPED: $(IFS=';'; echo "${skipped[*]}")"
ok_line hyprbars "$note"
