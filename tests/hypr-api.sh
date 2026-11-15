#!/usr/bin/env bash
# AgrOS's Hyprland config against the Hyprland installed (CI's: the newest, which the upstream gate approves once this
# and the rest pass): the whole config (Caelestia's dots, at the commit agros-hyprland-settings pins, with AgrOS's
# files over them, as /etc/skel has it) loaded by Hyprland itself (--verify-config: an unknown function or setting is an
# error), and every name of Hyprland's Lua API AgrOS uses (hl.*, its dispatchers, its events, the settings read by name
# and those made in one-line hl.config calls: in handlers too, which a load doesn't run) in the API Hyprland ships (its
# Lua stubs, made from its source)
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
stubs=/usr/share/hypr/stubs/hl.meta.lua
command -v Hyprland >/dev/null && [[ -f $stubs ]] || { echo "skip hypr-api (no Hyprland with its Lua stubs)"; exit 0; }

# Every hl.* name (comments left out), each hl.on's event, each one-line hl.config's setting
python3 -I - "$stubs" "$here" <<'PY' || fail "AgrOS uses Hyprland API the installed Hyprland doesn't have (above)"
import re, sys, glob, os
stubs, here = sys.argv[1], sys.argv[2]
classes, var_class, events, keys, cur, alias = {}, {}, set(), set(), None, None
for line in open(stubs):
    line = line.rstrip("\n")
    if m := re.match(r"---@class ([\w.]+)", line):
        cur, alias = m[1], None; classes.setdefault(cur, {}); continue
    if m := re.match(r"---@alias ([\w.]+)", line):
        cur, alias = None, m[1]; continue
    if (m := re.match(r'---\| "([^"]+)"', line)) and alias == "HL.EventName":
        events.add(m[1])
    if (m := re.match(r'---\| "([^"]+)"', line)) and alias == "HL.ConfigKey":
        keys.add(m[1])
    if (m := re.match(r"---@field (\[string\]|\w+)\??\s+(\S+)", line)) and cur:
        classes[cur][m[1]] = m[2]
    if (m := re.match(r"local (__\w+) = \{\}", line)) and cur:
        var_class[m[1]] = cur
    if (m := re.match(r"function (__\w+)\.(\w+)\(", line)) and m[1] in var_class:
        classes[var_class[m[1]]][m[2]] = "fun"
assert "HL.API" in classes and events and keys, "the stubs' layout changed: this check needs updating"
# (a section, decoration.blur, is the start of its settings' names)
sections = {".".join(k.split(".")[:i]) for k in keys for i in range(1, k.count(".") + 1)}
# (the Lua, the QML that calls Hyprland too (the switcher, the Settings app), and the scripts' hyprctl eval strings)
LIT = r'"(?:[^"\\]|\\.)*"|'"'"r"(?:[^'\\]|\\.)*'"


def scan_config(text, where, top):
    """Each hl.config call in this text's code (its strings emptied; at the top, a comment after it left out), then in
    each string holding one: a script's hyprctl eval 'hl.config({ ... })', or sh -c "hyprctl eval '...'" inside it"""
    code = re.sub(LIT, '""', text)
    check_config(code.split("--")[0] if top else code, where)
    for m in re.finditer(LIT, text):
        if re.search(r"hl\.config\s*[({]", m[0][1:-1]):
            scan_config(m[0][1:-1], where, False)


files = [f for d in (".config", ".local/bin", ".local/share") for f in glob.glob(f"{here}/{d}/**/*", recursive=True) if os.path.isfile(f)]
bad = []
def check_config(bare, where):
    """Each hl.config call in this code: its settings by full name, every section on the way a section; a setting whose
    value is a table (a gap's sides) not looked into; the plugins' own not Hyprland's"""
    # (hl.config({ ... }), hl.config ({ ... }) and hl.config{ ... }: the same call in Lua)
    for c in re.finditer(r"(?<![\w.])hl\.config\s*(?:\(\s*)?(?=\{)", bare):
        body = bare[c.end():]
        path, skip, opened = [], 0, False
        for t in re.finditer(r"(\w+)\s*=(?!=)\s*(\{)?|(\{)|(\})", body):
            if t[3] and not opened:
                opened = True  # (the call's table itself)
                continue
            if not opened:
                break  # (hl.config(x): not a table written out here)
            if t[4]:
                if skip: skip -= 1
                elif path: path.pop()
                else: break  # (the call's own closing brace: past its settings)
                continue
            if skip or t[3]:
                skip += 1 if (t[3] or t[2]) else 0
                continue
            name = ".".join(path + [t[1]])
            if path[:1] == ["plugin"] or name == "plugin":
                if t[2]: path.append(t[1])
                continue
            if t[2] and name in keys:
                skip = 1
            elif t[2]:
                if name not in sections:
                    bad.append(f"{where}: hl.config {name} (no such section)")
                path.append(t[1])
            elif name not in keys and name not in sections:  # (a section given a table made elsewhere)
                bad.append(f"{where}: hl.config {name} (no such setting)")


