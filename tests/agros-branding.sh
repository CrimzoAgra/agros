#!/usr/bin/env bash
# agros-branding: CachyOS's os-release (as its own hook leaves it) becomes AgrOS's, with cachyos and arch still in
# ID_LIKE; one without ID_LIKE or LOGO gets them; run again, nothing changes. Each kept as it was before, once
# (.agros-orig), for agros-system's removal (its install script in a throwaway root): put back from that copy (Arch's
# privacy link too), else by CachyOS's cachyos-branding, else said; its update notes and UFW's logging put back
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
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
cmp -s "$t/os.agros-orig" <(printf '%s\n' 'NAME="CachyOS Linux"' 'PRETTY_NAME="CachyOS"' 'ID=cachyos' 'ID_LIKE=arch' \
    'BUILD_ID=rolling' 'PRIVACY_POLICY_URL="https://terms.archlinux.org/"' 'LOGO=cachyos') &&
    grep -qx 'DISTRIB_ID=cachyos' "$t/lsb.agros-orig" || fail "not kept as it was before AgrOS's name (or overwritten by the second run)"

# agros-system's removal
r=$t/root
mkdir -p "$r/etc/ufw" "$r/var/lib/agros" "$r/var/lib/auto-update/db" "$r/usr/share/libalpm/scripts" "$t/bin"
for x in "" .agros-orig; do cp "$t/os$x" "$r/etc/os-release$x"; cp "$t/lsb$x" "$r/etc/lsb-release$x"; done
ln -s /nonexistent "$r/var/lib/auto-update/db/local"
echo 'LOGLEVEL=off' >"$r/etc/ufw/ufw.conf"; echo medium >"$r/var/lib/agros/ufw-logging-off"
printf '#!/bin/sh\necho "$0 $*" >>%s/calls\n' "$t" >"$t/bin/ufw"
printf '#!/bin/sh\necho "cachyos-branding $*" >>%s/calls\n' "$t" >"$r/usr/share/libalpm/scripts/cachyos-branding"
chmod +x "$t/bin/ufw" "$r/usr/share/libalpm/scripts/cachyos-branding"
remove() { (set +e; export AGROS_ROOT=$r PATH=$t/bin:$PATH; . "$here/packages/agros-system/agros-system.install"; post_remove); }
out=$(remove)
cmp -s "$r/etc/os-release" "$t/os.agros-orig" && grep -qx 'DISTRIB_ID=cachyos' "$r/etc/lsb-release" ||
    fail "not put back from the copies: $(cat "$r/etc/os-release")"
[[ -z $out && ! -e $r/etc/os-release.agros-orig && ! -e $r/var/lib/auto-update && ! -e $r/var/lib/agros/ufw-logging-off ]] ||
    fail "the copies, the update's notes or UFW's note left: $out"
grep -qx "$t/bin/ufw logging medium" "$t/calls" && ! grep -q cachyos-branding "$t/calls" || fail "removal's calls: $(cat "$t/calls")"
# No copy (named before they were kept): CachyOS's script; not there either (Arch): said. UFW's level set since: kept
cp "$t/os" "$r/etc/os-release"; rm "$r/etc/lsb-release" "$t/calls"
echo 'LOGLEVEL=high' >"$r/etc/ufw/ufw.conf"; : >"$r/var/lib/agros/ufw-logging-off"
out=$(remove)
[[ -z $out && $(cat "$t/calls") == "cachyos-branding os-release" ]] || fail "CachyOS's script not run: $out $(cat "$t/calls")"
rm "$r/usr/share/libalpm/scripts/cachyos-branding"
out=$(remove)
[[ $out == *"/etc/os-release still names AgrOS"* ]] || fail "no copy and no CachyOS script not said: $out"
echo "ok agros-branding"
