# Apps

Everything here comes installed, listed next to the Windows app it replaces.

| App | Instead of |
|---|---|
| **LibreWolf**: Firefox without the telemetry, with the Lagoon theme | Chrome, Edge |
| **Equibop**, themed in your colours | Discord |
| **Spotify**, themed in your colours | Spotify |
| **LibreOffice** | Microsoft Office |
| **Text Editor** | Notepad |
| **gThumb** (**Thumbnails** in the app list): view your pictures; rotate, crop or resize one and save it | Photos |
| **mpv**, a video player | Media Player |
| **VSCodium**, VS Code's open-source build | VS Code |
| **Thunar**: the bar at the bottom shows how full the drive is (it changes colour when the drive is nearly full); right-click a picture → **Set as wallpaper** | File Explorer |
| **File Roller** + 7-Zip (Extract/Compress in the right-click menu) | WinRAR, 7-Zip |
| **qBittorrent** | qBittorrent |
| **Proton VPN** | Proton VPN |
| **balenaEtcher** | Rufus |
| **Phone Link** (scrcpy): your Android phone's screen on the PC | Phone Link |
| **AntiMicroX**: a controller as keyboard and mouse | JoyToKey |
| **Document Scanner** and printing (HP printers included) | HP Smart |
| **Nuvio**, **ArtCraft** | |
| **Claude Code**, in the terminal and in VSCodium | |

For WhatsApp, Outlook, Teams and OneDrive, use their web versions in LibreWolf. LibreWolf's own built-in VPN is turned
off: Proton VPN is the VPN.

VSCodium opens on an empty window; the windows you had a folder open in come back. Claude Code asks whether to trust a
folder the first time you start it in that folder.

## Hardware apps

These install when you choose **Hardware apps** after your first login, for whatever's plugged in:

| App | For |
|---|---|
| Polychromatic + OpenRazer | Razer devices (instead of Synapse) |
| Solaar | Logitech devices (instead of G Hub / Options+) |
| Boxflat | Moza racing wheels (instead of Pit House) |
| OpenTabletDriver | Drawing tablets |
| The camera switch | The Lenovo Legion's webcam switch |
| The NVIDIA driver loaded early | An NVIDIA graphics card (the boot splash comes up on it) |
| VMware Workstation | Virtual machines |

## Installing more

- **From the repos**: `paru <name>` in a terminal searches Arch's packages and the AUR, Arch's community collection;
  `paru -S <name>` installs one.
- **Flatpaks**: `flatpak install <name>`.
- **AppImages**: double-click one. It asks before running it, then installs itself, appears in the app menu, and
  keeps itself updated. An app's own **Update** button asks too ("Update <app>?"): say yes only when you clicked it.
