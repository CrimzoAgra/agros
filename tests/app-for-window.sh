#!/usr/bin/env bash
# app-for-window: a window's app file by its class's last part, by its program (through a link: LibreOffice), a Wine
# .exe, hidden apps last, or none
set -euo pipefail
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
run() { PATH=$t/bin:$PATH XDG_DATA_HOME=$t/share XDG_DATA_DIRS=$t/none "$here/.local/bin/app-for-window" "$@"; }

[[ $(run org.cachyos.cachyos-pi 0) == cachyos-pi ]] || fail "reverse-DNS class against a short StartupWMClass"
[[ $(run lutris 0) == net.lutris.Lutris ]] || fail "short class against a reverse-DNS id"
cp /bin/sleep "$t/bin/mytool"
"$t/bin/mytool" 30 & p1=$!
# (LibreOffice: /usr/bin/libreoffice a link to soffice, which runs soffice.bin, its windows' class soffice)
mkdir -p "$t/lo"; printf '#!/bin/sh\n' >"$t/lo/soffice"; chmod +x "$t/lo/soffice"; ln -s "$t/lo/soffice" "$t/bin/libreoffice"
cp /bin/sleep "$t/lo/soffice.bin"; "$t/lo/soffice.bin" 30 & p3=$!
(exec -a /usr/bin/wine64 bash -c 'sleep 30; :' x "/games/My Game/Game.exe") & p2=$!
sleep 0.2
[[ $(run sun-awt-X11-XFramePeer $p1) == tool ]] || fail "by program: the shown app over the hidden one ($(run x $p1))"
[[ $(run game.exe-unknown $p2) == game ]] || fail "a Wine window by its .exe"
[[ $(run soffice $p3) == libreoffice-startcenter ]] || fail "LibreOffice's soffice window: Start Center ($(run soffice $p3))"
[[ -z $(run nothing-like-it $$) ]] || fail "printed an app for a window that has none"
kill $p1 $p2 $p3
echo "ok app-for-window"
