#!/usr/bin/env bash
# app-for-window: a window's app file by its class's last part, by its program (through a link: LibreOffice), a Wine
# .exe, a Lutris game's prefix (steam_app_default: the .exe that runs among games sharing one, else the launcher), hidden
# apps last, or none
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
a=$t/share/applications
mkdir -p "$a" "$t/bin"
app() { printf '[Desktop Entry]\nType=Application\nName=%s\n%s\n' "$1" "$2" >"$a/$1.desktop"; }
app cachyos-pi $'Exec=/usr/bin/cachyos-pi\nStartupWMClass=cachyos-pi'
app net.lutris.Lutris 'Exec=lutris %U'
app tool-hidden $'Exec=/opt/tool/mytool\nNoDisplay=true'
app tool $'Exec=env FOO=1 python3 /opt/tool/mytool.py --x %f'
app libreoffice-calc 'Exec=libreoffice --calc %U'
app libreoffice-startcenter 'Exec=libreoffice %U'
app game 'Exec=env WINEPREFIX=/p wine "/games/My Game/Game.exe"'
# lutris-library's entries: Epic's launcher (id 4) and a game in its prefix (id 9), EA's in its own
mkdir -p "$t/epic" "$t/ea" && ln -s . "$t/epic/pfx"
lut() { app "net.lutris.$1" $'Exec=env LUTRIS_SKIP_INIT=1 lutris lutris:rungameid/0\nX-AgrOS-WinePrefix='"$2"$'\nX-AgrOS-WineExe='"$3"; }
lut epic-games-store-4 "$t/epic" EpicGamesLauncher.exe
lut some-epic-game-9 "$t/epic" Game64.exe
lut ea-app-1 "$t/ea" EALauncher.exe
run() { PATH=$t/bin:$PATH XDG_DATA_HOME=$t/share XDG_DATA_DIRS=$t/none "$here/.local/bin/app-for-window" "$@"; }

[[ $(run org.cachyos.cachyos-pi 0) == cachyos-pi ]] || fail "reverse-DNS class against a short StartupWMClass"
[[ $(run lutris 0) == net.lutris.Lutris ]] || fail "short class against a reverse-DNS id"
cp /bin/sleep "$t/bin/mytool"
"$t/bin/mytool" 30 >/dev/null 2>&1 & p1=$!
# (the stand-ins' output off the runner's pipe: the Wine one's sleep, a child left by kill, held it open 30 s)
# (LibreOffice: /usr/bin/libreoffice a link to soffice, which runs soffice.bin, its windows' class soffice)
mkdir -p "$t/lo"; printf '#!/bin/sh\n' >"$t/lo/soffice"; chmod +x "$t/lo/soffice"; ln -s "$t/lo/soffice" "$t/bin/libreoffice"
cp /bin/sleep "$t/lo/soffice.bin"; "$t/lo/soffice.bin" 30 >/dev/null 2>&1 & p3=$!
(exec -a /usr/bin/wine64 bash -c 'sleep 30; :' x "/games/My Game/Game.exe") >/dev/null 2>&1 & p2=$!
sleep 0.2
[[ $(run sun-awt-X11-XFramePeer $p1) == tool ]] || fail "by program: the shown app over the hidden one ($(run x $p1))"
[[ $(run game.exe-unknown $p2) == game ]] || fail "a Wine window by its .exe"
[[ $(run soffice $p3) == libreoffice-startcenter ]] || fail "LibreOffice's soffice window: Start Center ($(run soffice $p3))"
[[ -z $(run nothing-like-it $$) ]] || fail "printed an app for a window that has none"
# (Proton's processes: WINEPREFIX the prefix's pfx, a link back to it here)
(export WINEPREFIX=$t/epic/pfx; exec -a 'C:\\Epic\\EpicWebHelper.exe' bash -c 'sleep 30; :') >/dev/null 2>&1 & p4=$!
(export WINEPREFIX=$t/epic; exec -a 'Z:\\games\\Game64.exe' bash -c 'sleep 30; :' x 'Z:\games\Game64.exe') >/dev/null 2>&1 & p5=$!
(export WINEPREFIX=$t/ea; exec -a 'C:\\EA\\EADesktop.exe' bash -c 'sleep 30; :') >/dev/null 2>&1 & p6=$!
sleep 0.2
[[ $(run steam_app_default $p4) == net.lutris.epic-games-store-4 ]] || fail "a Lutris launcher's window by its prefix ($(run steam_app_default $p4))"
[[ $(run steam_app_default $p5) == net.lutris.some-epic-game-9 ]] || fail "a game in its launcher's prefix by its .exe ($(run steam_app_default $p5))"
[[ $(run steam_app_default $p6) == net.lutris.ea-app-1 ]] || fail "another launcher's window by its own prefix ($(run steam_app_default $p6))"
pkill -P $p2; kill $p1 $p2 $p3 $p4 $p5 $p6
echo "ok app-for-window"
