#!/usr/bin/env bash
# agros-hyprland-settings' package() (its PKGBUILD's, run as makepkg would) on a made-up repo and Caelestia's dots, each
# a tiny git repo: /usr/share/agros/skel-versions lists every version each settings file in /etc/skel has had (AgrOS's
# history and Caelestia's, thunar as Thunar), Caelestia's execs.lua as package() changes it (caelestia-start), not
# the files that are yours (_own), not ones no longer in /etc/skel
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
g() { git -C "$1" -c user.name=t -c user.email=t@t -c commit.gpgsign=false "${@:2}"; }
commit() { g "$1" add -A && g "$1" commit -qm "$2"; }
sum() { sha256sum | cut -d' ' -f1; }

# Caelestia's dots: execs.lua and Thunar's accels in two versions; its other components there
d=$t/src/caelestia-dots
mkdir -p "$d/hypr/hyprland" "$d/thunar"
for c in fish foot fastfetch btop micro uwsm spicetify; do mkdir -p "$d/$c"; echo "$c" >"$d/$c/conf"; done
echo 'x = 1' >"$d/starship.toml"
git init -q "$d"
printf '%s\n' '-- 1' '    hl.exec_cmd("caelestia shell -d")' >"$d/hypr/hyprland/execs.lua"
echo accels-1 >"$d/thunar/accels.scm"
commit "$d" one
printf '%s\n' '-- 2' '    hl.exec_cmd("sleep 1 && gammastep")' '    hl.exec_cmd("caelestia shell -d")' >"$d/hypr/hyprland/execs.lua"
echo accels-2 >"$d/thunar/accels.scm"
commit "$d" two

# AgrOS: a setting in two versions, one of yours (shell.json), one deleted since; and what package() copies besides
a=$t/repo
mkdir -p "$a/packages/agros-hyprland-settings" "$a/.config/caelestia" "$a/.local/share/"{applications,firefox,lutris,fonts,icons}
cp "$here/packages/agros-hyprland-settings/PKGBUILD" "$a/packages/agros-hyprland-settings/"
for f in applications/a.desktop firefox/user.js lutris/l fonts/Bangers-Regular.ttf fonts/OFL.txt icons/i.svg; do
    echo "$f" >"$a/.local/share/$f"
done
git init -q "$a"
echo foo-1 >"$a/.config/foo.conf"; echo '{"a":1}' >"$a/.config/caelestia/shell.json"; echo gone >"$a/.config/gone.conf"
commit "$a" one
echo foo-2 >"$a/.config/foo.conf"; echo '{"a":2}' >"$a/.config/caelestia/shell.json"; rm "$a/.config/gone.conf"
commit "$a" two

# shellcheck disable=SC1091,SC2034  # (the PKGBUILD's package(), with makepkg's variables, as makepkg runs it: -e, no -u)
(set +u; cd "$a/packages/agros-hyprland-settings" && startdir=$PWD srcdir=$t/src pkgdir=$t/pkg &&
    . ./PKGBUILD && package) >"$t/out" 2>&1 || fail "package() failed: $(tail -3 "$t/out")"
v=$t/pkg/usr/share/agros/skel-versions
[[ -s $v ]] || fail "no skel-versions"
has() { grep -qx "$(printf '%s' "$1" | sum)  $2" "$v"; }
for x in foo-1 foo-2; do has "$x"$'\n' .config/foo.conf || fail "AgrOS's $x of foo.conf not listed: $(cat "$v")"; done
for x in accels-1 accels-2; do has "$x"$'\n' .config/Thunar/accels.scm || fail "Caelestia's $x (thunar as Thunar) not listed"; done
for x in 1 2; do
    has "-- $x"$'\n''    hl.exec_cmd("~/.local/bin/caelestia-start")'$'\n' .config/hypr/hyprland/execs.lua ||
        fail "execs.lua's version $x not listed as package() changes it: $(grep execs "$v")"
    ! has "-- $x"$'\n''    hl.exec_cmd("caelestia shell -d")'$'\n' .config/hypr/hyprland/execs.lua ||
        fail "execs.lua's version $x listed unchanged (never what /etc/skel has)"
done
grep -q 'hl.exec_cmd("~/.local/bin/caelestia-start")' "$t/pkg/etc/skel/.config/hypr/hyprland/execs.lua" || fail "execs.lua not changed"
! grep -q gammastep "$t/pkg/etc/skel/.config/hypr/hyprland/execs.lua" || fail "the night light still started by execs.lua"
! grep -qE ' \.config/(caelestia/shell\.json|gone\.conf)$' "$v" || fail "yours (shell.json) or a deleted one listed: $(cat "$v")"
[[ $(grep -c ' \.config/foo\.conf$' "$v") == 2 ]] || fail "foo.conf's versions not listed once each: $(cat "$v")"
echo "ok skel-versions"
