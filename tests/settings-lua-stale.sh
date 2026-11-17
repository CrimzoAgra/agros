#!/usr/bin/env bash
# hypr-user.lua writes settings.lua again (dots-settings lua) when it was made from another schema than the one
# installed, by the md5sum dots-settings writes in it, not by the files' times: an update's schema older than
# settings.lua (a package's files carry its build's time, and a setting changed since left settings.lua the newer one,
# the update's new settings nil) still has it written again; the same schema, newer, doesn't; a missing, empty or older
# settings.lua (no md5 line) does; not in the config check (DOTS_VERIFY_CONFIG)
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
command -v lua >/dev/null || { echo "skip settings-lua-stale (no lua)"; exit 0; }
h=$t/home schema=$t/home/.local/share/dots-settings/schema.json lua=$t/home/.config/dots/settings.lua
mkdir -p "${schema%/*}" "$h/.local/bin" "${lua%/*}"
cp "$here/.local/share/dots-settings/schema.json" "$schema"
printf '#!/bin/sh\necho lua >>"%s/ran"\n' "$t" >"$h/.local/bin/dots-settings"
chmod +x "$h/.local/bin/dots-settings"
# (hl answering anything with nothing; user/*.lua not found: hypr-user.lua's own part only, its errors after it)
cat >"$t/load.lua" <<'L'
hl = setmetatable({}, { __index = function() return function() end end })
package.path = os.getenv("HOME") .. "/none/?.lua"
pcall(dofile, arg[1])
L
# written: whether this load wrote settings.lua again
written() {
    rm -f "$t/ran"
    (cd "$t" && HOME=$h DOTS_VERIFY_CONFIG=${VERIFY:-} lua load.lua "$here/.config/caelestia/hypr-user.lua" >/dev/null 2>&1) || true
    [[ -e $t/ran ]]
}
# settings.lua as dots-settings writes it, from the schema there now
write_lua() {
    python3 -I - "$here" "$h" <<'P'
import importlib.machinery, importlib.util, sys
here, h = sys.argv[1:]
loader = importlib.machinery.SourceFileLoader("ds", f"{here}/.local/bin/dots-settings")
ds = importlib.util.module_from_spec(importlib.util.spec_from_loader("ds", loader))
loader.exec_module(ds)
ds.SCHEMA, ds.CONFIG, ds.SETTINGS = f"{h}/.local/share/dots-settings/schema.json", f"{h}/.config/dots", f"{h}/.config/dots/settings.json"
ds.write_lua({"place.name": {"key": "place.name", "type": "text", "default": "x"}})
P
}

write_lua
touch -d '1 hour' "$schema"
! written || fail "settings.lua written again for the same schema (newer than it)"
# An update: the schema changed, its file older than settings.lua
echo ' ' >>"$schema"; touch -d '1 hour ago' "$schema"
written || fail "a changed schema older than settings.lua: settings.lua not written again"
VERIFY=1 written && fail "settings.lua written by the config check"
write_lua
! written || fail "settings.lua written again after it was made from the new schema"
sed -i 2d "$lua"
written || fail "a settings.lua with no schema md5 (an older one) not written again"
: >"$lua"
written || fail "an empty settings.lua not written again"
rm "$lua"
written || fail "a missing settings.lua not written"
echo "ok settings-lua-stale"
