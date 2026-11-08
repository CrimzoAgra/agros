#!/usr/bin/env bash
# agros-branding: CachyOS's os-release (as its own hook leaves it) becomes AgrOS's, with cachyos and arch still in
# ID_LIKE; one without ID_LIKE or LOGO gets them; run again, nothing changes
set -euo pipefail
. "$(dirname "$0")/lib.sh"
b="$here/packages/agros-system/agros-branding"
printf '%s\n' 'NAME="CachyOS Linux"' 'PRETTY_NAME="CachyOS"' 'ID=cachyos' 'ID_LIKE=arch' 'BUILD_ID=rolling' \
    'PRIVACY_POLICY_URL="https://terms.archlinux.org/"' 'LOGO=cachyos' >"$t/os"
printf '%s\n' 'DISTRIB_ID=cachyos' 'DISTRIB_DESCRIPTION="CachyOS"' >"$t/lsb"
"$b" "$t/os" "$t/lsb"
grep -qx 'PRETTY_NAME="AgrOS"' "$t/os" && grep -qx 'ID=agros' "$t/os" || fail "not AgrOS's name: $(cat "$t/os")"
grep -qx 'ID_LIKE="cachyos arch"' "$t/os" || fail "ID_LIKE lost cachyos or arch"
grep -qx 'LOGO=agros-logo' "$t/os" && ! grep -q PRIVACY "$t/os" || fail "logo or Arch's privacy link: $(cat "$t/os")"
grep -qx 'DISTRIB_ID=agros' "$t/lsb" || fail "lsb-release not AgrOS's"
cp "$t/os" "$t/once"; "$b" "$t/os" "$t/lsb"; cmp -s "$t/os" "$t/once" || fail "a second run changed it"
printf '%s\n' 'NAME="Arch Linux"' 'ID=arch' >"$t/bare"; "$b" "$t/bare" "$t/none"
grep -qx 'ID_LIKE="cachyos arch"' "$t/bare" && grep -qx 'LOGO=agros-logo' "$t/bare" || fail "missing lines not added: $(cat "$t/bare")"
echo "ok agros-branding"
