#!/usr/bin/env bash
# The boot's update (auto-update's conf_repair) puts pacman.conf's AgrOS lines back where they're gone (a
# pacman.conf.pacnew merged whole): the upstream gate's Include (a pacman -Syu by hand took Hyprland unchecked) and the
# [agros] repo (AgrOS's packages foreign), by agros-system's own install code (pacman's copy of its install script),
# said in the log and noted for agros-check. Nothing missing: nothing changed, an earlier boot's note gone
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
r=$t/root
export AGROS_ROOT=$r
pacdb=$t/pac au=$t/au
mkdir -p "$r/etc" "$pacdb/local/agros-system-r100.abc1234-1" "$au"
cp "$here/packages/agros-system/agros-system.install" "$pacdb/local/agros-system-r100.abc1234-1/install"
eval "$(sed -n '/^conf_lacks() {$/,/^}$/p; /^conf_repair() {$/,/^}$/p' "$here/packages/agros-system/auto-update")"
declare -F conf_repair >/dev/null || fail "auto-update has no conf_repair"
conf=$r/etc/pacman.conf
# (CachyOS's own pacman.conf, as its .pacnew merged whole leaves it)
printf '%s\n' '[options]' 'HoldPkg = pacman glibc' 'Architecture = auto' '' '[core]' 'Include = /etc/pacman.d/mirrorlist' >"$conf"
want=$(printf '%s\n' '[options]' 'Include = /etc/pacman.d/agros-noextract.conf' 'Include = /etc/pacman.d/agros-gate.conf' \
    'HoldPkg = pacman glibc' 'Architecture = auto' '' '[core]' 'Include = /etc/pacman.d/mirrorlist' '' '[agros]' \
    'SigLevel = Required DatabaseRequired' 'Server = https://crimzoagra.github.io/agros/$arch' \
    'Server = https://pub-f1a3a482900748e8b69cd81361ab96e1.r2.dev/repo/$arch')
out=$(conf_repair)
[[ $(cat "$conf") == "$want" ]] || fail "pacman.conf not repaired: $(cat "$conf")"
[[ $out == "pacman.conf lacked the upstream gate's Include, AgrOS's repo ([agros]) (a pacman.conf.pacnew merged whole?): put back" ]] ||
    fail "the repair not said in the log: $out"
read -r _ _ what <"$au/pacman-conf-repaired" && [[ $what == "the upstream gate's Include, AgrOS's repo ([agros])" ]] ||
    fail "the repair not noted for agros-check: $(cat "$au/pacman-conf-repaired" 2>/dev/null)"
# Again: nothing to do, nothing said, the note gone (said once, by the login after the boot that repaired it)
out=$(conf_repair)
[[ -z $out && $(cat "$conf") == "$want" && ! -e $au/pacman-conf-repaired ]] || fail "a second run changed or said something: $out"
# Only the Include gone: only it put back, said; [agros] as it was
sed -i '/agros-gate/d' "$conf"
out=$(conf_repair)
[[ $(sed '/agros-gate/d' "$conf") == "$(sed '/agros-gate/d' <<<"$want")" && $(grep -c '^Include = /etc/pacman.d/agros-gate.conf$' "$conf") == 1 &&
    $out == "pacman.conf lacked the upstream gate's Include (a"* ]] || fail "the Include alone not put back: $out / $(cat "$conf")"
# No install script to repair with: said, nothing claimed
sed -i '/agros-gate/d' "$conf"
rm -r "$pacdb/local/agros-system-r100.abc1234-1"
out=$(conf_repair)
[[ $out == "!! pacman.conf lacks the upstream gate's Include, and it couldn't be put back" && ! -e $au/pacman-conf-repaired ]] ||
    fail "a repair that couldn't be done not said: $out"
echo "ok auto-update-pacman-conf"
