# AgrOS: Hyprland + Caelestia, as a CachyOS-based distro

AgrOS is a whole desktop installed in one go, on top of CachyOS. You get Hyprland (Lua config) with the
[Caelestia](https://github.com/caelestia-dots/shell) shell, patched with a dock and other changes, and a
Caelestia-style login screen. It comes with fixes for games, tray apps and the keyboard, every app below with its
settings, and Capri, the desktop companion. It's made for two machines: a Lenovo Legion Pro 7 (Gen 10) laptop and a
desktop (RTX 2060, external monitor). Things that depend on the hardware check for it, so the same install works on
both. The files are laid out like `$HOME`.

**What's not in this repo:** your personal data, meaning logins, keys, your browser profile and bookmarks (they travel
encrypted on your pen drive, see below), and copyrighted wallpapers. The default wallpaper
(`Pictures/Wallpapers/wallpaper.jpg`) is original artwork made for AgrOS.

Laptop settings and lighting are in a separate repo: **legion-control-linux**.

## Install AgrOS

1. **Boot the AgrOS ISO** (from [agros-iso](https://github.com/CrimzoAgra/agros-iso): CachyOS's installer with the
   AgrOS step) and install as usual, connected to the internet. Hyprland is picked for you.
2. At the end, the installer sets everything up for your user by itself. It runs every step of `setup.sh` (table
   below) unattended, with no questions; expect it to take a while (packages are built). You don't run `setup.sh`.
3. Reboot and log in. At your first login, AgrOS sets the wallpaper and its colours and applies the app settings,
   then offers to restore your accounts.
4. **The one thing you run:** plug in your pen drive and click *Restore now*, or run `agros-personal`. It brings back
   your logins (Discord, Spotify, Nuvio, Proton VPN, Steam, Lutris's stores, Claude Code, GitHub), the login keyring
   and your LibreWolf profile (bookmarks, passwords, extensions). Capri installs right after that, since her fork is
   private and needs your GitHub login.

If the install had no network, the steps it couldn't do run by themselves at the first boot with network
(`agros-firstboot.service`; log in `/var/log/agros-install.log`).

Already on CachyOS? `sudo ~/Projects/agros/install/agros-install $USER` does the same as the installer (clone the
repo to `~/Projects/agros` first).

Before reinstalling, put this PC's accounts on the pen drive: `agros-personal --save` (encrypted with a passphrase
you pick; never in the repo).

## Contents

- [Install AgrOS](#install-agros)
- [The setup steps](#the-setup-steps)
- [Layout](#layout)
- [Desktop Settings app](#desktop-settings-app)
- [Desktop and Caelestia](#desktop-and-caelestia)
- [Windows and keys](#windows-and-keys)
- [Screens and colours](#screens-and-colours)
- [Games](#games)
- [Tray apps and startup](#tray-apps-and-startup)
- [Apps](#apps)
- [Updates and system](#updates-and-system)
- [Laptop hardware](#laptop-hardware)
- [Lua API (`dots`)](#lua-api-dots)
- [Keeping it in sync](#keeping-it-in-sync)
- [Tests](#tests)
- [Troubleshooting](#troubleshooting)

## The setup steps

The installer runs these for you (`install/agros-install`). By hand, as your normal user, `./setup.sh` runs them too.
One user per machine: the system parts (pacman's hooks, the boot's update, the login screen) serve the account they
were set up for, and `dotfiles-check` on any other account says nothing about them.

Made for a fresh **CachyOS Hyprland** install (GRUB or Limine boot menu, Noctalia shell by default). `setup.sh` runs
the steps in `setup/modules/` in order, asking before each one that installs or changes the system (`files` and
`desktop` always run; replaced files are backed up):

| Step | What it does |
|---|---|
| `keyboard` | Keyboard layout (asked, the current one by default): text consoles, login screen and Hyprland all use the system's |
| `packages` | Desktop packages: official repos via pacman, AUR via paru (installed if missing); the real Quickshell in place of CachyOS's `noctalia-qs` |
| `caelestia` | Caelestia's own installer (`caelestia install`): the shell and its default configs (not its Spotify/VS Code parts) |
| `apps` | GPU drivers (`chwd`), the CachyOS gaming packages and the apps below; removes CachyOS's Firefox once LibreWolf is in (its profile in `~/.mozilla` stays) |
| `capri` | Capri, the Edgerunners 2 desktop companion (asked, yes by default; `--no-capri` leaves her out): my fork of CapriDesktop merged with its latest release, updated from the Updates app (a new release looked for at every boot) |
| `files` | Your files into your home, over Caelestia's defaults; anything replaced is backed up to `~/.dotfiles-backup/<date>/` |
| `desktop` | Builds the Caelestia overlay, sets the wallpaper and colours, turns off GTK apps' own window buttons, imports the LibreWolf settings and, asked (not with `--yes`), its bookmarks, installs the VSCodium extensions and Claude Code plugins |
| `shell` | fish as your login shell |
| `system` | With sudo: the pacman hook, the shell at normal CPU priority (ananicy rule), Bluetooth, updates at every boot, hidden boot menu, screens' best mode from boot, NVIDIA driver loaded early, the login screen and faster splash, keyring unlocked at login |
| `hardware` | Only on matching hardware: the Legion's camera switch, Legion Control, a VMware VM's screen following its window |
| `personal` | Only with `--personal`: your accounts back from your pen drive, else each app opened to sign in (see below) |
| `noctalia` | Last: removes Noctalia (CachyOS's default shell and login screen), only once the Caelestia login screen is in, and its leftover apps (Dolphin, kitty, Alacritty: Thunar and foot are used instead) |

The apps, with the Windows ones they replace in brackets:

- CachyOS gaming packages: Proton, Wine, Steam, Lutris, MangoHud, Gamescope, GOverlay, Faugus
- Equibop (Discord, themed with your colours)
- Spotify (Flatpak, for your user) with Spicetify (Caelestia's theme in your colours, marketplace)
- LibreWolf; Nuvio and ArtCraft Launcher (Flatpaks from their GitHub releases)
- Proton VPN
- With the device plugged in (else skipped: plug it in and run `./setup.sh --only apps`): Boxflat (Moza Pit House),
  OpenRazer + Polychromatic (Razer Synapse), Solaar (Logitech G Hub, Logi Options+), OpenTabletDriver (tablet app)
- File Roller + 7-Zip (WinRAR, 7-Zip; Extract/Compress in Thunar's right-click menu)
- VSCodium, VS Code's open-source build (with your extensions), LibreOffice (Microsoft Office), qBittorrent, AntiMicroX (JoyToKey)
- VMware Workstation (the AUR package: its installer from a copy on archive.org, as Broadcom gives it only to
  signed-in users; checked against the package's checksum)
- HP Deskjet 1050 J410: HP's Linux driver (HPLIP), printing and scanning; add the printer in Print Settings once it's
  plugged in, scan with Document Scanner
- balenaEtcher (Rufus), and Phone Link: scrcpy, your Android phone's screen on the computer (USB debugging on, phone
  plugged in; its screen off while mirrored, kept awake, 20 Mbit/s)
- Capri, the Edgerunners 2 desktop companion: [my fork](https://github.com/CrimzoAgra/capri-overlay) (private) of
  [CapriDesktop](https://github.com/nunezValen/CapriDesktop), her chat on your Claude Code (see [Apps](#apps))
- WhatsApp, Outlook, Teams and OneDrive: use the web versions

Options:

```sh
./setup.sh --yes                   # yes to everything (but the bookmarks: a later run asks)
./setup.sh --user-only             # only the steps in your home (files, desktop): no packages, no sudo
./setup.sh --only files desktop    # only these steps
./setup.sh --list                  # the steps
./setup.sh --no-capri              # without Capri
./setup.sh --save-personal         # this PC's accounts onto your pen drive (encrypted; never in the repo)
./setup.sh --personal              # ...and at the end, your accounts back from it
```

Your accounts (`--personal`): LibreWolf's Firefox account, bookmarks, passwords, cookies and extensions; Discord
(Equibop), Spotify, Nuvio, Proton VPN (and the login keyring they keep their keys in); Lutris's store logins; Steam's
login and settings; Claude Code's account, settings, skills and memories (its plugins come with the desktop step); the weather widget's place.
`--save-personal` puts them, apps closed, in `dotfiles-personal.tar.gpg` on your pen drive
(the removable drive plugged in, mounted if it isn't, or the folder you name after it), encrypted with a passphrase you
pick (gpg, AES-256): a lost drive gives nothing without it. `--personal` decrypts it straight into place (nothing
unencrypted written anywhere else) and backs up what it replaces; the keyring opens with your old login password.
Never in the repo: saved logins get past your password and 2FA, and git keeps every version. With no drive, it opens
each app for you to sign in instead (LibreWolf's Firefox account brings bookmarks and passwords through Sync) and asks
the weather widget's place. Save again now and then: logins expire.

Other screens get their own resolution at its fastest refresh rate; a machine's own screens go in
`.config/caelestia/user/hosts/<hostname>.lua` (see [Screens and colours](#screens-and-colours)).

## Layout

| Path | What's there |
|---|---|
| `setup.sh`, `setup/` | The installer: `lib.sh` (shared helpers) and `modules/NN-<step>.sh` |
| `system/` | The parts installed outside your home, run with sudo (setup's `system` step) |
| `.config/caelestia/` | Hyprland settings (`hypr-user.lua`, `hypr-vars.lua`, `user/`) and Caelestia settings (`shell.json`) |
| `.config/quickshell/` | The switcher, desktop widgets, Updates and Desktop Settings apps, their shared colours (`common/`), and the dock's pins |
| `.local/share/caelestia-overlay/` | My changes to Caelestia's own code, patched in by `caelestia-overlay` |
| `.local/share/caelestia-greeter/` | The login screen |
| `.local/bin/` | Scripts (on the session's `PATH` through `.config/environment.d/10-local-bin.conf`) |
| `.config/uwsm/env.d/` | `~/.local/bin` on the desktop's PATH (uwsm replaces environment.d's PATH with the login's); Qt's harmless Wayland text-input warnings silenced; `nvidia-vaapi.sh`: hardware video decoding in LibreWolf on the NVIDIA card, only when that card drives a screen; as its trade-off it sets `MOZ_DISABLE_RDD_SANDBOX=1`, so web video is decoded outside LibreWolf's RDD sandbox (the sandbox blocks the NVIDIA driver) |
| `.config/systemd/user/` | User services: game-focus, tray-keeper, the update check, lutris-library |
| `.local/share/applications/` | Launcher entries |

## Desktop Settings app

A window in Caelestia's style for changing these dotfiles without editing them (Super menu: "Desktop Settings").
Changes apply right away.
- **`.config/quickshell/settings/`**: the app (`desktop-settings [page]` opens it, on a page if given)
- **`.local/share/dots-settings/schema.json`**: every setting, its default, and how a change applies (reload
  Hyprland...). A new setting is added here, then read where it's used
- **`.local/bin/dots-settings`**: saves your choices (only those that differ from the default) to
  `~/.config/dots/settings.json`, for this machine only, and writes them to `settings.lua` for Hyprland, where
  `dots.setting(key)` reads them; scripts use `dots-settings get KEY` or `values`
- Pages:
  - **Windows**: floating or tiling, focus on click or hover, cascading, title bars, mouse acceleration, mouse DPI (the
    mouse's own, through Solaar: `.local/bin/mouse-dpi`, also at login; Solaar in the tray puts it back on reconnect)
  - **Features**: low input lag in games (tearing allowed for games only), each of game-focus's four
    behaviours, store launchers starting minimised, each Lutris change, and
    each change to Caelestia (listed from `caelestia-overlay`'s and the Lutris overlay's `patch.py --list`, so new ones
    show up by themselves). A Caelestia change turned off is left out of the rebuild (`Off:`, not a warning)
  - **Startup**: the apps `user/apps.lua` can start at login (Lutris, Proton VPN and Capri on by default;
    Solaar and ArtCraft off), and every app with a standard
    autostart entry (`/etc/xdg/autostart`, `~/.config/autostart`); turning one of those off writes your copy of it
    with `Hidden=true`, as GNOME's startup settings do
  - **Keyboard**: my shortcuts (`dots.bind` in `user/keys.lua`, `user/windows.lua` and `user/apps.lua`; defaults in the schema) and
    Caelestia's (its `kb*` variables, by its sections, minus the ones `hypr-vars.lua` turns off; your changes go back
    through `hypr-vars.lua`). + records a new one: Hyprland switches to an empty submap (`dots-capture`) meanwhile so
    every key reaches the app, and Esc always leaves it. A shortcut used twice shows in red

## Desktop and Caelestia

Caelestia's own Hyprland config (`caelestia install` puts it in `~/.config/hypr`) is never edited, as Caelestia's
README asks: everything goes in the files Caelestia leaves for you, so its updates apply cleanly.

- **`.config/caelestia/hypr-user.lua`**: my Hyprland settings, loaded after Caelestia's own: keyboard layout, no mouse
  acceleration (unless turned on in the Settings app), the mouse pointer drawn as part of the picture (so it doesn't stay on the shutdown screen), the `dots`
  table ([Lua API](#lua-api-dots)), and the modules in `user/`
- **`.config/caelestia/user/`**: the rest of my Hyprland settings, by topic (saving one reloads Hyprland):
  - `monitors.lua`: layout and refresh rates; `hosts/<hostname>.lua`: one machine's own screens
  - `workspaces.lua`: workspaces synced across screens
  - `keys.lua`: the switchers, Scroll Lock, lock badges and my binds
  - `windows.lua`: windows like on Windows
  - `apps.lua`: Lutris, games, Spotify, Proton VPN; store launchers a game starts (EA App, Ubisoft Connect, Epic) open
    minimised
  - `titlebars.lua`: title bars on floating windows
  - `desktop.lua`: widgets, login screen, what runs at login (Bluetooth on, update and health checks)
- **`.config/caelestia/hypr-vars.lua`**: Caelestia's variables I change
  - No special workspaces (music, communication, todo...): apps open on the normal ones, and the touchpad's 3-finger
    swipes up and down open none (`user/workspaces.lua`)
  - Caelestia's own Alt+Tab (window cycling), Print (full screenshot), float and maximise keys off, as `user/` binds
    those keys
  - Sleep (Super+Shift+L) suspends when the PC can't hibernate (CachyOS's default zram-only swap), not nothing
- **`.config/caelestia/shell.json`**: Caelestia settings
- **`.local/share/caelestia-overlay/`**: my changes to Caelestia, patched in by `patch.py`. A change whose code no
  longer fits a new Caelestia version is skipped, not broken; one that still fits but whose QML no longer loads (a
  renamed Caelestia component) is reported by `dotfiles-check`
  - Bar:
    - A dock (`Dock.qml`, `DockMenu.qml`): pinned apps and open windows, Force quit; minimised windows dimmed; a
      click on a window or its preview brings it to the front
    - Right-clicking the empty bar between the workspaces and the tray (not on the dock) opens a menu (`BarMenu.qml`)
      with Task Manager (btop) and the floating/tiling switch; it closes when the mouse moves away along the
      bar
    - Hovering a workspace shows a live preview of it: its windows where they are, over the wallpaper
      (`WorkspacePreview.qml`)
    - Window peek, like Windows' Aero Peek: resting the pointer on a preview for a moment shows what it shows alone on
      the desktop (widgets included), until the pointer leaves it: a window's (the dock's) that window, a workspace's
      (the workspace picker's) every window on it. The other windows fade out, their blur with them, and fade back
      (`dots.peek_screen` in `user/windows.lua`, tags and their rules); nothing is moved or focused (`WindowPeek.qml`).
      Windows on a workspace not being shown: live pictures of them instead (`PeekLayer.qml`)
    - The clock's hour and minute digits line up in columns: each digit, drawn as normal, centred in a slot as wide as
      the widest (not Caelestia's per-line stretching, nor the font's same-width digits, whose 1 is drawn wider)
    - Workspaces and the tray arrow light up under the mouse like the power button; clicking the workspace you're
      on does nothing (Caelestia opened a special workspace)
    - A collapsed tray that opens on a click (not hover) and closes on a click elsewhere on the bar or when the pointer
      leaves the bar for a window (no input grab: windows still scroll while it is open); tray icons A-Z;
      Spotify's tray icon shown; Steam's tray menu shows installed games only; right-clicking a tray icon with no
      standard menu (Wine apps: the Epic launcher) opens the app's own (`.local/bin/tray-menu`)
    - A "safe triangle" for bar popouts: moving towards an open popout doesn't switch to the buttons on the way
    - Bluetooth pairing from the Bluetooth popout
    - A Scroll Lock icon (`ScrollLock.qml`, `LockStatus.qml`); Caps/Num Lock icons re-read the keyboard after login
      and on keymap changes (no Caps Lock shown on at boot)
    - The logo does nothing (no click)
  - Super menu (launcher):
    - Pin buttons; favourites at the top, then everything A-Z
    - A "check for updates" button next to the search bar: its icon spins while checking, then a notification says
      the result (also if the menu was closed meanwhile) and opens the Updates app
    - Opens over fullscreen games and videos too (`general.showOverFullscreen` in `shell.json`; notifications and
      toasts stay off fullscreen windows)
  - Notifications:
    - The sidebar slides down from the top when you hover the top edge above it, with notifications only (no
      divider, ending above the bottom-right panel); Super+K opens it too, merged with the bottom-right panel
      It closes without bouncing back, and hovering the edge doesn't open it while a notification pop-up is on screen
      (nor afterwards for a pointer that stayed there: move away and back)
    - One neutral colour whatever their urgency
    - A click (pop-up or in the sidebar) runs the notification's action, like its button, and brings the app that
      sent it to the front
  - Lock screen: like the login screen (blurred, dimmed wallpaper, a text cursor, its elements coming down onto the
    screen from in front of it, out of focus and sharpening, from the centre outward); a wrong password said at once
    (its own PAM config, `assets/pam.d/passwd`, with nodelay on pam_unix and pam_faillock; pam_faillock still counts
    and locks out)
  - Other: brightness only on built-in screens; the dashboard's calendar and weather in the system language; no volume
    pop-up when the shell starts or the sound device changes
- **`.local/bin/caelestia-overlay`**: builds `~/.config/quickshell/caelestia` (Caelestia + the patches); also run by the
  pacman hook after every `caelestia-shell` update. Skipped patches go to `~/.local/state/caelestia-overlay-skipped`
  (reported by `dotfiles-check`)
- **`.local/bin/caelestia-restart`**: restarts Caelestia with a clean environment (also Ctrl+Super+Alt+R), keeping
  Spotify hidden
- **`.local/bin/caelestia-pin`**: pin apps to the launcher or dock from a picker
- **`.config/quickshell/widgets/`**: desktop widgets styled after the Spider-Verse wallpaper
  - Comic panels with halftone dots and the film's red/cyan misprint glitch, laid out in the sky around the falling
    Miles
  - A clock, weather with a 3-day forecast, a calendar, "Spidey-sense" CPU/RAM/GPU/SSD meters (they shake when the
    PC runs hot), and a now-playing card with controls
  - Weather follows Caelestia's `services.weatherLocation` in `shell.json` (a city, or `lat,lon`; empty finds you by
    IP, as on a fresh install). The pencil by the weather panel's tab (with the mouse over it) types it there; it's
    this machine's own, so setup keeps yours and `dotfiles-sync` doesn't copy it into the repo; media shows the same player as Caelestia's dashboard
  - A dimmed skeleton until the first forecast or player arrives; kept updating while windows cover them, so they're
    current whenever the desktop shows
  - Started by `widgets-start` once Caelestia has loaded; `user/desktop.lua` blurs behind the panels
  - Font: `.local/share/fonts/Bangers-Regular.ttf` (Google Fonts, SIL Open Font License)
- **`.config/quickshell/sidedock/pins.json`**: the dock's pinned apps (`caelestia-pin dock`; the folder is named after
  a separate dock it once had)
- **`.config/quickshell/common/Scheme.qml`**: Caelestia's colours for the Settings, Updates and switcher apps (its
  `scheme.json`, followed live; Caelestia's dark scheme until it loads). Each app loads it at run time (a `Loader`):
  Quickshell blocks imports from outside a config's folder, and an app doesn't reload when only this file changes
- **`.local/share/caelestia-greeter/`**: Caelestia-style login screen for greetd (cage + Quickshell)
  - Picks each screen's best mode (`best-mode`, with the rule in `screenmode.py` it shares with
    `system/boot-video-mode`)
  - Once the wallpaper shows, its elements come down onto the screen from in front of it (bigger and out of focus,
    shrinking and sharpening into place): the password bar first, then the rest from the centre outward
  - The wallpaper and colours are copied to it at every login (`greeter-theme-sync`)
  - It logs in the account that ran setup only; another account logs in from a text console (Ctrl+Alt+F2)
  - A wrong password said at once: its PAM service, `/etc/pam.d/greetd`, is made by `greetd-pam` from `greetd.pam` and
    the system's own stack as it is (its auth lines, with nodelay on pam_unix and pam_faillock, which still counts and locks
    out; the keyring's lines kept), and made again after each `pambase` or `pam` update (a pacman hook), so it follows
    the system's changes. A stack it can't follow leaves the file as it was, said. sudo and the text consoles keep theirs
- **`.config/spicetify/Themes/caelestia/user.css`**: Caelestia's Spotify theme (from its dots)
  with thin scrollbars; its colours (`color.ini`) are written by Caelestia
- **`.config/hypr/xdph.conf`**: screen sharing without asking each time
- **`Pictures/Wallpapers/`**: wallpaper (Spider-Man: Into the Spider-Verse still, © Sony Pictures; kept for personal
  use)

## Windows and keys

- **Workspaces** (`user/workspaces.lua`): synced across screens. Each screen has its own 10 workspaces, in screen
  order (the 1st screen 1-10, the 2nd 11-20...), and every screen always shows the same one of its 10 (a column):
  - Super+N shows N on all of them at once; anything else that changes a screen's workspace (the touchpad's swipe, a
    window moved and followed, the bar, a script) brings the others to the same column a moment later
  - Next/previous (Super+scroll, Ctrl+Super+Left/Right, Super+PageUp/PageDown) stay within the focused screen's 10 and
    stop at its 1st and 10th (no wrap: a scroll a notch too far doesn't fling you from the 10th back to the 1st); the
    swipe past the last one stays there too
  - Moving a window to N (Super+Alt+N, Super+Shift+N without following it, Super+Alt+PageUp/PageDown) puts it on the same
    screen's N; Ctrl+Super+N and Ctrl+Super+scroll go to screen N, or the next/previous screen, same column
  - With one screen, Caelestia's own workspaces and keys, unchanged
  - A screen unplugged (or the laptop lid closed, below): each of its workspaces with windows (minimised windows with
    theirs) goes to the next empty workspace of the first screen left, in order, not among the windows already there
    (onto the same number once there are no empty ones). Plugged in again, its windows go back to their own workspaces
    on it, the ones still where they were put (one you've moved since stays). It's remembered by the screen's make,
    model and serial, so a different screen gets nothing, and survives the config reloads screen changes make (in
    Hyprland's runtime folder, `dots-screens.lua`: window addresses only mean something in this session). Screens that
    stay take their windows along when their number changes (the 2nd becoming the 1st, and back)
- **Laptop lid** (`user/monitors.lua`): closed with another screen connected (docked: logind doesn't suspend), the
  laptop's panel turns off and its windows go to the other screen as above; opened, it's back with them. Closed with no
  other screen: logind suspends as usual. Booting or reloading with the lid closed keeps it off
- **Switchers** (`.config/quickshell/switcher/`, in Caelestia's style; releasing Super/Alt or clicking picks, Tab and the
  arrow keys move, the mouse over a preview only highlights it, Escape cancels):
  - Super+Tab: live previews of the workspaces with windows, in workspace order, Tab cycling on from the current one
  - Alt+Tab: the current workspace's windows, most recently used first (minimised ones too), each preview in its
    window's shape
- **Windows like on Windows** (`user/windows.lua`):
  - Floating by default, with a floating/tiling switch in the bar's right-click menu (remembered in
    `~/.local/state/window-mode`), also on Super+Alt+Space, for every workspace. Switching to floating places windows
    like new ones: maximised windows stay maximised, the rest cascade from the middle at the standard size
  - New windows open in the middle at one standard size: 60% of the screen's height, in a maximised window's shape
    (dialogs and pop-ups keep their own size); several opened in a row cascade down and right from there, one title bar
    apart, as on Windows
  - A Steam game shows in the dock under its own name and icon (Steam's shortcut for it), as in the switchers
  - Super+M minimises: the window stays in the dock, dimmed; clicking it, Alt+Tab or Super+Alt+M brings it back.
    Alt+Tab away from a fullscreen window (a game) minimises it, as on Windows; it comes back fullscreen
  - Super+Alt+F, the title bar button, a double-click on the title bar or an app's own button maximises inside the
    same gaps as tiled windows; dragging a maximised window by its title bar (the plugin's, or the app's own: GTK
    header bars, LibreWolf's tabs, VSCodium's) un-maximises it round the pointer and the drag goes on; resizing it
    just makes it no longer maximised (both need the title bar plugin's hook)
  - Windows resize by dragging their edges and corners (from the border to 15 px outside it), floating and tiled; an
    edge moves only that edge, a corner both (as far along each edge as Hyprland's corner cursor), and a window with a
    title bar resizes upwards from the bar's top, its top corners there (where the bar meets the app is a side; the
    plugin's patch). Not while a game is open: the grab area of a borderless game reached the next screen and the
    screen's corners, so a click there started resizing it
  - The window clicked, or picked in the dock or Alt+Tab, comes to the front; in floating mode the pointer stays
    where it is, and focus changes on a click, not on hover
  - Clicking a notification brings the app that sent it to the front (or opens it)
- **Title bars** (`user/titlebars.lua`), on floating windows only:
  - Minimise, maximise (a restore icon when maximised) and close, styled like Caelestia, with a hover highlight:
    40 px wide and the bar's full height, side by side at the right edge, no background until hovered
    (a rounded rectangle inside the button: faint white for minimise and maximise, the power button's red for close)
  - The only window buttons there are: GTK apps (LibreWolf included, and any installed later) draw none (the GTK button
    layout, set by `setup.sh`), VSCodium's are hidden (`window.controlsStyle`); Steam, which can't turn its own off,
    gets no bar
  - None on fullscreen windows or games (the `game` tag: Proton's `steam_app_<id>`, Lutris's, gamescope's and native
    Steam games; often borderless over the whole screen)
  - The hyprbars plugin with my patch (`.local/share/hyprbars/hyprbars.patch`: hover highlight, restore icon,
    un-maximise on drag, square buttons; it also hooks Hyprland's drag start, for any window, bar or not: a drag of a
    maximised window by the app's own title bar or edges, and edge resizes moving one edge only), built by `hyprbars-build` for the running Hyprland into `~/.local/lib/hyprbars/`. It runs
    as Hyprland starts (`--login`): after a Hyprland update or a patch change it rebuilds in the background, with the
    AUR build (no highlight) meanwhile, and a notification if the build fails
- **Keys** (`user/keys.lua`):
  - Ctrl+Shift+Esc opens btop (Task Manager; the open one if there is); Print selects an area to screenshot
  - Ctrl+Super+Alt+R restarts the shell
  - Scroll Lock as a real lock with its keyboard light, like Caps and Num Lock (`.local/bin/scroll-lock`: builds your
    layout's keymap with Scroll Lock on a free modifier, which Hyprland loads, and keeps the bar's icon in step with
    the light)
  - Caps/Num Lock badges follow whichever keyboard was used last

## Screens and colours

- **`user/monitors.lua`**: the shared rules and a
  fallback for any other screen (to the right of the others); **`user/hosts/<hostname>.lua`**: one machine's own screens, loaded on that machine only
  (`LegionCachy.lua`: the laptop's OLED and a Samsung LF27T450F; `TerraCachy.lua`: the desktop's Samsung C24F390 at
  its fastest mode). Copy it under your machine's hostname to fix a
  screen's mode or position by hand

## Games

- **`.config/environment.d/shader-cache.conf`**: keeps compiled game shaders (the NVIDIA driver would otherwise trim
  its cache, and games stutter again)
- **`.local/bin/steam-start`**: Steam in the tray, in a scope of its own (listed as an app, with its games inside). Lutris
  starts Steam games through it, so one launched while Steam is closed doesn't open Steam's window. No store launcher
  starts at login: Lutris does, in its tray
- **`.local/bin/nvidia-shader-fix`**: fixes Cyberpunk 2077 crashing at startup on Turing GPUs (RTX 20xx, GTX 16xx) with
  NVIDIA 610/615 drivers. Only applied where that's the case: adds itself to the game's Steam launch options when Steam starts
  (`steam-start`),
  and builds the fixed shader from the game's own files
- **`.local/bin/steam-installed-games`**: installed games, for the bar's Steam menu
- **`.local/bin/lutris-library`**: Lutris's Games view lists every game you own on Steam, EA, Ubisoft, Epic and GOG,
  installed first and the rest below (opening one installs it through its store). Rerun after every store sync by
  `.config/systemd/user/lutris-library.path`; an open Lutris shows the changes at once (the overlay's `library-refresh`
  action, asked over D-Bus; a plain Lutris once restarted). Installed Steam games join even when
  Lutris can't read the Steam library (game details private), with their covers (Steam's own copy when Lutris can't
  download one). A game on more than one store shows once: an installed
  copy, else the Steam one. The other copies go to Lutris's Hidden category. The store launchers (EA app, Ubisoft
  Connect, Battle.net, Epic, GOG Galaxy, Rockstar, Steam) are listed under Launchers in the sidebar (Library, below
  Uncategorized), installed or not: open one there to install it through Lutris (setup's apps step lists them too,
  making Lutris's folders and database first if it has never run). Steam installed on the system is listed installed:
  it opens it. A launcher lutris.net has no cover for gets one from `.local/share/lutris-library/covers` (Rockstar's)
- **`.local/bin/lutris`**: Lutris with the changes in `.local/share/lutris-overlay` (built into `~/.cache` the first
  time after Lutris or the changes update; Lutris starts unchanged, with a notification, if they no longer fit)
  - The grid splits into collapsible "Installed" and "Not installed" sections (`sections.py`), its covers a little
    bigger or smaller so the columns fill the window's width
  - Each game's store icon (Steam, EA, Ubisoft, Epic, GOG) in its cover's bottom-right corner, in light grey
    with the logo cut out of it (Ubisoft's: just the swirl), on the cover darkened
    towards that corner (`patch.py`). EA, Battle.net and Rockstar have no icon in Lutris: theirs are in
    `.local/share/lutris-overlay/icons` (Simple Icons). The sidebar's sources get the same icons, drawn the same way
  - Every cover in the Games view fills the same box, cropped at the edges (Steam's covers are 2:3, Lutris's 3:4)
  - Covers with rounded corners
  - Right-click → "Hide game from library" for uninstalled games too
  - The store launchers only under Launchers in the sidebar (a Library row, below Uncategorized), not among the games
  - A `library-refresh` action (D-Bus) for `lutris-library`: its changes show without a restart (not a setting)
  - Battle.net among its sources (Lutris turns on only Steam, EA, Ubisoft, Epic and GOG); switched off in Lutris's
    preferences, it stays off
  - Rockstar Games among its sources (Lutris has none; `rockstar.py`), like Battle.net with its sign-in (both
    `signin.py`): connect your
    Rockstar account (its own sign-in page) and it lists the games on it, read from inside the signed-in site
    (Rockstar has no public API); each reload signs in again unseen, else keeps the last list. Signed out, its games
    leave the Games view. Installing one installs the Rockstar Games Launcher first if needed, then adds the game and
    opens the launcher, where you install and play it (playing it from Lutris opens the launcher too)
  - Steam games start Steam through `steam-start` (its Steam runner setting, written if you have none)
  - Started at login in its tray only (`LUTRIS_START_HIDDEN=1`)
  - Games with no proper cover (none, a wide one, or Steam's padded one: its header art on a stretched background, when
    the publisher uploaded no cover) get one from SteamGridDB: `.local/bin/lutris-covers`, run in the background when
    the library changed. Needs a free API key (steamgriddb.com → Preferences → API) in `~/.config/dots/steamgriddb.key`,
    not in this repo; without it nothing happens
  - Its window, closed for a game ("Minimize client when a game is launched"), doesn't come back when the game closes:
    Lutris stays in its tray
  - Opening it while it runs in the tray doesn't redo its start-up (GPU checks that made the mouse stutter, a scan of
    every game folder): once per run
  - The GPU's name and ID (`vulkaninfo`, which also stutters) asked once per boot, at the login start
- **`.local/bin/game-focus`**: a user service (`.config/systemd/user/game-focus.service`)
  - A Steam game's sound plays only while its window is focused (other apps keep playing; a game you muted yourself stays
    muted)
  - In tiling mode, a game that goes fullscreen next to other windows moves to the first free workspace, and you with
    it; in floating mode it stays where it opened (Alt+Tab minimises it), and switching to tiling moves it then
  - When a game asks for attention (what flashes orange on the Windows taskbar), a notification shows until you clear
    it or go back to the game (also while it's minimised); clicking it takes you there
  - Closing a game closes its client: its store launcher (EA app, Ubisoft Connect, Epic...) a minute later (after its
    cloud save upload) unless its window is open, and Steam 15 s later if it's only in its tray (its window isn't
    open) and no other game is running or starting. What still runs of a Proton game two minutes after its
    last window closed (a game that doesn't exit, its crash reporter) is ended, so Steam doesn't count it as running

## Tray apps and startup

- **`.local/bin/after-games`**: waits while a game is open; the update check and `lutris-library` run after it, not
  while you play
- **`.local/bin/app-launch`**: how the config starts apps (Proton VPN, btop, an app opened from a
  notification): in a unit of its own under uwsm, like apps from the launcher
- **`.local/bin/tray-keeper`**: a user service (`.config/systemd/user/tray-keeper.service`); when Caelestia restarts it
  brings back tray icons apps don't re-add (Proton VPN), and keeps Spotify hidden
- **`.local/bin/spotify-tray`, `protonvpn-open`**: start Spotify / Proton VPN in the tray; opening them from the
  launcher or dock shows them (the launcher entries in `.local/share/applications/` run these). `spotify-tray` also
  re-applies Spicetify when a Spotify update undid it
- **`.local/share/applications/equibop.desktop`**: Equibop shown as Discord (name, description, icon)
- **`.local/share/applications/phone-link.desktop`**: scrcpy shown as Phone Link, no terminal, with
  `--turn-screen-off --disable-screensaver --stay-awake --video-bit-rate=20M`; scrcpy's own two entries hidden
- **`.local/bin/keyring-default`**: makes the "login" keyring (unlocked by your login password) the default, moving
  passwords over from another one
- **`.config/xdg-desktop-portal/hyprland-portals.conf`**: no "keep the screen on" portal: GTK's, the only one, needs a
  screensaver service this desktop lacks, so every request failed with log errors; games and video keep the screen on
  through Hyprland
- **`.local/bin/qmllint`**: Qt 6's qmllint first on the PATH (`/usr/bin/qmllint` is Qt 5's, which reports Quickshell
  files as broken)
- **`.local/bin/notify-wait`**: a notification that waits for its click (`notify-send -w`) and gives up when Caelestia
  restarts, so a click on a new notification can't reach an old one (used by `game-focus` and `update-apps`)
- **`.config/systemd/user/service-failed@.service`**: when game-focus or tray-keeper keeps crashing (5 times in a
  minute) it's stopped instead of restarting forever, with a notification showing its last error
- **At login** (`user/desktop.lua`): `widgets-start`, `greeter-theme-sync`, `console-clear` (no old
  text under the desktop at shutdown), `keyring-default`, `bluetooth-on`, `vm-screen-follow` (in a VM), the update check timer, and `dotfiles-check`
  after 30 s
- **`.config/autostart/`**: CachyOS's welcome app and Polychromatic's
  own autostart off (OpenRazer's service applies the
  lighting). Turning one on or off in the Settings app changes your copy here; `dotfiles-sync` commits it if it's in the repo
  already, else `dotfiles-sync add` it

## Apps

- **`.config/VSCodium/`**: VSCodium (VS Code's open-source build) settings and extension list (`extensions.txt`), with open replacements for the
  Microsoft-only extensions (basedpyright for Pylance, clangd for the C/C++ tools). Its launcher entries
  (`.local/share/applications/vscodium*.desktop`) show its logo without the white circle
  (`.local/share/icons/hicolor/scalable/apps/vscodiumlogo.svg`).
  Claude Code's plugins and conversations are in `~/.claude`, shared by both
- **`.local/bin/claude`**: Claude Code in the terminal (the CLI inside the editor's extension; without it, the next `claude` on PATH), for what the extension
  can't do, like `/plugin`. Its plugins (installed by setup's `desktop` step, `CLAUDE_PLUGINS` in
  `setup/modules/60-desktop.sh`): [ponytail](https://github.com/DietrichGebert/ponytail) (minimal code; needs
  Node.js) and Addy Osmani's [agent-skills](https://github.com/addyosmani/agent-skills), each at its repo's latest version (not pinned: what they are when setup runs). `.local/bin/claude-notify`: a notification when it finishes an answer (its Stop hook, added to `~/.claude/settings.json` by the same step)
- **`.local/share/firefox/`**: LibreWolf bookmarks (toolbar, `bookmarks.html`, Firefox's format) and the settings Firefox Sync doesn't
  carry (`settings.js`: privacy, new tab, theme, toolbar layout, sidebar; add a `user_pref` line to keep another),
  the Lagoon theme with the Linux system theme off (a new profile gets Lagoon installed from addons.mozilla.org at setup),
  and the new tab's background picture (`newtab-wallpaper.jpg`). All updated by `dotfiles-sync`
- **`.config/librewolf/librewolf/librewolf.overrides.cfg`**: LibreWolf keeps cookies, logins and history when it closes
  (it erases them on every quit by default), allows the Firefox account and Sync, and tells sites the desktop's dark
  mode (Firefox's fingerprinting protection, all of it but that, instead of Resist Fingerprinting, which always says light).
  The default browser
- **`.config/mimeapps.list`**: default apps for file types
- **`.local/bin/appimage-open`**: opens AppImages (`.local/share/applications/appimage-open.desktop`): installs the app
  in `~/Applications` with a launcher entry, or replaces the old version, and starts it; so an app's own Update button
  updates it by itself
- **`.local/bin/appimage-update`**: updates those AppImages from their GitHub releases, checked against the release's
  checksums
- **`.local/bin/flatpak-bundle-update`**: updates Flatpaks installed from a downloaded `.flatpak` file (no Flatpak repo,
  e.g. ArtCraft Launcher) from their GitHub releases, checksum-verified; `--check` lists the ones with a newer version
  (both use `.local/share/github-release/lib.sh`: the release's x86_64 file and its checksum)
- **`.local/bin/capri-update`**: installs and updates Capri: my fork (`CrimzoAgra/capri-overlay`: CapriDesktop with
  her brain on Claude Code, on Hyprland, her intro and new text box) merged with the latest **release** (v* tag) of the
  original ([nunezValen/CapriDesktop](https://github.com/nunezValen/CapriDesktop)), not every commit to its main. Built
  in `~/.local/share/capri/<build>/` with her lockfile's packages (no install scripts but Electron's download), then
  `npm run build`, and switched to (`current`) only once it's built, Electron starts, her types check
  (`npm run typecheck`) and her tests pass (`npm run test`, my fork's); the build before is kept, and any she's still
  running from. Two kinds of conflict are settled by rule: a file my fork deleted stays deleted, and her lines
  (`src/shared/lines/*.json`) stay my fork's. A release my changes otherwise don't merge with, or that doesn't build or
  check, is said once (notification, `dotfiles-check`) and isn't tried again with that fork commit; she then gets my
  fork with the release she's on, else with the one it has merged in itself, so my own changes still come and a first
  install still has her; merge the release in the fork by hand (a download that failed is tried again). One run at a
  time (a `--check` meanwhile says nothing). The
  fork is private: with no GitHub login (`gh auth login`) its last copy is used, never a login prompt (`$CAPRI_FORK`
  fetches it from elsewhere for one run, e.g. a bundle of it). A release tag moved upstream is refused and said, not
  taken. Her folder from the old Capri (mochiiwuff/capri-desktop's fork) is cloned again and its build not kept. It runs
  from the Updates app (as AUR apps: the merged code is built and checked, not unseen at boot); `--check` is what the
  Updates app lists and what the boot runs.
  **`.local/bin/capri`** starts her build (Super menu entry and icon made by `capri-update`; log `~/.cache/capri.log`),
  through XWayland on Hyprland (her window lets the clicks around her through); `$CAPRI_RUN`, set in your session,
  names a start script run instead (a checkout of her code you work on). Started again while she runs, she comes back.
  At login she starts put away (`--hidden`: only her tray icon) when the Settings app's Startup page says so (on by
  default); once she's installed, Shift+Space (Settings, Keyboard; off while a game or a fullscreen window has the
  focus) puts her away or brings her back, through her local bridge (`POST 127.0.0.1:47823/toggle`). She sets her own
  window rules, by her windows' titles, and writes her windows' own (hidden) launcher entry for their icon
- **`.config/legion-control/`**: Legion Control's lighting choices, and the backup of Lenovo's original keyboard
  lighting profile (its "Default" mode puts that back)

## Updates and system

The `system/` scripts install things outside your home; run them with `sudo bash system/<script>` (setup's `system`
step asks for each).

- **Updates app** (`.config/quickshell/updates/`, in the Super menu; opened through `.local/bin/updates`):
  - Lists what's waiting, by app with its icon and old → new version: system and AUR apps, Flatpaks, AppImages
  - "Update all" runs `update-apps`, showing its progress; shown only while something is waiting. Closed with the
    title bar; an update already running carries on (its log: `$XDG_RUNTIME_DIR/update-apps.log`), and opening it
    again and pressing "Update all" follows it
- **`.local/bin/update-apps`**: updates everything (system and AUR apps, Flatpaks, AppImages), like at boot. `--list` is what the Updates app shows; every 6 hours (`update-check.timer`) it checks, and when
  updates are waiting a notification's "Update now" opens the Updates app and starts. VSCodium's own updater (which
  only opens the website) is off
- **`system/auto-update-setup.sh`**: updates everything at every boot: Flatpaks (system-wide and yours) and AppImages
  then (Capri's new release only looked for: `capri-update --check`), and the system, kernel and CachyOS gaming packages downloaded then and installed at shutdown, after a Snapper
  snapshot (installed under the running session, a new NVIDIA driver or kernel broke games and USB devices until a
  reboot). AUR apps and Capri aren't built at boot: they wait until you start an update (their build scripts can change under you). Run in a terminal, `update-apps` shows each AUR package's build-script changes for review first; the Updates app's "Update all" builds them without that review (it lists which ones first, in its log; it asks for your password in a
  dialog), which also rebuilds Quickshell after a Qt update. Log: `/var/log/auto-update.log`; `dotfiles-check` says an install at shutdown that failed or was held back (until one goes through), and 3 shutdowns in a row with nothing installed, with the last one's reason (the boot's download didn't finish: only a finished one is installed; something else using pacman still held its lock; a soft reboot, which keeps the kernel running). An install cut off has pacman's lists put back, and its lock removed, at the next boot or install. Its download stops after 2 h; the install has 30 min (shutdown's own limit is made 45 min for it); `paccache.timer` keeps pacman's cache from growing for good
- **`system/boot-menu.sh`**: hidden boot menu (GRUB or Limine): straight into CachyOS, Esc in the first second shows
  the menu (Windows and snapshots listed). No motherboard wait before the boot loader (`efibootmgr -t 0`; F11 still
  opens its boot menu)
- **`system/boot-video-mode.sh`**: no "no video" between the login screen and the desktop. Installs
  `system/boot-video-mode`, which at every boot gives the kernel console each connected screen's best mode as a
  `video=` boot option (Limine or GRUB), and only rebuilds the boot entries when the screens changed
- **`system/nvidia-early.sh`**: loads the NVIDIA driver from the start of the boot (in the initramfs, which CachyOS's
  `chwd` leaves it out of): about 2 s sooner, with the boot splash on it
- **`system/keyring-setup.sh`**: unlocks the passwords keyring with your login password (no keyring prompts from
  Proton VPN, Equibop...)
- **`system/bluetooth-setup.sh`**: Bluetooth on at boot (`AutoEnable=true`) and after sleep (`system/bluetooth-resume`,
  a systemd sleep hook: waking resets the adapter, which comes back off)
- **`system/pacman-hooks/`** (setup fills in your user and installs them in `/etc/pacman.d/hooks/`):
  `caelestia-overlay.hook.in` re-applies the overlay after every `caelestia-shell` update; `hyprbars-prebuild.hook.in`
  builds the title bar plugin for a new Hyprland (or a library its plugins hang on) straight away;
  `hypr-config-check.hook.in` checks the Hyprland config against a new Hyprland (`hypr-config-check`, its errors said
  by `dotfiles-check`). `system/boot-menu.sh` adds `grub-quiet.hook` (GRUB's loading messages hidden again after each
  GRUB update)
- **`.local/share/boot-tweaks/`**: boot and shutdown screens, and installs the login screen: faster Plymouth splash,
  boot/shutdown text hidden, "Shutting Down..." and "Restarting..." in the system language

## Laptop hardware

- **`.local/share/camera-switch/`**: makes the physical camera switch turn the webcam off/on (Legion webcam)
- **`.local/bin/camera-test`**: low-latency webcam preview

## Lua API (`dots`)

Functions other programs call through `hyprctl eval 'dots.<name>(...)'`, kept in one table (created in
`hypr-user.lua`) instead of loose globals:

| Function | Where it's defined | Called by |
|---|---|---|
| `focus_window(address, switcher)` | `user/windows.lua` | dock, switcher (which minimises a fullscreen window it leaves), game-focus |
| `task_manager()` | `user/keys.lua` | bar menu |
| `focus_app(entry, name, launch)` | `user/windows.lua` | notification clicks (overlay) |
| `minimise_window()`, `maximise_window()`, `refit_maximised()` | `user/windows.lua` | title bar buttons; a screen change |
| `toggle_window_mode()` | `user/windows.lua` | bar menu |
| `window_drag_start(address, kind)`, `titlebar_drag_start(address, phase)` | `user/windows.lua` | the hyprbars patch |
| `titlebar_height(win)` | `user/titlebars.lua` | `user/windows.lua` |
| `is_game(win)` | `user/apps.lua` | `user/windows.lua`, `user/titlebars.lua` |
| `started_for_game(pid)` | `user/apps.lua` | `user/apps.lua` (store launchers a game started open minimised) |
| `without_warps(fn)` | `user/windows.lua` | `user/workspaces.lua` (Super+N) |
| `setting(key)` | `hypr-user.lua` | everything the Settings app changes |
| `bind(name, action, opts)` | `hypr-user.lua` | my shortcuts (keys from the Settings app) |
| `peek_screen(screen, address...)`, `peek(address)`, `peek_end()` | `user/windows.lua` | window peek (overlay `WindowPeek.qml`): only those windows on that screen, the others faded out; all back |
| `goto_workspace(n)` | `user/workspaces.lua` | switcher, the bar's workspaces and workspace previews (overlay), game-focus |
| `screens_changed()` | `user/workspaces.lua` | itself, after the reload a screen change makes (windows back to a returning screen) |
| `monitor(rule)` | `user/monitors.lua` | host files |
| `lid(closed, output)` | `user/monitors.lua` | itself (at load: the lid switch reloads the config); `output` only to try it on a screen that isn't a laptop panel |
| `spotify_silent_set(on)`, `spotify_hide(address)`, `spotify_show()` | `user/apps.lua` | spotify-tray, tray-keeper, caelestia-restart |
| `minimise_launcher(address)`, `open_retry(address)` | `user/apps.lua`, `user/windows.lua` | themselves, a moment after a window opens (a sleep in its own process: a config reload would drop a timer) |

## Keeping it in sync

It pushes to the repo you cloned (`~/Projects/agros`, which is **public**): to keep your own copy, fork this repo
first and clone your fork. Your bookmarks and the new tab's picture are never exported into it; they're personal and
travel in your LibreWolf profile on the pen drive.

After changing settings, run `dotfiles-sync` (`-n` to see what changed first; `add <file>` to keep a new file). It
copies your current settings into the repo (`$DOTFILES_DIR`, default the folder setup ran from, else `~/Projects/dotfiles`; Legion Control into
`$LEGION_CONTROL_DIR`), commits and pushes. Only what it copied, or what matches your copy at home,
is committed: a file you're editing in the repo itself (newer than yours, said as skipped) and any other change there are
left out, set aside for the pull and put back after (one that clashes with what was pulled stays in `git stash`, and
the sync says it failed).

After pulling changes made elsewhere, copy them into your home first (`./setup.sh --only files desktop`), or the next
`dotfiles-sync` skips the files the repo has newer (and says so) until you do. After changing anything in `system/` or the login screen,
run its script again with sudo: those parts live outside your home, so `dotfiles-sync` doesn't carry them.

## Tests

`tests/run.sh` runs them all (`tests/run.sh lutris-overlay` just one), each in a throwaway home, so nothing of yours is
touched. Run it after changing a script, and after Caelestia, Lutris or Hyprland updates: they check that the
Caelestia and Lutris changes and the hyprbars patch still fit, besides the setup's file copy, the
bookmarks export, dotfiles-sync not undoing pulled changes, the settings file Lua reads, the login screen's theme,
lutris-covers' cover checks and the boot video mode.

## Troubleshooting

- **The login screen broke**: Ctrl+Alt+F2, log in, `sudo login-reset`
- **Something stopped working after a Hyprland or Caelestia update**: run `dotfiles-check`. It lists Hyprland config
  errors (the config checked from disk with `Hyprland --verify-config`, by `hypr-config-check`: the running Hyprland's
  own list is cleared by every `hyprctl eval`) and outdated settings, Caelestia changes that no longer fit (skipped by the overlay), and parts that aren't
  running (Caelestia, the switcher, the widgets, the title bar plugin, the services) or logged errors, and my QML in
  Caelestia that fails to load (a Caelestia update renamed something it uses, which the patches can't see). It also runs
  30 s after login and sends a notification only if something's wrong
- **Caelestia's Hyprland config has an update** (a low-urgency note from `dotfiles-check`, once per new version): run
  `caelestia-hypr-refresh`. It refreshes `~/.config/hypr` alone (files you haven't edited replaced, Caelestia's new
  version written beside the ones you have as `.new`) and checks the config. Not `caelestia update`: its own system
  update skips the Updates app's Qt rebuild, and a new Qt leaves the shell unable to start
- **No title bar highlight**: see `~/.cache/hyprbars-build.log`, or run `hyprbars-build`
- **A setup step failed**: run it again on its own, e.g. `./setup.sh --only apps`