# (this check's own check: each form a call takes is looked at, a wrong name in it found)
for probe in ('hl.config({ misc = { nosuch_a = 1 } })', 'hl.config ({ misc = { nosuch_b = 1 } })',
              'hl.config{ misc = { nosuch_c = 1 } }', 'x = "hyprctl eval \'hl.config({ misc = { nosuch_d = 1 } })\'"',
              """sh -c "hyprctl eval 'hl.config({ misc = { nosuch_e = 1 } })'" """,
              'hl.config({ decoration = { blur = { nosuch_f = 1 } } })', 'hl.config({ nosuch_g = { x = 1 } })',
              'hl.config({ misc = { vrr = 1 }, cursor = { nosuch_h = 1 } })',
              # (a brace in a string inside the call, in a script's hyprctl eval "...": that string emptied too)
              """hyprctl eval "hl.config({ general = { layout = '}' }, misc = { nosuch_i = 1 } })" """):
    bad.clear()
    scan_config(probe, "probe", True)
    assert any("nosuch_" in b for b in bad), f"this check missed a wrong setting in: {probe}"
bad.clear()
for f in files:
    try:
        text = open(f, encoding="utf-8").read()
    except (UnicodeDecodeError, OSError):
        continue
    for n, line in enumerate(text.splitlines(), 1):
        code = line.strip()
        if code.startswith(("--", "#", "//")):
            continue
        where = f"{os.path.relpath(f, here)}:{n}"
        for m in re.finditer(r"(?<![\w.])hl((?:\.[A-Za-z_]\w*)+)", line):
            cls = "HL.API"
            for part in m[1].split(".")[1:]:
                fields = classes.get(cls)
                if fields is None:
                    break
                if part in fields:
                    if fields[part] in classes:
                        cls = fields[part]; continue
                    break
                if "[string]" in fields:
                    break
                bad.append(f"{where}: hl{m[1]} ({part} isn't in {cls})"); break
        # (the settings made in one line, as the handlers make theirs, hl.config({ a = { b = ..., c = { d = ... } } }):
        # each call in the line's code, and in each string, a string in a string too)
        scan_config(line, where, True)
        # (a setting read by its full name: hl.get_config("general.gaps_in"), and windows.lua's live() over it)
        for m in re.finditer(r'(?<![\w.])(?:hl\.get_config|live)\(\s*"([\w.]+)"', line):
            if m[1] not in keys:
                bad.append(f'{where}: "{m[1]}" (no such setting)')
        for m in re.finditer(r'(?<![\w.])hl\.on\(\s*"([^"]+)"', line):
            if m[1] not in events:
                bad.append(f'{where}: hl.on("{m[1]}") (no such event)')
for b in sorted(set(bad)):
    print(b)
sys.exit(1 if bad else 0)
PY

# The whole config, loaded by Hyprland (Caelestia's dots fetched at the pinned commit: offline, not checked)
dots=$(sed -n 's/^_dots=//p' "$here/packages/agros-hyprland-settings/PKGBUILD")
if git init -q "$t/dots" && git -C "$t/dots" fetch -q --depth 1 https://github.com/caelestia-dots/caelestia "$dots" 2>/dev/null; then
    git -C "$t/dots" checkout -q FETCH_HEAD
    mkdir -p "$t/home/.config"
    cp -r "$t/dots/hypr" "$t/home/.config/hypr"
    cp -r "$here/.config/." "$t/home/.config/"
    mkdir -m700 "$t/run"
    out=$(cd "$t" && HOME=$t/home XDG_RUNTIME_DIR=$t/run DOTS_VERIFY_CONFIG=1 \
        timeout 60 Hyprland --verify-config -c "$t/home/.config/hypr/hyprland.lua" 2>&1) || true
    res=$(sed -n '/^======== Config parsing result:/,$p' <<<"$out" | sed '1d;/^$/d')
    [[ $res == "config ok" ]] || fail "$(Hyprland --version 2>/dev/null | grep -om1 'Hyprland [0-9.]*') doesn't load AgrOS's config: ${res:-$(tail -5 <<<"$out")}"
else
    skipped "Caelestia's dots couldn't be fetched: the whole config's load not checked"
fi
echo "ok hypr-api"
