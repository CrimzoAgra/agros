#!/usr/bin/env bash
# Caelestia's Hyprland variables AgrOS names are still Caelestia's (its variables.lua at the commit
# agros-hyprland-settings pins): the ones hypr-vars.lua changes, the Settings app's (caelestia-vars.* in its schema)
# and the ones user/*.lua reads (vars.<name>). One Caelestia renamed is set or read for nothing, silently: its key back
# beside AgrOS's (Print doing both), Super+W's browser Firefox again, the gaps snapping uses Caelestia's defaults
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
dots=$(sed -n 's/^_dots=//p' "$here/packages/agros-hyprland-settings/PKGBUILD")
if ! git init -q "$t/dots" || ! git -C "$t/dots" fetch -q --depth 1 https://github.com/caelestia-dots/caelestia "$dots" 2>/dev/null; then
    skipped "Caelestia's dots couldn't be fetched"
    echo "ok caelestia-vars (SKIPPED: Caelestia's dots couldn't be fetched)"
    exit 0
fi
git -C "$t/dots" checkout -q FETCH_HEAD
python3 -I - "$here" "$t/dots/hypr/variables.lua" <<'P'
import glob, os, re, sys
here, variables = sys.argv[1:]
theirs = set(re.findall(r"^\s*(\w+)\s*=", open(variables).read(), re.M))
assert len(theirs) > 50, f"only {len(theirs)} variables read from Caelestia's variables.lua"
bad = []
# hypr-vars.lua's table (local vars = { ... }: its keys, one per line)
hv = open(f"{here}/.config/caelestia/hypr-vars.lua").read()
table = re.search(r"^local vars = \{\n(.*?)^\}", hv, re.S | re.M)
assert table, "hypr-vars.lua's table not found"
for name in re.findall(r"^\s*(\w+)\s*=", table.group(1), re.M):
    if name not in theirs:
        bad.append(f"hypr-vars.lua sets {name}")
for name in set(re.findall(r'"caelestia-vars\.(\w+)"', open(f"{here}/.local/share/dots-settings/schema.json").read())):
    if name not in theirs:
        bad.append(f"the Settings app's caelestia-vars.{name}")
for f in sorted(glob.glob(f"{here}/.config/caelestia/user/**/*.lua", recursive=True)):
    # (its code, not its comments: "hypr-vars.lua")
    for name in set(re.findall(r"(?<![\w-])vars\.(\w+)", re.sub(r"--.*", "", open(f).read()))):
        if name not in theirs:
            bad.append(f"{os.path.relpath(f, here)} reads vars.{name}")
if bad:
    print("FAIL: not one of Caelestia's variables (renamed or gone): " + "; ".join(sorted(bad)))
    sys.exit(1)
P
echo "ok caelestia-vars"
