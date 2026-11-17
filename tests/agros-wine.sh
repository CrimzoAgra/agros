#!/usr/bin/env bash
# agros-wine: CachyOS's Wine as the system's. It stands in for Arch's wine (provides, no conflict: a machine that has
# Arch's keeps updating), agros-desktop lists it before the gaming packages (whose winetricks needs a wine: pacman takes
# the one already chosen, so Arch's never comes in) and no longer lists wine-mono or wine-gecko (they need Arch's), and
# its files put /opt/wine-cachyos/bin first on the PATH, once however often they're read (sh, fish, systemd's)
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
desk=$here/packages/agros-desktop/PKGBUILD
deps=$(sed -n '/^depends=(/,/^)/p' "$desk" | sed 's/#.*//' | tr -s ' \n' '\n' | grep -v '^\(depends=(\|)\|\)$')
pos() { grep -nx -- "$1" <<<"$deps" | cut -d: -f1; }
[[ -n $(pos agros-wine) && -n $(pos cachyos-gaming-meta) ]] || fail "agros-desktop lists no agros-wine or no gaming packages"
(($(pos agros-wine) < $(pos cachyos-gaming-meta))) || fail "agros-wine after the gaming packages: Arch's wine would come in"
! grep -qx 'wine\|wine-mono\|wine-gecko' <<<"$deps" || fail "agros-desktop still lists Arch's wine or its Mono/Gecko"
# The package: wine provided, nothing conflicting or replaced
w=$here/packages/agros-wine/PKGBUILD
(   # shellcheck source=../packages/agros-wine/PKGBUILD
    . "$w"
    [[ " ${provides[*]} " == *" wine "* && -z ${conflicts[*]:-} && -z ${replaces[*]:-} && " ${depends[*]} " == *" wine-cachyos-opt "* ]] ||
        fail "agros-wine doesn't stand in for wine alone: provides ${provides[*]}, conflicts ${conflicts[*]:-}, replaces ${replaces[*]:-}"
    pkgdir=$t/pkg package
) || exit 1
p=$t/pkg
# sh/bash: first on the PATH, once over two reads
out=$(PATH=/usr/bin:/bin; . "$p/etc/profile.d/agros-wine.sh"; . "$p/etc/profile.d/agros-wine.sh"; echo "$PATH")
[[ $out == /opt/wine-cachyos/bin:/usr/bin:/bin ]] || fail "profile.d's PATH: $out"
# fish, where it's there
if command -v fish >/dev/null; then
    out=$(PATH=/usr/bin:/bin fish --no-config -c "source $p/usr/share/fish/vendor_conf.d/agros-wine.fish; source $p/usr/share/fish/vendor_conf.d/agros-wine.fish; string join : \$PATH")
    [[ $out == /opt/wine-cachyos/bin:/usr/bin:/bin ]] || fail "fish's PATH: $out"
else
    skipped "no fish: its file not run"
fi
grep -qx 'PATH=/opt/wine-cachyos/bin:${PATH}' "$p/usr/lib/environment.d/50-agros-wine.conf" ||
    fail "environment.d's PATH: $(cat "$p/usr/lib/environment.d/50-agros-wine.conf")"
echo "ok agros-wine"
