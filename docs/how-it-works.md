<p align="center">
  <img src="../.local/share/icons/hicolor/scalable/apps/agros-logo.svg" alt="AgrOS logo" width="160">
</p>

# How AgrOS works

AgrOS is a whole desktop installed in one go, on top of CachyOS. You get Hyprland (Lua config) with the
[Caelestia](https://github.com/caelestia-dots/shell) shell, patched with a dock and other changes, and a
Caelestia-style login screen. It comes with fixes for games, tray apps and the keyboard, every app below with its
settings, and Capri, the desktop companion. It's made for two machines: a Lenovo Legion Pro 7 (Gen 10) laptop and a
desktop (RTX 2060, external monitor). Things that depend on the hardware check for it, so the same install works on
both. The files are laid out like `$HOME`; `packages/` turns them into pacman packages.

**What's not in this repo:** your personal data, meaning logins, keys, your browser profile and bookmarks (they travel
encrypted on your pen drive, see below), and wallpapers: the default is Caelestia's own. The logo, three leaves drawn in one line width,
is `agros-logo` (#bec4ee, `.local/share/icons/hicolor/scalable/apps`), installed with the icons in `/usr/share/icons`,
so every install has it.

Laptop settings and lighting are in a separate repo: **legion-control-linux**.

## Install AgrOS

1. **Boot the AgrOS ISO** ([agros-iso](https://github.com/CrimzoAgra/agros-iso): CachyOS's installer, with AgrOS's
   package list) and install as usual. There's no desktop to pick: the installer installs `agros-desktop`, AgrOS's
   meta package, from the `[agros]` repo, alongside CachyOS's base. pacman puts in exactly the final set of packages
   in one go; nothing is installed only to be taken away again, and nothing is built during the install.
2. Reboot and log in. At your first login, `caelestia-start` builds Caelestia's overlay and sets its wallpaper and
   colours before the shell starts (`agros-welcome` does both if that failed, and moves the shell onto the overlay), and
   `agros-welcome` does the rest of what's per user: LibreWolf's settings, the Spotify, Nuvio and ArtCraft Flatpaks with Spicetify, VSCodium's extensions
   and Claude Code's plugins.
3. **The one thing you run:** its notification offers *Restore my accounts*. Plug in your pen drive and click it, or
   run `agros-personal`. It brings back your logins (Discord, Spotify, Nuvio, Proton VPN, Steam, Lutris's stores,
   Claude Code, GitHub), the login keyring and your LibreWolf profile (bookmarks, passwords, extensions). Capri
   installs right after that, since her fork is private and needs your GitHub login.

The same notification offers *Install hardware apps and VMware* (`agros-welcome --system`). It installs the apps for
the hardware that's plugged in: Boxflat (Moza), OpenRazer + Polychromatic (Razer), Solaar (Logitech),
OpenTabletDriver (tablets) and the Legion's camera switch. It also builds VMware Workstation from the AUR, because its
license forbids passing it on.

Before reinstalling, put this PC's accounts on the pen drive: `agros-personal --save` (encrypted with a passphrase
you pick; never in the repo).

Already on CachyOS (only CachyOS: `agros-desktop` needs packages from CachyOS's repos, such as
`cachyos-gaming-meta`, `paru` and `vscodium`; on Arch, add CachyOS's repos first): add the `[agros]` repo (below),
trust its key (`ci/agros.asc`: `pacman-key --add`, then `--lsign-key`), `sudo pacman -Syu agros-keyring
agros-desktop`, then make a new account (it gets AgrOS's settings from `/etc/skel`) or copy `/etc/skel` into your home.

### How it's packaged

The same structure as CachyOS, EndeavourOS or Garuda: a signed pacman repo of AgrOS's own packages, built by CI from
this repo (`ci/build-repo.sh`, `.github/workflows/ci.yml`) and published on GitHub Pages:

```ini
[agros]
SigLevel = Required DatabaseRequired
Server = https://crimzoagra.github.io/agros/$arch
Server = https://pub-f1a3a482900748e8b69cd81361ab96e1.r2.dev/repo/$arch
```

Its database is signed too, and required to be (`DatabaseRequired`: pacman's default takes an unsigned one, so a
server could list packages CI never put together). agros-iso's `pacman.conf` files have the line, and `agros-system`'s
install adds it under `[agros]` where it's missing (a machine installed before; a `SigLevel` of yours there stays),
its removal taking it out.

The second server is a mirror on Cloudflare R2 (the bucket agros-iso's ISO is downloaded from, under `repo/x86_64`), so
a GitHub Pages outage doesn't stop every machine's updates: pacman tries Pages first and the mirror only when Pages
fails. `.github/workflows/mirror.yml` fills it after each CI run on `main`, also one that failed after Pages was deployed (and by hand): `ci/mirror.sh`
downloads what Pages publishes (the database and `agros.files` with their `.tar.gz` copies, every package the database
lists, `agros-approved`, `agros-arch-ok`, each with its `.sig` where published), checks every signature against
`ci/agros.asc` alone (the database's required), then `rclone` uploads the packages first and the database last, and
only then removes what the repo no longer has: a mirror mid-update never lists a package it doesn't have. Only the
current set is kept (R2's free 10 GB; the repo is about 190 MB). It needs the same four secrets as agros-iso's ISO
upload, `R2_ACCOUNT_ID`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY` and `R2_BUCKET`; without them it says so (a
warning) and does nothing. agros-iso's `pacman.conf` files list the mirror, and `agros-system`'s install adds it after
`[agros]`'s other servers where it's missing (a `#Server =` line of yours for it counts: not added again), its removal
taking it out. `update-gate`'s approved list, the boot's copy of `agros-arch-ok` and agros-iso's gate try each of
`[agros]`'s servers in turn (Pages down: the mirror's).

| Package | What it is |
|---|---|
| `agros-desktop` | The meta package: every package the desktop is made of (Hyprland, Caelestia, the apps, PipeWire with its JACK, fonts, themes). Hardware apps are optional |
| `agros-hyprland-settings` | The settings every new account gets (`/etc/skel`): Caelestia's own configs (its dots, pinned), AgrOS's over them (everything in `.config`), launcher entries, LibreWolf settings, the wallpaper, and every version each of these has had (`/usr/share/agros/skel-versions`, from the repo's and Caelestia's git history); fonts and icons system-wide |
| `agros-scripts` | The programs in `.local/bin` and the data they use, in `/usr/lib/agros`, linked into each home (by links in `/etc/skel` for new accounts; `agros-links` adds new ones at every login, before the desktop starts, and copies in once each config file and launcher entry an update added to `/etc/skel`, and updates the settings you never edited) |
| `agros-system` | The update at every boot (downloaded and AUR apps built at boot, installed at shutdown with firmware), pacman hooks that rebuild each user's Caelestia overlay and hyprbars and check the Hyprland config, Bluetooth and the screens back on after sleep, the ananicy rule, the keyring, the night light's and time zone's permissions (geoclue, polkit), folder icons that follow the colour scheme (a sudoers rule for `papirus-folders` alone), mDNS from Avahi alone (resolved's off: the two clashed over the computer's name), UFW's logging off (once), the upstream gate (Hyprland's updates held until AgrOS's CI has checked them), the files never unpacked (NoExtract), AgrOS's name in `/etc/os-release`, a VMware VM's screen following its window (VMware's tools) |
| `agros-greeter` | The Caelestia-style login screen for greetd, its PAM service following the system's, `login-reset` |
| `agros-boot` | The hidden boot menu in AgrOS's GRUB theme (`grub-theme/`, its pictures and fonts made by `make.sh`), the faster splash with shutdown titles, no text at boot or shutdown (behind the splash), screens in their best mode from boot |
| `agros-hyprbars` | The title bar plugin, hyprbars, with AgrOS's patch, built in CI for the Hyprland there (in place of the AUR's plain one): the live USB's, and an installed system's until its account's own build is made |
| `agros-nvidia`, `agros-camera-switch` | NVIDIA driver loaded early; the Legion's camera switch |
| `agros-welcome` | The first-login step above |
| `agros-keyring` | The repo's signing key |
| `agros-vmware` | In a VMware VM, the desktop on its virtual graphics card: a shim that lets Hyprland and the login screen use its buffers (only there, only with `vmwgfx`; Hyprland gets it from a drop-in for its uwsm unit, `wayland-wm@hyprland.desktop.service.d`, so no app started through uwsm loads it) |
| `agros-thunar-usage` | A Thunar plugin: a bar beside the free space in its status bar, showing how full the folder's drive is (each window and tab its own drive; the theme's warning colour past 90%) |
| `agros-wine` | One Wine: CachyOS's (`wine-cachyos-opt`, in `/opt`) first on the PATH (`profile.d`, fish's `vendor_conf.d`, `environment.d`), standing in for Arch's `wine` that `winetricks` needs (provides it, no conflict: a machine that has Arch's keeps updating, with it unused; `agros-desktop` lists this before the gaming packages, so new installs never get Arch's, ~600 MB, nor its Mono and Gecko, ~430 MB). Wine fetches Mono or Gecko itself when a program needs them; a double-clicked `.exe` opens in Faugus Launcher (Proton) |

The AUR packages AgrOS uses (`aur/packages.txt`: Caelestia, equibop, Spicetify, darkly, ...) are built into
the same repo. Quickshell is built first, on its own, with AgrOS's fix
(`packages/agros-system/aur-patches/quickshell-git.patch`, added by `aur-agros-patch`, its pkgrel a `.<rel>` above the
AUR's, raised when what it adds changes; stripped, as Arch's own packages are). Without it, a window that closed while Quickshell was asking Hyprland for the window list came back from the
late answer and stayed listed for good (a game quit, its icon left in the dock). The boot's rebuild on a new Qt
(`auto-update-aur`) adds the same fix, and a patch that no longer applies fails the build rather than going out without
it. CachyOS's installer is built there too: `cachyos-calamares` rebuilt with AgrOS's changes (the live ISO installs
it from `[agros]`; among them, an EFI partition already on the disk checked against the minimum size, agros-iso's 64
MB, not the 512 MB a new one gets, so it installs beside Windows' 100 MB one): its version is CachyOS's with a `.N`
after the pkgrel (`calamares_rel` in `ci/build-repo.sh`), raised with any change to AgrOS's changes or to the pins
below, beside their new checksum (`calamares_sum`, over both), or CI fails. A build whose settings name a module it
wasn't built with (CMake leaves one out unsaid when its library is missing, and the installer stopped at that step) is
held, the published one kept. CachyOS's recipe for it is taken at a fixed commit of CachyOS-PKGBUILDS
(`calamares_pkgbuild`), and the installer's code at a fixed commit of its `cachyos` branch (`calamares_src`), not their
newest: their changes reach AgrOS's installer only once looked at, the pins moved on and `calamares_rel` raised; the
weekly status says when either has moved. (On 2026-11-17 CachyOS moved the recipe from `cachyos-dev`, as
`cachyos-calamares-next`, to `cachyos`; that branch's installer installs every package-list group, `platform:` or not,
so AgrOS's list lost its handheld kernel group first. Their own ISO builds `cachyos-staging`: `cachyos` plus their
newest work.) Most of AgrOS's own packages are versioned by the repo's commits (one built again from the same commit with
other contents fails CI: a build that isn't reproducible); `agros-vmware` and `agros-thunar-usage`, compiled, by the
commits that touch their own folder (`2.r<count>.<commit>`, `1.r<count>.<commit>`: the `2.` keeps `agros-vmware` above
the `1-1` published before, with no epoch, whose `:` would go in the file's name); `agros-boot` by the commits that
touch what it's made from (its folder, `system/boot-video-mode`, the login screen's `screenmode.py`: `1.r<count>.<commit>`,
the `1.` keeping it above the whole repo's `r<count>` it had before), as each new version makes every boot image again (it
ships a file mkinitcpio's pacman hook watches); `agros-hyprbars` by the Hyprland it's built for, then the commits that
touch it (`<hyprland version>.r<count>.<commit>`: a build for another Hyprland is a new version); `agros-desktop`,
`agros-welcome`, `agros-keyring`, `agros-nvidia` and `agros-wine` have a fixed `pkgver`, raised by
hand in their `PKGBUILD` with any change to them: CI fails when one changed under a version already published. A
version already published keeps the published file (a rebuild under the same name read as corrupted in pacman's
cache), except a compiled one built against other libraries, Qt or Python than it (`built_against`): that rebuild goes
out, so new installs and the ISO get one that runs. Quickshell, Caelestia and Calamares aren't even built when nothing
that would change that has (`reused` in `ci/published.sh`). To change AgrOS, change this repo: CI builds and publishes the packages, and pacman updates every
machine. Settings in `/etc/skel` reach new accounts. An account that has them already gets an update's new version
at its next login (`agros-links`) where its file is still one AgrOS shipped, byte for byte (one you never edited); one
you edited is kept, AgrOS's new version put beside it as `<file>.agros-new` (as pacman's `.pacnew`), and a
notification says so once. The settings that are yours to change, mostly through the apps that write them, are never
updated, only copied in when missing: Caelestia's `shell.json` (its settings, the weather location), the dock's pins,
`mimeapps.list`, `~/.config/autostart` (Settings > Startup), VSCodium's, Legion Control's, and `user/hosts/` (one machine's
screens). A file `package()` changes at build time only has its current version listed (Caelestia's `execs.lua` has
every version, with the same change made).

The CI needs two repository secrets: `AGROS_GPG_KEY`, AgrOS's key without a passphrase (today the key itself, kept
only there: no other copy, and no revocation certificate; the same secret in both repos. A signing subkey works too,
with nothing to change: agros-iso's manual, *Building the ISO*, step 7, makes one);
and `AGROS_ISO_TOKEN`, a fine-grained token for `agros-iso` only with **Actions: Read and write**, which starts
agros-iso's ISO build after each publish (the `iso` job fails without it). It also needs GitHub Pages turned on with
"GitHub Actions" as its source. An optional repository variable, `AGROS_PUBLISHED`, points the build at another
published repo to compare with (default `https://crimzoagra.github.io/agros/x86_64`).

### The apps

With the Windows ones they replace in brackets:

- CachyOS gaming packages: Proton, Wine, Steam, Lutris, MangoHud, Gamescope, GOverlay, Faugus
- Equibop (Discord, themed with your colours)
- Spotify (Flatpak, for your user) with Spicetify (Caelestia's theme in your colours, marketplace)
- LibreWolf; Nuvio and ArtCraft Launcher (Flatpaks from their GitHub releases)
- Proton VPN
- With the device plugged in (`agros-welcome --system`): Boxflat (Moza Pit House), OpenRazer + Polychromatic (Razer
  Synapse), Solaar (Logitech G Hub, Logi Options+), OpenTabletDriver (tablet app)
- File Roller + 7-Zip (WinRAR, 7-Zip; Extract/Compress in Thunar's right-click menu)
- VSCodium, VS Code's open-source build (with your extensions), LibreOffice (Microsoft Office), qBittorrent, AntiMicroX (JoyToKey)
- Text Editor (Notepad), qView (Photos), mpv (Media Player)
- VMware Workstation (`agros-welcome --system`: the AUR package, its installer from a copy on archive.org, as Broadcom
  gives it only to signed-in users; checked against the package's checksum)
- HP Deskjet 1050 J410: HP's Linux driver (HPLIP), printing and scanning; add the printer in Print Settings once it's
  plugged in, scan with Document Scanner
- balenaEtcher (Rufus), and Phone Link: scrcpy, your Android phone's screen on the computer (USB debugging on, phone
  plugged in; its screen off while mirrored, kept awake, 20 Mbit/s)
- Capri, the Edgerunners 2 desktop companion: [my fork](https://github.com/CrimzoAgra/capri-overlay) (private) of
  [CapriDesktop](https://github.com/nunezValen/CapriDesktop), her chat on your Claude Code (see [Apps](#apps))
- WhatsApp, Outlook, Teams and OneDrive: use the web versions

### Your accounts

`agros-personal` covers LibreWolf's Firefox account, bookmarks, passwords, cookies and extensions; Discord (Equibop),
Spotify, Nuvio, Proton VPN (and the login keyring they keep their keys in); Lutris's store logins and the store
launchers installed in it (each one's Wine folder, so they come back installed and signed in); Steam's login and
settings; VSCodium's extensions' own data; Claude Code's account, settings, skills and memories; GitHub's login;
SteamGridDB's key (`lutris-covers`); and the weather widget's place.
`agros-personal --save` puts them, apps closed, in `dotfiles-personal.tar.gpg` on your pen drive (the removable drive
plugged in, mounted if it isn't, or the folder you name after it), encrypted with a passphrase you pick (gpg, AES-256):
a lost drive gives nothing without it. `agros-personal` decrypts it straight into place (nothing unencrypted written
anywhere else) and backs up what it replaces; the keyring opens with your old login password. It's never in the repo:
saved logins get past your password and 2FA, and git keeps every version. With no drive, it opens each app for you to
sign in instead (LibreWolf's Firefox account brings bookmarks and passwords through Sync) and asks the weather
widget's place. Save again now and then: logins expire.

Other screens get their own resolution at its fastest refresh rate; a machine's own screens go in
`.config/caelestia/user/hosts/<hostname>.lua` (see [Screens and colours](#screens-and-colours)).

## Credits and licenses

AgrOS is GPL-3.0-or-later (`LICENSE`). It builds on [Caelestia](https://github.com/caelestia-dots) (GPL-3.0): its dots
are installed as they are, and the overlay in `.local/share/caelestia-overlay` changes its shell. It also builds on
[hyprland-plugins](https://github.com/hyprwm/hyprland-plugins)' hyprbars (BSD-3-Clause), patched by
`.local/share/hyprbars/hyprbars.patch`, and [Lutris](https://github.com/lutris/lutris) (GPL-3.0), changed by
`.local/share/lutris-overlay`. The Bangers font is under the SIL Open Font License 1.1 (`.local/share/fonts/OFL.txt`).
The default wallpaper is Caelestia's own (`assets/wallpaper.webp` in its shell).

## Layout

| Path | What's there |
|---|---|
| `packages/` | The PKGBUILDs of AgrOS's packages (and their system files: units, hooks, the boot update) |
| `aur/packages.txt`, `ci/` | The AUR packages built into `[agros]`, and the script that builds the repo |
| `system/` | Files the system packages install (Bluetooth after sleep, the screens on after sleep, the boot video mode, the ananicy rule, the night light's location (geoclue), the time zone's permission (polkit), resolved's settings, the `papirus-folders` sudoers rule) |
| `.config/caelestia/` | Hyprland settings (`hypr-user.lua`, `hypr-vars.lua`, `user/`) and Caelestia settings (`shell.json`) |
| `.config/quickshell/` | The switcher, desktop widgets, Updates and Desktop Settings apps, their shared colours (`common/`), and the dock's pins |
| `.local/share/caelestia-overlay/` | My changes to Caelestia's own code, patched in by `caelestia-overlay` |
| `.local/share/caelestia-greeter/` | The login screen |
| `.local/bin/` | Scripts (on user services' `PATH` through `.config/environment.d/10-local-bin.conf`, on the desktop's through `.config/uwsm/env.d/local-bin.sh`) |
| `.config/environment.d/` | `~/.local/bin` on user services' PATH; compiled game shaders kept for good (`shader-cache.conf`: the NVIDIA driver trims its cache otherwise) |
| `.config/uwsm/env.d/` | `~/.local/bin` on the desktop's PATH (uwsm replaces environment.d's PATH with the login's); Qt's harmless Wayland text-input warnings silenced; `nvidia-vaapi.sh`: hardware video decoding in LibreWolf on the NVIDIA card, only when that card drives a screen; as its trade-off it sets `MOZ_DISABLE_RDD_SANDBOX=1`, so web video is decoded outside LibreWolf's RDD sandbox (the sandbox blocks the NVIDIA driver) |
| `.config/systemd/user/` | User services: game-focus, tray-keeper, the update check, lutris-library, and `service-failed@` (a notification when game-focus or tray-keeper keeps crashing) |
| `.local/share/applications/` | Launcher entries (and fixed copies of a package's own, e.g. HP Scan's with an icon that exists) |

## Desktop Settings app

A window in Caelestia's style for changing the whole desktop without editing files (Super menu: "Desktop Settings").
Changes apply right away.
- **`.config/quickshell/settings/`**: the app (`desktop-settings [page]` opens it, on a page if given). It draws
  every page from the schema: one control per kind of setting (a switch, joined buttons or a list for a choice,
  shortcuts, a slider and -/+ for a number, a text field, a JSON field, pictures), a button back to the default on any
  that's changed, a note where AgrOS relies on the value, and a search over every page above the list of pages
- **`.local/share/dots-settings/schema.json`**: every setting, its kind, default, and how a change applies (reload
  Hyprland...). A new setting is added here, then read where it's used; a new kind of setting is added to `dots-settings`
  and the app once, for every page
- **`.local/bin/dots-settings`**: saves your choices (only those that differ from the default) to
  `~/.config/dots/settings.json`, for this machine only, and writes them to `settings.lua` for Hyprland, where
  `dots.setting(key)` reads them; scripts use `dots-settings get KEY` or `values`. Where a setting lives elsewhere it
  says so in the schema, and `dots-settings` reads and writes it there:
  - `caelestia-shell.<option>` / `caelestia-tokens.<option>`: one of Caelestia's own options, in its `shell.json` /
    `shell-tokens.json`, written through `json-edit`. Caelestia watches those files, so the change shows at once (no
    restart). The schema only gives these a label and a description: their kind, choices and default come from the
    Caelestia installed (`.local/share/dots-settings/caelestia-options.qml`, run offscreen by Qt's `qml` tool, asks
    Caelestia's config plugin for each option's type and default; its choices' names come from the plugin's
    `caelestia-config.qmltypes`). The list is kept in `~/.cache/dots-settings` until Caelestia (or that reader) changes
    (a read that failed isn't kept: tried again), so a new option in an update shows up by itself, and one an update
    removes drops out of the page that named it. Back to the
    default is AgrOS's own value where `/etc/skel/.config/caelestia/shell.json` has one, else the option is left out of
    your file (so Caelestia's default, and an update's new one, apply). A few options AgrOS relies on carry a note
    (`caelestia-managed` in the schema), the Super menu's pins can only be changed from the Super menu
  - `caelestia-vars.<variable>`: one of Caelestia's Hyprland variables (gaps, border, rounding, blur, touchpad), set
    through `hypr-vars.lua` like its shortcuts, only once changed
  - `screens.<description>.<mode|scale|position|enabled>` and `screens.main`: read by `user/monitors.lua` (below)
  - a `get` / `set` shell command (the window mode, the wallpaper and colour scheme through the `caelestia` command,
    the keyboard layout through `localectl`); `options_cmd` lists a choice's options from a command (fonts, schemes,
    wallpapers, the screens)
- Pages:
  - **Windows**: floating or tiling, focus on click or hover, cascading, title bars
  - **Mouse and keyboard**: mouse DPI (the mouse's own, through Solaar: `.local/bin/mouse-dpi`, also at login; Solaar
    in the tray puts it back on reconnect), acceleration, pointer speed, natural scrolling, the touchpad (tap to click,
    off while typing, scrolling speed), key repeat (`hypr-user.lua` sets them), and the keyboard layout, variant and options:
    the system's, as the installer set it, through `localectl` (it asks for the password; the login screen and Scroll
    Lock's keymap follow it, from the Hyprland reload)
  - **Screens**: each connected screen (Hyprland's list) by its full description: on or off, resolution and refresh
    rate, scale, position, and the main screen. Empty is AgrOS's own choice (the host file's rule, the fastest rate)
  - **Look**: the wallpaper (pictures in `~/Pictures/Wallpapers`, `caelestia wallpaper -f`), the colour scheme, light
    or dark and its style (`caelestia scheme set`), the shell's fonts and text size, window gaps, border, rounded
    corners, blur and shadows (Caelestia's Hyprland variables), the shell's transparency, rounding and screen frame
  - **Bar**, **Panels** (dashboard, sidebar, quick settings, the volume pop-up, desktop clock and visualiser),
    **Launcher**, **Notifications** (and toasts), **Lock and session** (lock screen, idle, the session menu), **Region
    and services** (weather place and units, clock, data units, media player, volume step): the Caelestia options most
    often changed, with plain labels
  - **Features**: low input lag in games (tearing allowed for games only; while one is open the pointer is drawn into the picture,
    as Hyprland allows no tearing with the graphics card's cursor layer showing one: `user/apps.lua`), each of game-focus's four
    behaviours, store launchers starting minimised, each Lutris change, and
    each change to Caelestia (listed from `caelestia-overlay`'s and the Lutris overlay's `patch.py --list`, so new ones
    show up by themselves). A Caelestia change turned off is left out of the rebuild (`Off:`, not a warning)
  - **Startup**: the apps `user/apps.lua` can start at login (Lutris, Proton VPN and Capri on by default;
    Solaar and ArtCraft off), and every app with a standard
    autostart entry (`/etc/xdg/autostart`, `~/.config/autostart`); turning one of those off writes your copy of it
    with `Hidden=true`, as GNOME's startup settings do
  - **Shortcuts**: my shortcuts (`dots.bind` in `user/keys.lua`, `user/windows.lua` and `user/apps.lua`; defaults in the
    schema), Caelestia's (its `kb*` variables, by its sections, minus the ones `hypr-vars.lua` turns off; your changes go
    back through `hypr-vars.lua`), and the fixed ones neither can change (Caelestia's arrows, media keys...: Hyprland's
    list of binds, `hyprctl binds`), shown so a clash with them shows too. + records a new one: Hyprland switches to an
    empty submap (`dots-capture`) meanwhile so every key reaches the app, and Esc always leaves it. A shortcut used twice
    shows in red. A new shortcut of mine is a `dots.bind` with its default in the schema: no other code
  - **All Caelestia options**: every option of the Caelestia installed (about 420), by area (closed until opened),
    named from the option's own name, each with the control its type needs (a JSON field for lists)

## Desktop and Caelestia

Caelestia's own Hyprland config (`caelestia install` puts it in `~/.config/hypr`) is never edited, as Caelestia's
README asks: everything goes in the files Caelestia leaves for you, so its updates apply cleanly.

- **`.config/caelestia/hypr-user.lua`**: my Hyprland settings, loaded after Caelestia's own: keyboard layout, no mouse
  acceleration (unless turned on in the Settings app), the Settings app's pointer speed, scrolling, tap to click and
  key repeat, the `dots` table ([Lua API](#lua-api-dots)), and the modules in `user/`
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
  - Super+W opens LibreWolf (Caelestia's is Firefox, which AgrOS leaves out); the Bibata pointer (Caelestia's
    sweet-cursors isn't installed)
  - In a VMware VM without `agros-vmware`'s shim, the apps drawn on the CPU (the virtual GPU refuses their buffers)
  - Then the Settings app's changes: shortcuts (`caelestia-keys.*`) and the other variables (`caelestia-vars.*`: gaps,
    border, rounding, blur, the touchpad)
- **`.config/caelestia/shell.json`**: Caelestia settings (AgrOS's; each account's copy changes from the Settings app,
  which puts AgrOS's value back as the default)
- **`.local/share/caelestia-overlay/`**: my changes to Caelestia, patched in by `patch.py`. A change whose code no
  longer fits a new Caelestia version is skipped, not broken; one that still fits but whose QML no longer loads (a
  renamed Caelestia component) is reported by `dotfiles-check`
  - Bar:
    - A dock (`Dock.qml`, `DockMenu.qml`): pinned apps and open windows, Force quit; minimised windows dimmed; a
      click on a window or its preview brings it to the front. Turned off, its place is kept (the workspaces, tray and
      clock stay put)
    - A window's icon found by one lookup for the bar, the dock and Alt+Tab (`.config/quickshell/common/WindowApps.qml`:
      Quickshell's, else `.local/bin/app-for-window`: the class's last part, a Flatpak's id, the window's program)
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
      and on keymap changes (no Caps Lock shown on at boot; Caelestia's own fix, PR #1899, only covers remapped Caps
      keys, so this stays)
    - The logo does nothing (no click)
  - Super menu (launcher):
    - Pin buttons; favourites at the top, then everything A-Z
    - A "check for updates" button next to the search bar: its icon spins while checking, then a notification says
      the result (also if the menu was closed meanwhile) and opens the Updates app
    - Opens over fullscreen games and videos too (`general.showOverFullscreen` in `shell.json`; notifications and
      toasts stay off fullscreen windows)
  - Panels that open on hover (dashboard, Super menu, sidebar, volume, utilities) open only from the screen's last 3
    pixels (not the last alone: Caelestia's dots' `cursor:hotspot_padding` keeps the pointer a pixel short of every
    edge), not the border's whole width, and not while a mouse button is held or a window is dragged; once open, one
    stays while the pointer is over it (`edge_triggers`)
  - Notifications:
    - The sidebar slides down from the top when you hover the top edge above it, with notifications only (no
      divider, ending above the bottom-right panel); Super+K opens it too, merged with the bottom-right panel
      (a Caelestia with its own shortcut mode for the sidebar, as main has, keeps it: its choice of which opening counts
      as by the key is replaced, as its own counts the top edge's, and as on v2.5.0 the pointer on the sidebar puts it
      back under hover control and the launcher closing closes it unless hovered)
      It closes without bouncing back, and hovering the edge doesn't open it while a notification pop-up is on screen
      (nor afterwards for a pointer that stayed there: move away and back)
    - One neutral colour whatever their urgency
    - A click (pop-up or in the sidebar) runs the notification's action, like its button, and brings the app that
      sent it to the front
  - Lock screen: like the login screen (blurred, dimmed wallpaper, a text cursor, its elements coming down onto the
    screen from in front of it, out of focus and sharpening, from the centre outward); a wrong password said at once
    (its own PAM config, `assets/pam.d/passwd`, with nodelay on pam_unix and pam_faillock; pam_faillock still counts
    and locks out); sleep, restart and power off buttons, bottom right like the login screen's
  - Settings (Caelestia's, Nexus) > Language & region: the weather location picker (the desktop widget's, one
    setting for both) and the system clock: time, NTP, date and time by hand, time zone (`timedatectl`, through polkit;
    `nexus-weather-block.qml`, `nexus-time-block.qml`)
  - Other: brightness only on built-in screens; the dashboard's calendar and weather in the system language
    (`LANG`; Caelestia's own locale dates, PR #2213, follow `LC_TIME` for a language it has no translation for, so this
    stays); no volume
    pop-up when the shell starts or the sound device changes; a critical battery suspends instead of hibernating, and
    so does the session menu's Hibernate (unless `shell.json`'s `session.commands.hibernate` sets another command): there's no swap to hibernate
    into (zram only); no warnings about a missing account picture (`~/.face`)
- **`.local/bin/caelestia-overlay`**: builds `~/.config/quickshell/caelestia` (Caelestia + the patches); also run by the
  pacman hook after every `caelestia-shell` or `agros-scripts` update. Nothing it's built from changed since the last
  build (Caelestia's files, the script, the patches, the Settings app's `caelestia.*` switches: one checksum, kept in
  the folder's `.agros-built`): left as it is, the shell not restarted. With a Caelestia running from the overlay (an update from the
  Updates app, inside the session) it hands over to `caelestia-restart --rebuild`, which stops the shell, rebuilds and
  starts it again: swapped under a running shell, the folder got it dropped by Hyprland. It checks under the overlay's
  lock (`~/.config/quickshell/caelestia.lock`), which `caelestia-restart` and `caelestia-start` hold from the shell's
  stop to its new start, so a rebuild waiting on one finds the shell up and hands over too. A game open: the restart
  waits until it closes (`after-games`, in the background); a session that ends first loses it, and the next login's
  `caelestia-start` makes it. Skipped patches go to `~/.local/state/caelestia-overlay-skipped` (reported by
  `dotfiles-check`)
- **`.local/bin/caelestia-start`**: starts Caelestia at login (Caelestia's `execs.lua` runs it, so set by
  `agros-hyprland-settings`), running `caelestia-overlay` first (at every login: it rebuilds only what's out of date,
  so one an update left waiting for a game is made then); each start logged in
  `~/.local/state/agros/caelestia-start.log`. A shell that comes up but never loads its config (it doesn't answer `qs
  ipc show` within 30 s: Quickshell stays running with nothing on screen when a part can't be created, AgrOS's changes
  on a Caelestia or Quickshell other than the one CI checked, a type renamed), on the overlay's changes, is started
  again without them (`caelestia-restart --without-changes`, below), not left with no bar, notifications or lock screen
- **`.local/bin/caelestia-restart`**: restarts Caelestia with a clean environment (also Ctrl+Super+Alt+R), keeping
  Spotify hidden. `--rebuild` (the Settings app's Caelestia changes) rebuilds the overlay while the shell is stopped:
  rebuilt under the running shell, Hyprland dropped it. Exit 3 when that build failed (the shell started again on what
  was there); the changes it skipped are said once the new shell is up (Caelestia is the notification server: said
  during the build, they went to nobody). Each start waits for the shell's config to load (it answers `qs ipc show`,
  30 s at most): one that never does, on the overlay's changes, is stopped and started again on Caelestia as it comes
  (`caelestia-overlay --without-changes <why>`: links only, why written down for `dotfiles-check` and said once the
  shell is up, not marked built, so the next login or update tries the changes again), exit 3; `--without-changes`
  does that at once (`caelestia-start`'s). A shell that won't close in 5 s is killed outright. With a game open, any
  restart (the Settings app's, a rebuild handed over, the shortcut) waits until it closes (`after-games`, in the
  background), and a notification says so. Run outside the desktop (SSH, a text console) or without the desktop's
  environment (no `XDG_CURRENT_DESKTOP`: the shell would start with no Qt theme), it has Hyprland run it instead, once
- **`.local/bin/caelestia-pin`**: pin apps to the launcher or dock from a picker
- **Night light** (`.config/gammastep/config.ini`): gammastep, which Caelestia's `execs.lua` starts at login with
  geoclue's demo agent (both in `agros-desktop`), turns the screens warmer after sunset (6500 K by day, 4000 K at
  night, faded in). Its location comes from geoclue (Arch's: Wi-Fi networks and then the IP, looked up on BeaconDB, its
  default since Mozilla's service closed; nothing to set). `agros-system`'s `/etc/geoclue/conf.d/90-agros.conf` lets
  gammastep have it without the agent asking at every login. Without a location (offline, nothing found) gammastep
  waits, untinted, and isn't restarted; there's no fallback on purpose (the weather location is often a town far away
  or empty): to set it by hand, `location-provider=manual` and a `[manual]` section with `lat=` and `lon=`
- **`.local/bin/timezone-auto`**: Settings > Language & region > "Set the time zone automatically" (Caelestia's
  Settings app, `nexus-time-block.qml`; on while `~/.local/state/agros/timezone-auto` is there; off by default). Its
  zone comes from Caelestia's weather location: `lat,lon` through Open-Meteo's forecast (`timezone=auto`), a town
  through Open-Meteo's geocoding, empty (automatic) by IP through ip-api.com, as Caelestia's weather finds you. Not
  geoclue: it says only coordinates, and the weather location is what you picked. Run at login (`user/desktop.lua`),
  when turned on, and when the page sees the weather location change; set with `timedatectl` only when it differs.
  `agros-system`'s polkit rule (`/usr/share/polkit-1/rules.d/50-agros-timezone.rules`) lets an admin (wheel) at the
  machine change the time zone without the password, so the one at login never asks; for anyone else it's left as it
  is (`--no-ask-password`). No network or no answer: nothing changes. While it's on, the Time zone field only shows it
- **`.config/quickshell/widgets/`**: desktop widgets, designed around AgrOS's old Spider-Verse wallpaper and kept as they
  are on Caelestia's (the default now)
  - Comic panels with halftone dots and the film's red/cyan misprint glitch, laid out where the sky was around the
    falling Miles
  - A clock, weather with a 3-day forecast, a calendar, "Sixth sense" CPU/RAM/GPU/SSD meters (they shake when the
    PC runs hot), and a now-playing card with controls
  - Weather follows Caelestia's `services.weatherLocation` in `shell.json` (a city, or `lat,lon`; empty finds you by
    IP, as on a fresh install). The pencil by the weather panel's tab (with the mouse over it) types it there, as does
    Settings > Language & region (one picker for both, `.config/quickshell/common/PlacePicker.qml`); it's
    this machine's own, so an update keeps yours and `dotfiles-sync` doesn't copy it into the repo; media shows the same player as Caelestia's dashboard
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
  - Picks each screen's best mode (`best-mode`, with the rule in `screenmode.py`'s `best()` it shares with
    `system/boot-video-mode`)
  - Once the wallpaper shows, its elements come down onto the screen from in front of it (bigger and out of focus,
    shrinking and sharpening into place): the password bar first, then the rest from the centre outward
  - The wallpaper and colours are copied to it at every login (`greeter-theme-sync`)
  - It shows the last account that logged in (before anyone has, as on a new install: the first account, from
    `agros-greeter`'s `run`, as its install, which runs before the installer makes the account, couldn't name one);
    with more than one account (uid 1000 and up, a login shell), the person
    pill by the session's opens a list of them (the wallpaper and colours stay the last one's). The session pill opens
    the sessions' list the same way: above the pill, the current one ticked, picked with a click or the arrow keys and
    Enter, closed by Esc or a click elsewhere
  - A wrong password said at once: its PAM service, `/etc/pam.d/greetd`, is made by `greetd-pam` from `greetd.pam` and
    the system's own stack as it is (its auth lines, with nodelay on pam_unix and pam_faillock, which still counts and locks
    out; the passwords keyring unlocked at login, from the template's lines, not for the login screen's own `greeter`
    account), and made again after each `pambase` or `pam` update (a pacman hook), so it follows the system's changes.
    A stack it can't follow leaves the file as it was, said (never one that can't log in; on a first install, greetd's
    own, so the keyring isn't unlocked at login and apps ask for its password). sudo and the text consoles keep theirs
- **`.config/spicetify/Themes/caelestia/user.css`**: Caelestia's Spotify theme (from its dots)
  with thin scrollbars; its colours (`color.ini`) are written by Caelestia
- **`.config/hypr/xdph.conf`**: screen sharing without asking each time

## Windows and keys

- **Workspaces** (`user/workspaces.lua`): synced across screens. Each screen has its own 10 workspaces, in screen
  order (the 1st screen 1-10, the 2nd 11-20...), and every screen always shows the same one of its 10 (a column):
  - Super+N shows N on all of them at once; anything else that changes a screen's workspace (the touchpad's swipe, a
    window moved and followed, the bar, a script) brings the others to the same column a moment later
  - Next/previous (Super+scroll, Ctrl+Super+Left/Right, Super+PageUp/PageDown) stay within the focused screen's 10 and
    stop at its 1st and 10th (no wrap: a scroll a notch too far doesn't fling you from the 10th back to the 1st); the
    swipe past the last one stays there too
  - Moving a window to N (Super+Alt+N, Super+Shift+N without following it, Super+Alt+PageUp/PageDown) puts it on the same
    screen's N; Ctrl+Super+N and Ctrl+Super+scroll go to screen N, or the next/previous screen, same column, and
    Ctrl+Super+Alt+N moves the window there
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
  - Super+Tab: live previews of the workspaces with windows, the current one first, then the last used first (as
    Alt+Tab orders windows), Tab cycling on from the current one
  - Alt+Tab: the current workspace's windows, most recently used first (minimised ones too), each preview in its
    window's shape
  - A × on the selected preview and the one under the mouse: Alt+Tab's closes that window (Hyprland's close, as its
    close key), Super+Tab's moves that workspace's windows, silently, to the nearest other workspace with windows, the
    previous one on a tie (`dots.clean_workspace`); none where there's nothing to move or nowhere to move it. The
    switcher stays open
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
  - Snapping, as on Windows (floating mode; not games or fullscreen windows; needs the title bar plugin's hook): let
    go with the pointer at a screen's top edge, a window is maximised; at its left or right edge, that half; in a corner
    (the last sixth of an edge), that quarter; on the screen the pointer is on. The edges are inside Caelestia's border
    and bar, where the pointer is held while a window is moved; a side with another screen beyond isn't one (the
    pointer goes on across). A move takes effect after 5 px: a click on a maximised or snapped window's title bar (an
    app's own too, or Super+click) leaves it as it is. A see-through
    preview (the overlay's `SnapPreview.qml`) shows the zone and follows the pointer between zones. Dragged away, a
    snapped window gets back the size it had; maximised or floated by the switch, it's no longer snapped. Snapped
    windows next to each other (side by side or one above the other) share their seam: a two-way resize cursor over
    the gap (not while a special workspace is open over them), where a press resizes that one edge (the plugin takes the press: not the app's, nor a title bar button's); resizing one
    moves every edge on that seam's line (the whole line with four quarters) in the same frame, stopping at either
    app's smallest size. Snapping, its seams and maximise follow Hyprland's gaps and border as they are now (Caelestia's
    Game mode sets them while it runs), as the plugin's seams do
  - Always within reach: after a move and after a screen change, a floating window's title bar is all below the top
    border and at least 150 px of it inside the other borders (not on a side with another screen beyond). A screen's
    size change (a VM window resized) re-fits windows once, from Hyprland's event: maximised ones fill it again, snapped
    ones their zone, with seams that were dragged kept in proportion; a window minimised meanwhile is fitted the same
    way as it comes back (`refit_window`). Maximised and snapped ones (no others) are fitted again a second after
    whatever can change their box settles: the gaps or border (Game mode on or off, the Settings app), title bars on or
    off, the space Caelestia's bar reserves (back after a shell restart); Hyprland's `config.props_refreshed`,
    `layer.opened` and `layer.closed`, which come for much else too, so each only if its box changed. Each seam is kept
    where it was, the new gap across it; edges rounded to the nearest pixel, so on-and-off doesn't creep. X11 menus and
    tooltips are never moved into reach: their apps place them. A pop-up keeps its own size: one wider or taller
    than the screen opens shrunk to fit, in the middle, and one opening off it is brought within reach (not X11 menus
    and tooltips, which their apps place)
  - The window clicked, or picked in the dock or Alt+Tab, comes to the front; in floating mode the pointer stays
    where it is, and focus changes on a click, not on hover
  - Clicking a notification brings the app that sent it to the front (or opens it)
- **Title bars** (`user/titlebars.lua`), on floating windows only:
  - Minimise, maximise (a restore icon when maximised) and close, styled like Caelestia, with a hover highlight:
    40 px wide and the bar's full height, side by side at the right edge, no background until hovered
    (a rounded rectangle inside the button: faint white for minimise and maximise, the power button's red for close)
  - The only window buttons there are: GTK apps (LibreWolf included, and any installed later) draw none (the GTK button
    layout, set by `agros-welcome`), VSCodium's are hidden (`window.controlsStyle`); Steam, which can't turn its own off,
    gets no bar
  - None on fullscreen windows or games (the `game` tag: Proton's `steam_app_<id>`, Lutris's, gamescope's and native
    Steam games; often borderless over the whole screen), X11 menus and pop-ups (Caelestia's `xwl_popup` tag, Wine's
    included), nor apps with their own buttons (Steam, Proton VPN)
  - The hyprbars plugin with my patch (`.local/share/hyprbars/hyprbars.patch`: hover highlight, restore icon,
    un-maximise on drag, square buttons; it also hooks Hyprland's drag start, for any window, bar or not: a drag of a
    maximised window by the app's own title bar or edges, and edge resizes moving one edge only; and every drag for
    the snapping: each one's start, after 5 px for a move, the new size then taken up by the drag (`updateDragWindow`),
    each step and its end told to `user/windows.lua`, the pointer held inside the screen's free part while moving, the
    seam cursor and press between snapped windows, and `hl.plugin.hyprbars.min_size` for Lua), built by
    `hyprbars-build` for the running Hyprland into `~/.local/lib/hyprbars/`. It runs
    as Hyprland starts (`--login`): after a Hyprland update or a patch change it rebuilds in the background, with the
    packaged build meanwhile (`agros-hyprbars`: the same patch, built by `hyprbars-build` in CI for the Hyprland
    there, in place of the AUR's plain one; loaded only when built for the running Hyprland, its commit in it: on any
    other, a point release too, the plugin's own check refuses it with a red "Version mismatch" error on screen), and a
    notification if the build fails. On the live USB (no compiler)
    that packaged build is loaded as it is
- **Keys** (`user/keys.lua`):
  - Ctrl+Shift+Esc opens btop (Task Manager; the open one if there is); Print selects an area to screenshot
  - Ctrl+Super+Alt+R restarts the shell
  - Scroll Lock as a real lock with its keyboard light, like Caps and Num Lock (`.local/bin/scroll-lock`: builds your
    layout's keymap with Scroll Lock on a free modifier, which Hyprland loads, and keeps the bar's icon in step with
    the light)
  - Caps/Num Lock badges follow whichever keyboard was used last
  - A VMware Workstation window focused: every key reaches the VM, Super shortcuts too (Hyprland's `vm` submap, with no
    other binds), until another window has the focus or Ctrl+Alt+Esc

## Screens and colours

- **`user/monitors.lua`**: the shared rules and a
  fallback for any other screen (to the right of the others); **`user/hosts/<hostname>.lua`**: one machine's own screens, loaded on that machine only
  (`LegionCachy.lua`: the laptop's OLED and a Samsung LF27T450F; `TerraCachy.lua`: the desktop's Samsung C24F390 at
  its fastest mode). Copy it under your machine's hostname to fix a
  screen's mode or position by hand. The Settings app's Screens page goes over both (`screens.*` settings, by the
  screen's full description, serial included: two of one model each keep theirs): what's set there is applied on top
  of the rule that applied to that screen, so a field left empty keeps it. The main screen goes to 0x0 (the first
  screen: workspaces 1-10, and the windows of a screen unplugged) and the others to its right unless given a position
  (there, or by the host file); the last screen on can't be turned off (all set off: the main one stays on, else the
  laptop's panel, else the first by name). A mode the screen no longer has is left out (the rule it had applies). A screen's settings stay while it's unplugged. Applied by a Hyprland reload
  (`hypr-reload`, after any game)

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
- **`.local/bin/lutris-library`**: Lutris's Games view lists every game you own on Steam, EA, Ubisoft, Epic, GOG, Battle.net and Rockstar,
  installed first and the rest below (opening one installs it through its store). Rerun after every store sync by
  `.config/systemd/user/lutris-library.path`; an open Lutris shows the changes at once (the overlay's `library-refresh`
  action, asked over D-Bus; a plain Lutris once restarted). Installed Steam games join even when
  Lutris can't read the Steam library (game details private), with their covers (Steam's own copy when Lutris can't
  download one). A game on more than one store shows once: an installed
  copy, else the Steam one. The other copies go to Lutris's Hidden category. The store launchers (EA app, Ubisoft
  Connect, Battle.net, Epic, GOG Galaxy, Rockstar, Steam) are listed under Launchers in the sidebar (Library, below
  Uncategorized), installed or not: open one there to install it through Lutris (`agros-welcome` lists them too at the
  first login, making Lutris's folders and database first if it has never run). Steam installed on the system is listed installed:
  it opens it. A launcher lutris.net has no cover for gets one from `/etc/skel/.local/share/lutris/coverart` (Rockstar's, this repo's `.local/share/lutris/coverart`)
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
    the library or the key changed, one run at a time. Needs a free API key (steamgriddb.com → Preferences → API) in `~/.config/dots/steamgriddb.key`,
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
    last window closed (a game that doesn't exit, its crash reporter) is ended once it's idle, so Steam doesn't count it
    as running (not while it reads or writes the disk, a save; using CPU alone for about 10 minutes: hung, ended)

## Shared helpers

One problem, one place: the scripts call these (beside themselves, `$(dirname "$(readlink -f "$0")")/<helper>`, so a
helper a package update just brought works before `agros-links` has linked it), never their own copy of the logic.

- **`.local/bin/after-games`**: waits while a game is open; the update check, `lutris-library`, `hypr-reload`,
  `hyprbars-build` and `caelestia-restart` run after it, not while you play. What a game is: `game-focus --game-open` (its `is_game`, the one definition: a store
  launcher's window isn't one; `dots.is_game` in `user/apps.lua` agrees)
- **`.local/bin/store-launchers`**: the store launchers that run under Wine beside their games (EA app, Ubisoft
  Connect, Epic, Rockstar's...), one list read by `game-focus` and `user/apps.lua`: not games, though under Proton
  their windows get the games' class
- **`.local/bin/hypr-reload`**: the one way to reload Hyprland's config: after any game (a reload takes a fullscreen
  game out of fullscreen), Hyprland named (works from an SSH login or a text console). Used by the Settings app
  (`dots-settings`), `capri-update`, `vm-screen-follow` and `user/workspaces.lua`
- **`.local/bin/qs-running`**: whether a Quickshell config is running (`qs list --all` read whole: `grep -q` quitting
  early got qs a SIGPIPE, which `pipefail` took for "not running"). Whether Caelestia runs from the overlay:
  `caelestia-overlay --running` (its folder's path resolved too), `agros-welcome`'s and the overlay's own
- **`.local/bin/notify-when-up`**: the one way to notify at login or from a hook: tried again for up to a minute, as
  Caelestia is the notification server and one sent while it isn't up (login, a restart, a rebuild) went to nobody.
  Used by `dots-warn`, `dotfiles-check`, `hyprbars-build`, `capri-update`, `agros-welcome`'s offer, `nvidia-shader-fix`,
  `caelestia-restart` and `hypr-reload` (each waiting for a game), `update-kinds`' notices, `agros-each-user --notify`,
  `appimage-open` and `claude-notify` (Claude Code waits on its hook:
  2 s of tries, not a minute)
- **`.local/bin/dots-warn`**: the one way to warn that something in the setup needs a look (a critical notification
  from "Dotfiles", sent by `notify-when-up`). Used by the Lua config, the overlays (Caelestia's, Lutris's),
  `caelestia-restart`, `dotfiles-check`, `agros-links` (settings kept with AgrOS's new version beside them: marked said
  only once it got through), `nvidia-shader-fix` and `service-failed@.service`
- **`.local/bin/notify-wait`**: a notification that waits for its click (`notify-send -w`) and gives up when Caelestia
  restarts, so a click on a new notification can't reach an old one (used by `game-focus` and `update-apps`)
- **`.local/bin/json-edit`**: a JSON settings file changed by a jq filter, under its lock, replaced whole, tried again
  while Caelestia is rewriting it (Caelestia's `shell.json`: the weather place from the place picker and
  `agros-personal`, the Super menu and dock pins from `caelestia-pin`; Equibop's theme from `agros-welcome`). An
  empty file (Caelestia mid-rewrite) is left alone, not started again; a link stays a link (its target replaced), and
  the file keeps its mode. `json-edit --lock <file> <command>`: a command
  under the same lock (`caelestia-pin`'s dock order: its check, the change and its note as one)
- **`.local/bin/nvidia-screen`**: whether an NVIDIA card drives a screen (`--id`: its PCI address), for VA-API on it
  (`uwsm/env.d/nvidia-vaapi.sh`, by its installed path: read before `agros-links` runs) and the desktop widgets' stats panel's GPU meter
- **`.local/bin/fail-streak`**: counts a failure that keeps coming back, so it's given up on at the third run in a row
  rather than tried for good (`capri-update`'s download or merge, `agros-welcome`'s VSCodium step)
- **`.local/bin/wait-online`**: waits (at most ~2 min) for the network at boot or login (`auto-update`,
  `hyprbars-build`, `timezone-auto`); any HTTP answer is online, an error too: only no connection waits
- **`.local/bin/pacman-lock-holder`**: what running may hold pacman's lock, the one list of what takes it
  (`auto-update`, also before it takes out a stale lock of the boot's download, and `dotfiles-check`); one only reading
  (a query, a search or info, the files database, `paru -G`, what it would do printed, `-p`/`--print`/`--print-format`,
  an upgrade's too, `-Sup`, but not with `-y`/`--refresh` or `-c`/`--clean`, which take the lock) doesn't, nor one on
  another database
  (`-b`/`--dbpath`, or another system's, `-r`/`--root`; a plain pacman is on `/var/lib/pacman`'s)
- **`.local/bin/updates-pending`**: the updates waiting from a `pacman -Qu`/`paru -Qua` list, those `pacman.conf` holds
  back left out (`update-apps`, `update-kinds`, `auto-update`, `auto-update-aur`)
- **`.local/bin/update-kinds`**: the kinds of update, how each is listed (`--list`, what the Updates app shows: system,
  aur, firmware, flatpak, appimage, capri, proton, dev) and run (`update-kinds <kind>...`), and the Qt installed
  (`--qt-now`): `update-apps` and the boot's `auto-update` (as each user, `--boot`) both run it, its updates never as
  root (its queries, `--qt-now` and the runtimes' below, also from root's `auto-update`), one run at a time per user
  (a lock in `~/.local/state/agros`: the boot's and Updates' worked on the same Proton folders at once). Also
  the one list of runtimes whose new version breaks what's built on them (Qt, Python's minor version) and its queries
  (`--runtime-target`, `--runtimes-now`, `--built-on`): what the boot's AUR builds and `update-apps` both rebuild
- **`.local/bin/agros-each-user`**: runs a command as each AgrOS user (pacman hooks, the boot's update); `--list`
  lists them; `--as <user>` runs one as that user (or the boot's AUR builds' `agros-aur`) from root with `setpriv` (never `runuser`, `su` or `sudo`: their PAM
  opens a logind session, whose processes leave the calling service's cgroup and time limit, and makes the user count
  as logged in). Either way the command runs in a session of its own, with nothing on its input and its output
  through pipes this opens and waits for: a user's command (theirs to change) never reaches root's terminal nor root's
  own files (auto-update's log); the caller's stop (a timeout, a signal) is passed on to that whole session and then
  taken by `agros-each-user` itself (a run over the users stops, not on to the next one); the list of users is read
  whole first, nothing of it left open for a command to read; `--sessions` the session bus of each one logged in to a desktop (a logind session of type Wayland or
  X11, class user: not the greeter's, a text or SSH login, nor a background one; its bus the user's own, not a link;
  camera switch); `--notify [--user
  <name>]` says something on their desktops, now or once someone logs in (up to 12 h), from a unit of its own
  (`systemd-run`), so the caller doesn't wait, as the user in their account's group (not the bus file's): the system's
  one way (the firmware note, the boot's
  Proton notices)
- **`.local/bin/screens-on`**: the screens Hyprland has switched off (DPMS) switched back on, in each of your Hyprland
  sessions (`hl.dsp.dpms({ action = "enable" })`, as Caelestia's idle sends it); only when one is off (screens on, a
  fullscreen game: nothing sent), no reload, the pointer never moved; tried 10 times a second apart (just after waking
  Hyprland may not answer yet), each answer waited for up to 3 s: up to ~40 s per session when Hyprland doesn't answer,
  ~70 s when it answers the check but not the switch. Run after waking by `agros-system`'s sleep hook, as each user
- **`.local/share/github-release/lib.sh`**: a GitHub release's x86_64 file and its checksum, when the release has any (`appimage-update`,
  `flatpak-bundle-update`)
- **`.local/bin/app-for-window`**: the app a window belongs to when its class names none Quickshell finds (Java, Wine
  and script apps, a Flatpak's id): by the class's last part, the Flatpak's id, then the window's program against each
  app's `Exec`. So the dock, the switchers and the bar show the app's own icon (`.config/quickshell/common/WindowApps.qml`,
  the overlay's)

## Tray apps and startup

- **`.local/bin/app-launch`**: how the config starts apps (Proton VPN, btop, an app opened from a
  notification): in a unit of its own under uwsm, like apps from the launcher
- **`.local/bin/tray-keeper`**: a user service (`.config/systemd/user/tray-keeper.service`); when Caelestia restarts it
  brings back tray icons apps don't re-add (Proton VPN), and keeps Spotify hidden
- **`.local/bin/spotify-tray`, `protonvpn-open`**: start Spotify / Proton VPN in the tray; opening them from the
  launcher or dock shows them (the launcher entries in `.local/share/applications/` run these). `spotify-tray` also
  re-applies Spicetify when a Spotify update undid it
- **`.local/bin/artcraft-silent`**: ArtCraft Launcher at login in its tray only (`user/apps.lua`, Settings > Startup,
  off by default): it shows its window when it restarts after updating itself, so for its first two minutes any
  ArtCraft window that opens is closed, to its tray
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
- **`.config/systemd/user/service-failed@.service`**: when game-focus or tray-keeper keeps crashing (5 times in a
  minute) it's stopped instead of restarting forever, with a notification showing its last error
- **At login** (`user/desktop.lua`): `widgets-start`, `greeter-theme-sync`, `console-clear` (no old
  text under the desktop at shutdown), `cursor-hide-at-shutdown` (the pointer is on the graphics card's cursor layer,
  Hyprland's default, which follows the mouse with no lag; nothing clears that layer when the desktop closes, so this
  hides it at logind's PrepareForShutdown, holding a delay lock until Hyprland has taken that up; a shutdown called off
  after that brings it back), `keyring-default`, `bluetooth-on`, `vm-screen-follow` (in a VM), `timezone-auto` (when on), the update check timer, and `dotfiles-check`
  after 30 s
- **`.config/autostart/`**: Geoclue's demo agent (Caelestia starts it already) and Polychromatic's own autostart
  off (OpenRazer's service applies the
  lighting). Turning one on or off in the Settings app changes your copy here; `dotfiles-sync` commits it if it's in the repo
  already, else `dotfiles-sync add` it

## Apps

- **`.config/VSCodium/`**: VSCodium (VS Code's open-source build) settings and extension list (`extensions.txt`), with open replacements for the
  Microsoft-only extensions (basedpyright for Pylance, clangd for the C/C++ tools). Its launcher entries
  (`.local/share/applications/vscodium*.desktop`) show its logo without the white circle
  (`.local/share/icons/hicolor/scalable/apps/vscodiumlogo.svg`).
  Claude Code's plugins and conversations are in `~/.claude`, shared by both
- **`.local/bin/claude`**: Claude Code in the terminal (the CLI inside the editor's extension; without it, the next `claude` on PATH), for what the extension
  can't do, like `/plugin`. Its plugins (installed by `agros-welcome`, `CLAUDE_PLUGINS` in
  `.local/bin/agros-welcome`): [ponytail](https://github.com/DietrichGebert/ponytail) (minimal code; needs
  Node.js) and Addy Osmani's [agent-skills](https://github.com/addyosmani/agent-skills), each at its repo's latest version (not pinned: what they are at your first login). `.local/bin/claude-notify`: a notification when it finishes an answer (its Stop hook, added to `~/.claude/settings.json` by `agros-welcome` too)
- **`.local/share/firefox/`**: the LibreWolf settings Firefox Sync doesn't carry (`settings.js`: privacy, new tab,
  theme, toolbar layout, sidebar; add a `user_pref` line to keep another; its values refreshed from your profile by
  `dotfiles-sync`), the Lagoon theme with the Linux system theme off (a new profile gets Lagoon installed from
  addons.mozilla.org by `agros-welcome`), and the new tab's background picture (`newtab-wallpaper.jpg`). Your bookmarks
  aren't here: they travel in your LibreWolf profile on the pen drive (`agros-personal`). `.local/bin/firefox-bookmarks-export`
  writes them to a `bookmarks.html` LibreWolf can import, by hand; its `--profile` finds the LibreWolf profile's folder
  for `agros-welcome`, `agros-personal` and `dotfiles-sync`
- **`.config/librewolf/librewolf/librewolf.overrides.cfg`**: LibreWolf keeps cookies, logins and history when it closes
  (it erases them on every quit by default), allows the Firefox account and Sync, and tells sites the desktop's dark
  mode (Firefox's fingerprinting protection, all of it but that, instead of Resist Fingerprinting, which always says light).
  Video decoded on the graphics card (VA-API), and no AV1 (the desktop's RTX 2060 can't decode it, so YouTube sends VP9;
  on every machine). The default browser
- **`.config/mimeapps.list`**: default apps for file types
- **`.local/bin/appimage-open`**: opens AppImages (`.local/share/applications/appimage-open.desktop`): installs the app
  in `~/Applications` with a launcher entry, or replaces the old version, and starts it; so an app's own Update button
  updates it by itself. One on a drive that won't run it (a USB stick's FAT, a noexec mount) is copied there first
- **`.local/bin/appimage-update`**: updates those AppImages from their GitHub releases, checked against the release's
  checksums when it has them (some, but none for the file: not installed)
- **`.local/bin/flatpak-bundle-update`**: updates Flatpaks installed from a downloaded `.flatpak` file (no Flatpak repo,
  e.g. ArtCraft Launcher) from their GitHub releases, checked the same way; `--check` lists the ones with a newer version
  (both use `.local/share/github-release/lib.sh`: the release's x86_64 file and its checksum). At boot, each user's
  own are done as that user and the system-wide ones once, as root
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
  default); once she's installed, Shift+Space (Settings, Shortcuts; off while a game or a fullscreen window has the
  focus) puts her away or brings her back, through her local bridge (`POST 127.0.0.1:47823/toggle`). She sets her own
  window rules, by her windows' titles, and writes her windows' own (hidden) launcher entry for their icon
- **`.config/legion-control/`**: Legion Control's lighting choices, and the backup of Lenovo's original keyboard
  lighting profile (its "Default" mode puts that back)

## Updates and system

The `system/` files are the parts outside your home: `agros-system` and `agros-boot` install them (a pacman update
brings each change; nothing to run by hand).

- **Updates app** (`.config/quickshell/updates/`, in the Super menu; opened through `.local/bin/updates`):
  - Lists what's waiting, by app with its icon and old → new version: system and AUR apps, firmware, Flatpaks,
    AppImages, Capri, Proton builds, developer tools
  - A list that couldn't be made (`update-apps --list` failed) says so, not "Everything is up to date"
  - "Update all" runs `update-apps`, showing its progress; shown only while something is waiting. Closed with the
    title bar; an update already running carries on (its log: `$XDG_RUNTIME_DIR/update-apps.log`), and opening it
    again and pressing "Update all" follows it
- **Files never unpacked** (`packages/agros-system/agros-noextract.conf` at `/etc/pacman.d/agros-noextract.conf`,
  included by `pacman.conf` the same way, at install and at upgrade): pacman's `NoExtract` for what no one on AgrOS uses:
  docs and help pages (fish's and HPLIP's kept), the Nerd font styles nothing names (JetBrains Mono's Mono, Propo and NL,
  Cascadia's Mono and Propo), Material Symbols' Outlined and Sharp, Hyprland's own wallpapers. A new install has them
  left out from its first package: agros-iso's `agros-trim.sh` puts the same list in the installed `pacman.conf`
  (marked `# agros-iso`), which agros-system's install swaps for its Include; keep the two lists the same. On a machine
  installed before, a package's go at its next update
- **The upstream gate** (`packages/agros-system/agros-gate.conf` at `/etc/pacman.d/agros-gate.conf`, which
  `agros-system`'s install adds to `pacman.conf`'s Include lines, with the file; `.local/bin/update-gate`): Hyprland and its libraries (the packages AgrOS's config, title
  bar plugin and shell patches are written against) are held back from every pacman run, a manual one too, and updated
  by AgrOS's own updates (the boot's, the Updates app) only to versions AgrOS's CI has checked:
  - CI's test job runs every test against the newest Hyprland from Arch (the real one loading the whole config,
    `tests/hypr-api.sh`; against Hyprland's own Lua stubs, in handlers too: every Hyprland name and event AgrOS uses,
    the settings it reads by name, and those it makes in one-line `hl.config` calls (a multi-line one only through the
    load); the plugin built; the overlay applied); when all pass, those versions go on the approved list, published
    beside the `[agros]` repo (`agros-approved`, "name version" without the pkgrel, earlier approvals kept). Each
    package's version is approved on its own, not as the set it was tested in (decided: pacman's soname dependencies
    already refuse a mix whose libraries don't fit, and a mirror a little behind isn't held for it)
  - `update-gate <pacman.conf> <out>` gives the pacman.conf to update with: without the gate's Include when every gated
    package goes to an approved version (or only a rebuild of the same one, as for a library's new soname), else as it
    is (held together, and said: "waits for AgrOS's check"); a library whose update would break a held one held with it,
    and a package whose update needs one held (one rebuilt for a held library's new version; pacman's
    own dry run says which). Held, it's held by the gate's Include even when `pacman.conf` lost its own (a merged
    `.pacnew`). Every place that works out what to update goes through it, on the lists it uses: the boot's download
    and AUR builds (one needing a held package, or a newer version of one, isn't built: said; one `pacman.conf` itself
    holds back, `IgnorePkg`, isn't built either, nor the others of its build, and isn't counted as waiting; one a new Qt
    needs rebuilt holds that Qt back, said as any rebuild that can't be done), the shutdown's install
    (deciding again, the Updates app may have synced newer lists since, but from the approved list kept at the boot,
    `--offline`: nothing let through that the boot didn't download), the Updates app's list and its update. A held
    update isn't listed in the Updates app; the update log says what waits ("waits for AgrOS's check"). A version older
    in the repo than installed (a rollback) doesn't count: pacman keeps the newer one. The list is fetched from each of
    `[agros]`'s servers in turn (Pages, then the mirror) and kept for when none can be reached; never fetched, nothing
    new. It's taken only with a good signature by AgrOS's key beside it
    (`agros-approved.sig`, CI's release job signs it; checked with `gpgv` against `agros-keyring`'s key file alone,
    `/usr/share/pacman/keyrings/agros.gpg`): with none, or a bad one (a mirror or a network in between that changed it),
    that server's is as if it couldn't be reached, said ("no good signature by AgrOS's key"), and the next one is tried:
    none good, the kept list, nothing new let through. agros-iso's build and installer check it the same way
  - Checks that stop passing are said on the machine too: the boot's update keeps the day they last passed on Arch
    (`agros-arch-ok`, beside the repo; `/var/lib/agros/agros-arch-ok`, from the first of `[agros]`'s servers that
    answers), and `dotfiles-check` says after login, once it was over 10 days old when fetched: "AgrOS's checks haven't
    passed for N days: Hyprland updates wait until they do" (a broken check, or CI no longer running). No network at
    login: a copy the boot hasn't refreshed yet is counted to when it was fetched, not to today
  - The ISO build (agros-iso's `check_gate`) stops when its Hyprland isn't approved, keeping the published ISO; the
    ISO keeps a copy of that approved set, and a new install gets it rather than the newest unchecked one (agros-iso's
    `agros-gate-install`, an installer step)
  - The Include comes and goes with the file (`agros-system`'s install adds it, and each upgrade where it's missing: a
    machine from before the gate, a merged `pacman.conf.pacnew`; its removal takes it out): pacman can't read a config
    including a missing file, and the ISO's `pacman.conf` for the installed system is in place before anything is
    installed
- **`.local/bin/update-apps`**: updates everything (system and AUR apps with `paru` through the upstream gate, then each kind
  `update-kinds` runs: firmware with fwupd, Flatpaks, AppImages, Capri, Proton builds, developer tools), like at boot.
  `--list` is what the Updates app shows (`update-kinds --list`); every 6 hours (`update-check.timer`) it checks, and when
  updates are waiting a notification's "Update now" opens the Updates app and starts. With no terminal (the Updates
  app), sudo asks for the password in a dialog (`.local/bin/askpass`, zenity, as `SUDO_ASKPASS`). VSCodium's own
  updater (which only opens the website) is off
- **The boot update** (`agros-system`: `packages/agros-system/auto-update`, for every account): updates everything at
  every boot. Then: Flatpaks (system-wide and yours), AppImages, Proton builds and developer tools (`update-kinds
  --boot`, as each user; Capri's new release only looked for: `capri-update --check`). Downloaded then and installed at
  shutdown, after a Snapper snapshot (installed under the running session, a new NVIDIA driver or kernel broke games and
  USB devices until a reboot): the system, kernel and CachyOS gaming packages, the AUR apps, and firmware.
  - **AUR apps** (`packages/agros-system/auto-update-aur`, after the download): those with a newer AUR version (not in
    a repo: `paru -Qua`'s), and, when the download brings a new version of a runtime that breaks what's built on it,
    those built on it (from the AUR or `[agros]`, not a `-bin`, not rebuilt by their repo in the same download). The
    runtimes are one list, `update-kinds`' (`runtimes`, which `update-apps` uses too): Qt (`qt6-base`, `qt6-declarative`: any new version; what needs them,
    Quickshell, Caelestia, qtengine, qt6-m3shapes..., uses Qt's private parts and won't start on another Qt) and Python
    (a new minor version, 3.13 to 3.14: the packages with files in the old `/usr/lib/python3.13`, which the new one
    doesn't look in). Built in their dependency order (their `.SRCINFO`'s `depends`/`makedepends` on each other's
    packages or `provides`: quickshell-git before caelestia-shell), else by name. One of `[agros]`'s rebuilt for a runtime
    is rebuilt at the version installed (CI's, tested), not the AUR's newest: a git package's source pinned to the
    commit in its version, another's AUR files at the commit with that version; one not found isn't built, and the
    runtime waits, as on a failed build. Their
    build scripts are unreviewed (your choice), so they're built as an account of their own, `agros-aur` (a system
    account from `agros-system`'s `sysusers.d`: no login shell, no password, owning nothing but the run's build
    folder), never as root and never as a person (`agros-each-user --as`: `setpriv`, no PAM, so no logind session: the
    builds stay in `auto-update.service`'s cgroup, under its 4 h; its part refuses root), at the lowest priority
    (`nice -n 19`, `ionice -c 3`). Not as the main user, as it was: any process of theirs, needing no password, could
    rewrite a package's build files, sources or the staged system between its fetch and its build, or enter the
    sandbox's user namespace (the same uid), and so get a build of its own installed as root at shutdown. Another
    uid's processes are out of their reach (no ptrace, no signals, no `setns` into its namespaces), and so is its build
    folder (0700, its own, in root's 0755 `/var/lib/auto-update`); the main user takes no part in the builds. Every step that
    touches what the AUR sent runs in a `bwrap` sandbox: git's clone, the keys and sources' download and check
    (`makepkg --verifysource`), reading its `.SRCINFO`, the build, unpacking what it built, reading the packages back.
    The sandbox has its own namespaces (`--unshare-all`), no new privileges (so `sudo` can't work in it), `/usr`, `/etc`
    and `/opt` read-only and nothing else of the system (but pacman's list of what's installed, for the package's
    `.BUILDINFO`): no `/home` (yours neither), `/root`, `/run` (the system bus, the sessions'), `/mnt`, `/media`, `/srv`,
    nor the rest of `/var`; its own empty `/tmp`, `/var/tmp` and home, gone after each step. The network only while
    fetching and building (Go, Rust and Node apps fetch their own dependencies in `prepare()` or `build()`; the
    sources fetched and their signatures checked before, `makepkg --holdver`), and never the host's: a network
    namespace of the sandbox's own, outbound internet through pasta (`passt`, run as `agros-aur`: `pasta --config-net`
    makes the namespace, bwrap starts in it and maps the account back from pasta's root). 127.0.0.1 and ::1 are its own
    loopback and abstract sockets are per network namespace, so the host's local services (Capri's bridge, CUPS,
    an editor's) are out of its reach; pasta forwards no port either way (`-t`/`-u`/`-T`/`-U none`: its default binds
    the host's listening ports in the namespace) and maps neither the gateway's address to the host's loopback
    (`--no-map-gw`, `--map-guest-addr none`). The host's main address is the sandbox's own (pasta copies it), but its
    others were reachable through pasta, from the host itself, which LAN machines can't do: a second card, `docker0`,
    VMware's `vmnet1`/`vmnet8` and the VMs on them, `virbr0`, a VPN's tunnel, and whatever listens on them or on every
    address. So before bwrap starts, as the namespace's root (pasta's user namespace: nothing in the sandbox can undo
    it), every address the host has and every network its main routing table routes to (`ip -j addr`, `ip -j route`,
    read at each run) gets a `prohibit` route there (`--jail`; iproute2 alone, nftables isn't in a base install): a
    connection to one fails at once. Kept: the default route, and the LAN pasta gave the namespace (its route there
    already), so the gateway and the LAN's machines are reachable as from any machine on it. Not covered: link-local
    addresses (`fe80::`, `169.254/16`: not routed through pasta), and routes in tables other than the main one (a
    VPN's policy routing). One that can't be closed off stops the step (nothing runs open). DNS goes to an address of
    each family of its own (its own `resolv.conf`: `169.254.0.53` and `fd53:a6e4:2c3a::53`) that pasta sends to the
    host's resolver of that family, so an IPv6-only `resolv.conf` resolves too. Each base is fetched, checked and built on its own, its
    sources in a folder of its own (two bases' same-named files don't collide). Writable: only that run's build folder (`/var/lib/auto-update/aur-build`,
    `agros-aur`'s alone, made anew each run and removed after: no git config, cache or anything else a build wrote reaches the
    next run, nor a step outside the sandbox). Root opens nothing in it: each step's output goes to root's own
    `/var/lib/auto-update/aur/log/`; right after each build, the packages it made are read through the sandbox into
    root's own folder (a regular file only: a FIFO a build left there would block the read; each read under a
    `timeout`), and only those the plan names are kept (their `.PKGINFO`'s name and version as their file names
    them, at least the version planned, the AUR's or the installed one a runtime rebuild is pinned to: a `sudo` or `linux` a build left beside them isn't); a dependency a `.SRCINFO`
    names must look like one (`name`, `name>=1.2`) and reaches root's pacman after `--`. Nothing a build wrote reaches
    a notification as it is: the reasons `dotfiles-check` shows are fixed sentences, with a name stripped to
    `[A-Za-z0-9@._+<>=-]` (and `dotfiles-check` keeps only plain characters of anything `auto-update` wrote down,
    pacman's error included, which can carry an install script's words: Caelestia's notifications render Markdown,
    links and images); a build's own output reaches root's log through `cat -v` (no terminal escapes). What's left:
    an AUR package's own install script runs as root when it's installed at shutdown: that's what installing from the
    AUR is (paru's the same), the build scripts unreviewed being your choice; and the builds of one boot share the
    account and the folder, so one AUR app's build can tamper with another's built after it (or with the staged system
    it sees), all of them trusted the same. The sandbox sees
    the system as the download leaves it: every package the shutdown's transaction installs (`pacman -Sup`'s:
    upgrades, new dependencies, replacements), and what the builds need that isn't installed (downloaded from the
    repos, never installed), unpacked and laid over `/usr` (overlayfs), so they're built against the new runtime before
    it's installed. That download writes pacman's cache, as the boot's main one does: from the
    run's start to the end of its main download, and again around this one, the boot marks it
    (`/var/lib/auto-update/downloading`), and Updates' `update-apps` waits while it's there (not through the Flatpaks or
    the builds) before its `paru`, so both never write the cache at once. That was picked over the alternatives: a devtools clean chroot needs root to make
    and a full base system downloaded; installing Qt at shutdown and rebuilding at the next boot leaves a desktop that
    can't start if that build fails. Collected (read as `agros-aur`, through the sandbox) into a local repo, `agros-aur`, and installed at
    shutdown in the same `pacman -Su` as the repo's (`agros-aur/<name>` targets, a reinstall for a runtime rebuild of
    the same version), each one that built. Each base is on its own: one that failed keeps the version it has (as
    `paru -Syu` leaves it), named by `dotfiles-check` (until it's at the version the boot meant to build, Updates having
    built it; not beside the held update for the same failure), and the rest goes in. Only a new runtime waits for
    what's built on it: one of its rebuilds failed (or came out older than what's installed, which pacman would leave),
    and the whole update waits (a part of it would be a partial upgrade, and the shells or the Python apps wouldn't
    start), built again at the next boot, or by Updates (its `update-apps` rebuilds the same ones after its `paru
    -Syu`). An AUR app pacman refuses at the install (a conflict, a file conflict, a missing dependency: it refuses the
    whole transaction, and every shutdown failed the same way, the system never updated) is left out of a second try
    (`--ignore`; pacman installs nothing of a transaction it refuses), unless a new runtime in it needs it (then it
    fails as one, the lists put back); what's left out is written down (`/var/lib/auto-update/aur-install-failed`)
    and named by `dotfiles-check` until it's installed.
    A Qt the shells were rebuilt for is written down (`/var/lib/auto-update/qt-built`), so Updates doesn't rebuild
    them again
  - **Firmware** (fwupd): its metadata refreshed (LVFS, signed) and checked at boot (nothing said when offline or
    none). Any waiting is said on each user's desktop ("Firmware update ready... installed when you shut down or
    restart", once someone's logged in to a desktop: `agros-each-user --notify-wait`) and installed at the next shutdown
    only then, before the packages (a flash cut off could leave a device unusable; a package install cut off is taken
    up again at the next shutdown, with the snapshot to go back to), by `fwupdtool update --assume-yes` (fwupd's daemon can't be started at shutdown). Never under a time limit
    of its own (one sent it SIGTERM mid-flash; only fwupd's queries have one): the install's unit has 60 min, firmware
    starts only with 55 of them left, and the packages start only with their 30 left, else wait for the next shutdown
    (counted, as below); a flash still writing at the unit's 60 min has hung. The install's unit is ordered after udisks2 and the system bus (fwupd finds the EFI
    partition through udisks2, which stopped first before: a UEFI update was "installed" with nothing staged). fwupd's
    own checks stand (on battery below its level, or without AC power, it skips the device); its exit says nothing of
    a skipped device (nor, in 2.1, of a failed flash), so a device still offering the same update after it (`fwupdtool
    get-updates`) wasn't updated: tried at the next shutdown, said by `dotfiles-check` with fwupd's reason (Updates
    checks the same after its `fwupdmgr update`); that note goes once nothing's waiting. A UEFI or BIOS update is
    staged and applied at the next boot. Passim (fwupd's optional LAN cache: a listener sharing its metadata over mDNS
    and HTTPS, which fwupd starts over D-Bus) is masked once by `agros-system` (fwupd works without it, only logging
    that it's not there; removing `agros-system` unmasks it)
  - **Proton builds** (yours, as you) where Steam and Lutris look for them: Steam's `compatibilitytools.d` and Lutris's
    Wine runners (`$XDG_DATA_HOME/lutris/runners/wine`, or `lutris.conf`'s `runner_dir` when named in full: a relative
    one is skipped, as what's removed must be inside it). For each family there
    (GE-Proton from GloriousEggroll's GitHub releases, dwproton from Dawn Winery's at dawn.wine), its newest release
    beside the old ones (which release a folder is: its `version` file, else its name), checked against the release's
    `.sha512sum` (none, or not matching: not installed), unpacked in a hidden folder there and moved in whole, marked
    as this one's (`.agros-installed` in it). An old one is removed only when this installed it (one you or Lutris
    put there is never removed), it's not the newest, no game or default is on it, and it isn't running. In use:
    Steam's `config.vdf` `CompatToolMapping` (each game's and the default); Lutris's `wine:` `version:` in a game's
    config (`games/*.yml`) or the Wine runner's default (`runners/wine.yml`), in `~/.config/lutris` when that's there,
    else its data folder (Lutris's own rule). Lutris's own `dw-proton-x86_64` is lutris.net's "dw-proton" runner (a
    fixed name, no version in it): Lutris installs it once and never updates it, so the newest dwproton goes beside it
    and your games stay on it until you pick the new one. Lutris newer than 0.5.22 (its development version) also lists
    Steam's `compatibilitytools.d` and names a GE build without its folder's `-x86_64`: a folder is in use when any game of Steam's or Lutris's names
    it, either way. Running: its real path (Steam's is under the `~/.steam/root` link) in a process's command line, as
    text. A download cut off is removed on the way out, or (a power cut) at a run 6 h later. Steam lists its tools at
    its start: while your Steam runs, a notification says to restart it (never restarted for you). A new one in Lutris:
    a notification says to restart Lutris and pick it in a game's Configure, Runner options, Wine version (and, per
    family, which games' old one is kept). From the boot's run these are handed to root, which says them once you're
    logged in (`agros-each-user --notify`); from Updates, at once. The boot's run and Updates' never at once: the
    second waits (`update-kinds`' lock; the folder moved in with `mv -T`, never into one already there)
  - **Developer tools**, yours, only those there: npm's global packages only where its prefix is in your home (`/usr`'s
    are pacman's), `uv tool upgrade --all`, `rustup update`, cargo's programs with `cargo install-update` (without
    cargo-update, a one-line note), `pipx upgrade-all`
  Run in a terminal, `update-apps` shows each AUR package's build-script changes for review first; the Updates app's
  "Update all" builds them without that review (it lists which ones first, in its log; it asks for your password in a
  dialog). After its `paru -Syu` it rebuilds what's built on a runtime it changed (the boot's same list: Quickshell,
  Caelestia, qtengine for a new Qt; the AUR's Python packages for a new Python minor version), and on a Qt changed
  since they were last built, once the runtime is in: `[agros]`'s own at the version installed with AgrOS's Quickshell fix
  (through `auto-update-aur --fetch`, as the boot's), the AUR's others at their newest. Log: `/var/log/auto-update.log` (its last 20 runs kept);
  `dotfiles-check` says an install at shutdown that failed or was held back (until one goes through), AUR builds, AUR
  apps the install left out, or a firmware update that failed, and 3 shutdowns in a row with nothing installed, with the last one's reason (the boot's
  download didn't finish: only a finished one is installed; something else using pacman still held its lock; a soft
  reboot, which keeps the kernel running; on battery, nearly empty: below 15%, discharging; pacman's lists couldn't be
  kept aside, a full disk). An install cut off has pacman's lists put back, and its lock removed, at the
  next boot or install. The boot's run (download, Flatpaks, AUR builds and all, everything it started: nothing it runs
  as a user leaves its unit) stops after 4 h; a Flatpak from a file isn't reinstalled with less than 35 min of that
  left (cut off between its removal and install, the app would be gone). The Updates app waits only for its downloads. The install has 60 min (shutdown's own limit is made 75 min for it); `paccache.timer` keeps pacman's
  cache from growing for good
- **`agros-boot`**: hidden boot menu (GRUB or Limine): straight into CachyOS, Esc in the first second shows
  the menu (Windows and snapshots listed). No motherboard wait before the boot loader (`efibootmgr -t 0`; F11 still
  opens its boot menu). An update that changes `boot-menu` applies its settings again, over any of yours (one that
  doesn't change it leaves them): `boot-menu` notes each run in `/var/lib/agros/boot-menu.sum` (its checksum; empty when
  it failed, so the next update runs it again). With the boot loader not set up yet (the installer's package step: no
  `/boot/grub/grub.cfg` or `limine.conf`) it changes nothing; the installer's own step runs it once GRUB is set up, so
  `grub.agros-orig` is CachyOS's settings, not the grub package's own file. Removing it puts back the settings it changed from the copies kept before AgrOS
  (`grub.agros-orig`, `limine.conf.agros-orig`: timeout, menu, default entry, theme, `quiet`), takes out the `video=`
  options it set (in the form it writes, `video=<screen>:<W>x<H>@<Hz>`; your others stay), the quiet boot's options
  below that weren't there before AgrOS, the splash and the motherboard's wait (where it noted the one before)
- **`agros-boot`** also: no text at boot or shutdown, only the splash. `boot-menu` adds the kernel options missing from
  the normal entries' line (`GRUB_CMDLINE_LINUX_DEFAULT`, or Limine's `KERNEL_CMDLINE[default]` in `/etc/default/limine`,
  kept first as `limine.agros-orig`), through `boot-video-mode --quiet-boot`, the one place that edits that line for
  both. The file is a shell script: a `KEY=` line sets the options, each `KEY+=` after it adds to them, so the line is the
  set in effect (the last `=` and the `+=` after it): the missing ones go on its last line, one on any of them counts as
  there, and removal takes AgrOS's out of those lines only (the screens' `video=` out of every one). The options: `quiet` (kernel messages but critical ones off), `splash` (Plymouth's splash, not its text mode),
  `loglevel=3`, `rd.udev.log_level=3` (udev's start-up line in the boot image, before Plymouth is up) and
  `systemd.show_status=false` (systemd's status lines, failures too: they're in the journal, `journalctl -b -p err`; Esc
  on the splash still shows the text). One you set yourself under the same name (`loglevel=7`) stays.
  No `vt.global_cursor_default=0`: a text console and the emergency shell would have no cursor. Plymouth's hook is put
  in the boot image where the install left it out (`/etc/mkinitcpio.conf.d/90-agros-plymouth.conf`: before an
  `encrypt` hook, else last, an older `HOOKS="..."` string split into words first; in the images from the next time
  they're made), so the splash is up from the start. The
  shutdown's own steps already say nothing on screen: the update install (`auto-update --install`) writes to the
  journal, its progress on the splash (`plymouth display-message`), and the shutdown splash is Plymouth's own
  (`plymouth-poweroff`/`-reboot`)
- **`agros-boot`** also: no "no video" between the login screen and the desktop. `system/boot-video-mode` at every boot gives the kernel console each connected screen's best mode as a
  `video=` boot option (Limine or GRUB), and only rebuilds the boot entries when the screens changed
- **`agros-nvidia`**: loads the NVIDIA driver from the start of the boot (in the initramfs, which CachyOS's
  `chwd` leaves it out of): about 2 s sooner, with the boot splash on it
- **The boot images** after `agros-boot` or `agros-nvidia` is installed, updated or removed: made again once, after the
  transaction, by mkinitcpio's own pacman hook (Limine's `limine-mkinitcpio-hook` has its own in its place), which
  watches `usr/lib/initcpio/*`: `agros-boot` ships a file there (`plymouth-title-font`), `agros-nvidia` one only for this
  (its list is in `/etc/mkinitcpio.conf.d`, which the hook doesn't watch). Not from their install scripts: with a kernel
  updated in the same transaction, its old modules were gone, so they failed (said so for nothing) and the images were
  made twice. `splash-theme` run by hand or by its own hook still makes them (`limine-mkinitcpio` on Limine, else
  `mkinitcpio -P`, the command it names when they fail)
- **`agros-greeter`** and **`agros-system`**: unlock the passwords keyring with your login password (no keyring prompts from
  Proton VPN, Equibop...)
- **`agros-system`**: Bluetooth on at boot and after sleep (`system/bluetooth-resume`,
  a systemd sleep hook: waking resets the adapter, which comes back off)
- **`agros-system`** also: the screens on after waking, with no key press (`system/screens-resume`, a systemd sleep
  hook). Caelestia's idle switches the screens off (`dpms off`, 10 min) before its idle sleep (30 min), and on again
  only at the next input (its `returnAction`), so the PC woke to black screens. After waking the hook runs
  `agros-each-user screens-on` in a unit of its own (`systemd-run --no-block`): not waited on, as sleep hooks run before
  systemd thaws the user sessions it froze (without NVIDIA's `SYSTEMD_SLEEP_FREEZE_USER_SESSIONS=0`, a VM's case), when
  Hyprland can't answer. Caelestia's idle still counts you idle until you touch something, so it doesn't switch them
  off again until then
- **`agros-system`** also: AgrOS's name in `/etc/os-release` and `/etc/lsb-release` (`agros-branding`, a pacman hook
  run after CachyOS's own, `zz-agros-os-release.hook`; `ID_LIKE` keeps cachyos and arch; its removal puts the old
  name back), and, in a VMware VM, `/etc/vmware-tools/tools.conf` with `resolutionKMS` on, so VMware's tools pass a
  resized window on and `vm-screen-follow` (at login) has Hyprland take the new size
- **`agros-system`** also: the night light's location without a prompt (`system/geoclue/agros.conf`) and the time zone
  changed without the password by admins at the machine (`system/polkit/agros-timezone.rules`), both described under
  Desktop and Caelestia
- **pacman hooks** (`agros-system`, for every account through `agros-each-user`): the Caelestia overlay re-applied after
  every `caelestia-shell` update; the title bar plugin built for a new Hyprland (or a library its plugins hang on)
  straight away; the Hyprland config checked against a new Hyprland (`hypr-config-check`, its errors said by
  `dotfiles-check`); the overlay, the title bar plugin and the config check also after an `agros-scripts` update
  (their scripts are in it; the check is `Hyprland --verify-config`, well under a second per user). `agros-boot` adds one that
  hides GRUB's loading messages again after each GRUB update, and one that remakes the faster splash after a CachyOS
  splash update (and the boot images, when it changed and is the splash in use)
- **The splash** (`agros-boot`): the CachyOS animation without its closing animation, boot/shutdown text hidden,
  "Shutting Down..." and "Restarting..." in the system language. Not on an AMD GPU (`chwd --check amd`, as CachyOS's
  installer asks; without `chwd`, an AMD card in `/sys/class/drm`): the animation breaks on amdgpu, so CachyOS's
  installer sets its plain `cachyos` splash there, and AgrOS keeps it (the faster one, set by an older AgrOS, moved to it)

## Laptop hardware

- **`.local/share/camera-switch/`**: makes the physical camera switch turn the webcam off/on (Legion webcam;
  `agros-camera-switch`, its service and udev rule, installed by `agros-welcome --system` on the Legion)
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
| `refit_placed_soon()` | `user/windows.lua` | the overlay's `bar_space_refit` (Caelestia's bar's space changed); its own events |
| `refit_window(win)` | `user/windows.lua` | `refit_maximised` (each window), a minimised window's restore |
| `window_fades(on)` | `user/windows.lua` | `focus_window` (off while Alt+Tab leaves a fullscreen game, on again a moment later) |
| `switcher_open(open)` | `user/keys.lua` | the switcher, as it opens and closes (Super+drag off while it's open) |
| `toggle_window_mode()` | `user/windows.lua` | bar menu, the Settings app (window mode) |
| `window_drag_start(address, kind)`, `window_drag_step(address, kind)`, `window_drag_end(address, kind)`, `titlebar_drag_start(address, phase)` | `user/windows.lua` | the hyprbars patch (each drag's start, each step, its end) |
| `titlebar_height(win)` | `user/titlebars.lua` | `user/windows.lua` |
| `is_game(win)` | `user/apps.lua` | `user/windows.lua`, `user/titlebars.lua` |
| `started_for_game(pid)` | `user/apps.lua` | `user/apps.lua` (store launchers a game started open minimised) |
| `without_warps(fn)` | `user/windows.lua` | `user/workspaces.lua` (Super+N, `clean_workspace`) |
| `setting(key)` | `hypr-user.lua` | everything the Settings app changes |
| `hl.plugin.hyprbars.min_size(address)` (the other way round: the plugin's, for Lua) | the hyprbars patch | `user/windows.lua` (a snapped neighbour's smallest size) |
| `settings(prefix)` | `hypr-user.lua` | the settings whose key starts with it, by key (`user/monitors.lua`: the Screens page's) |
| `bind(name, action, opts)` | `hypr-user.lua` | my shortcuts (keys from the Settings app) |
| `peek_screen(screen, address...)`, `peek_end()` | `user/windows.lua` | window peek (overlay `WindowPeek.qml`): only those windows on that screen, the others faded out; all back |
| `goto_workspace(n)` | `user/workspaces.lua` | switcher, the bar's workspaces and workspace previews (overlay), game-focus |
| `clean_workspace(n)`, `merge_target(n, has)` | `user/workspaces.lua` | the Super+Tab switcher's ×: workspace n's windows to `merge_target`'s (the nearest other with windows, the previous on a tie; tests/workspace-merge.sh) |
| `screens_changed()` | `user/workspaces.lua` | itself, after the reload a screen change makes (windows back to a returning screen) |
| `monitor(rule)` | `user/monitors.lua` | host files |
| `lid(closed, output)` | `user/monitors.lua` | itself (at load, and the lid switch: at once, no reload); `output` only to try it on a screen that isn't a laptop panel |
| `spotify_silent_set(on)`, `spotify_hide(address)`, `spotify_show()` | `user/apps.lua` | spotify-tray, tray-keeper, caelestia-restart |
| `minimise_launcher(address)`, `open_retry(address)` | `user/apps.lua`, `user/windows.lua` | themselves, a moment after a window opens (a sleep in its own process: a config reload would drop a timer) |

## Keeping it in sync

`dotfiles-sync` (below) pushes to the repo you cloned (`~/Projects/agros`, which is **public**): to keep your own copy, fork this repo
first and clone your fork. Your bookmarks and the new tab's picture are never exported into it; they're personal and
travel in your LibreWolf profile on the pen drive.

After changing settings, run `dotfiles-sync` (`-n` to see what changed first; `add <file>` to keep a new file). It
copies your current settings into the repo (`$DOTFILES_DIR`, default `~/Projects/agros`; Legion Control into
`$LEGION_CONTROL_DIR`), commits and pushes. Only what it copied, or what matches your copy at home,
is committed: a file you're editing in the repo itself (newer than yours, said as skipped) and any other change there are
left out, set aside for the pull and put back after (one that clashes with what was pulled stays in `git stash`, and
the sync says it failed).

After pulling changes made elsewhere, copy the ones you want into your home first, or the next `dotfiles-sync` skips
the files the repo has newer (and says so) until you do. Changes to `packages/`, `system/` or the login screen reach
the system as package updates: push them, CI publishes the new packages, and the next update installs them (a change
to `agros-desktop`, `agros-welcome`, `agros-keyring`, `agros-nvidia` or `agros-wine` with its `pkgver` raised: CI fails
without it; `agros-vmware`'s and `agros-thunar-usage`'s versions move only with a commit to their folder in
`packages/`, `agros-boot`'s only with one to what it's made from, `agros-hyprbars`' with one to it or a new
Hyprland).

## Tests

`tests/run.sh` runs them all (`tests/run.sh lutris-overlay` just one), each in a throwaway home, so nothing of yours is
touched. Several run at once (one per CPU; `AGROS_TEST_JOBS=1`, one at a time), and one that fails among them runs again
alone: only a failure there counts. A pass ends on the test's own `ok <test>` line, so one that stops early with exit 0
fails. Run it after changing a script, and after Caelestia, Lutris or Hyprland updates: they check that the
Caelestia and Lutris changes and the hyprbars patch still fit, besides the boot update (its AUR builds, firmware,
Proton and developer tools too), the account restore, the
bookmarks export, dotfiles-sync not undoing pulled changes, the settings file Lua reads, the login screen's theme,
lutris-covers' cover checks and the boot video mode, and that every program the configs run (login starts, keys,
Caelestia's too, the Super menu's actions, the user services, the Quickshell apps) is installed (`config-programs`). One is a lint (`no-pipefail-grep-q`): every shell script that sets
`pipefail` must not pipe into `grep -q` (it stops reading at its first match, the writer dies of SIGPIPE, and the
pipeline reads as "not found": a running Proton was removed under a game), nor into `head`/`grep -m` where the
pipeline's status decides something; read the output whole (`grep -q x <<<"$(cmd)"`), or mark a line
`# pipefail-ok: <why>`.

CI runs them on every push (not one to the docs alone), pull request and night, with what the checks against Caelestia, Hyprland, Qt and the kernel need
(its dots at the pinned commit), so none is skipped there: a skip there, whole or in part (`skipped` in
`tests/lib.sh`; `tests/run.sh` for a whole one), fails CI, as its pass approves that Hyprland. The checks against
upstream's next release (Caelestia's, Lutris's and Hyprland's main branches, hyprland-plugins' main: a change there
that breaks one of AgrOS's shows first) are the exception: one that doesn't fit, or couldn't be fetched, is said on the
test's last line (`ahead` in `tests/lib.sh`: "ok caelestia-overlay (AHEAD: ...)"), never a failure. Neither the published
`[agros]` nor an older Arch undoes a change on main, so it read as AgrOS's own code and nothing went out; the release,
once it comes, is checked as installed like any other.

### Keeping itself up

On `main` CI builds the repo first, then tests what it built, then puts out what passed, so an upstream change that
breaks something holds back that one piece, never the rest (`.github/workflows/ci.yml`):

- **Signed apart from the build.** The `repo` job runs AUR build scripts (as its builder user, with passwordless
  sudo) and `test` runs what was built and the tests, so neither has a secret: the repo goes between them unsigned
  (`ci/build-repo.sh` refuses to start with a secret key at hand), with only AgrOS's public key (`ci/agros.asc`), which
  the published files it keeps are checked against and `agros-keyring` is made from. The `release` job, a container of
  its own that runs none of that, puts the release together, then signs it in one step, the only one with
  `AGROS_GPG_KEY` (`ci/sign-repo.sh`): each new package (one kept as published keeps its signature; one with any other
  `.sig` stops it), the database made again and signed, `agros-approved` and `agros-arch-ok`; each signature checked
  against `ci/agros.asc`, then gpg's agent stopped and the key removed before anything else runs (CachyOS's keyring,
  the install check with signatures required, the upload to Pages). `tests/ci-signing.sh` checks the workflow keeps it
  so. Moving to a new signing subkey: add it to `ci/agros.asc` (and agros-iso's `agros.asc`) and raise
  `agros-keyring`'s `pkgver`, let machines update, then replace the secret; signing with a subkey `ci/agros.asc` lacks
  fails the release, before anything goes out.
- **A package that doesn't build** (an AUR change, AgrOS's Quickshell patch or Calamares changes no longer fitting,
  Calamares built without a module its settings name, a download that failed): the published one is kept, its
  signature checked, with the packages of the repo it needs (`ci/published.sh`); the rest goes out. None published yet:
  the build fails. The AUR packages and CachyOS's installer are built without compiler warnings (theirs, not AgrOS's);
  AgrOS's own packages keep them.
- **Tests that fail** (`ci/test-passes.sh`): all the tests are run again, to see which side broke them: with the published `[agros]`
  (they pass: this run's new AUR builds broke them, swapped for the published ones by `build-repo.sh --hold-new`; the
  new Hyprland still approved), then on Arch as of the last day the tests passed on it (its archive's snapshot; the day
  published as `agros-arch-ok`): they pass, an Arch update broke them (its Hyprland not approved, the new AUR builds
  held, AgrOS's own packages still out). Failing even then: AgrOS's own code, and nothing goes out.
- **Upstream's next release** no longer fitting AgrOS's changes (a check against a main branch, above): nothing held,
  everything goes out, and the issue below says which change to adapt before that release.
- **One issue** (`ci/report.sh`, label `held`) says what was held back or why nothing went out (or, as "Heads-up", what
  of upstream's next release doesn't fit), brought up to date by each run and closed by itself once one puts everything
  out again with none of these. GitHub notifies of it.
- **Every Friday at 17:00 Lisbon time** an issue (`ci/status.sh`, `.github/workflows/status.yml`, label `status`,
  last week's closed) says whether anything needs a look: the last CI and ISO runs (an ISO run the upstream gate held,
  which built nothing and which GitHub shows as a success, too), what's held (and since when), CachyOS changes waiting
  for a merge (agros-iso's CachyOS sync, since when) and the sync's own failures (its ISO check's are the pull request's
  to say), a daily run (CI's, the sync's) not seen for 3 days (GitHub turns a public repo's schedules off after 60 days
  without a commit), whether Arch's newest Hyprland is approved yet, and CachyOS's installer recipe or code moved on
  past AgrOS's pins (`calamares_pkgbuild`, `calamares_src`); a lookup that fails is said too, never read as
  nothing to say. Its table also says how far Caelestia's dots have gone since the commit `agros-hyprland-settings`
  pins (a new one is taken on purpose; nothing else says when there is one). The owner is mentioned, so GitHub notifies
  them. Its size watch (`ci/sizes.sh` in an Arch container, `ci/sizes.py`) works out
  from the package databases what goes on the live ISO (agros-iso's list as `agros-trim.sh` leaves it) and on a new
  install (`netinstall.yaml`'s selected groups), nothing built, and says: a package new this week of 20 MiB or more
  and what pulled it in, either set grown 50 MiB or more, a package `agros-trim.sh` leaves out coming back, a listed
  name no repo has, a NoExtract pattern (the live ISO's, installed systems', `agros-noextract.conf`) matching no file
  any more, the installed systems' two NoExtract lists differing, and each fallback `agros-trim.sh` took (a name
  CachyOS's list no longer has, the LTS kernel kept, NoExtract not added: its lines ending in "(agros-trim.sh)",
  otherwise only in the ISO build's log, while the ISO stays bigger for good). A set pacman can't work out (a
  dependency no package provides, a conflict, an empty list) is said with pacman's error, and its last week's sizes
  kept for the next; a set whose files pacman can't all list has its NoExtract patterns left unchecked, said. Last
  week's sizes are kept in last week's issue (a comment in its body; left out, said, if it would take the body past
  GitHub's 65536 characters); the size watch not running at all is said with a link to its log.
- **Once a month** `.github/workflows/keepalive.yml` turns every scheduled workflow here (CI's nightly run, the weekly
  status, itself) on again through GitHub's API (`gh api -X PUT repos/<repo>/actions/workflows/<file>/enable`, with
  `actions: write`), as keepalive-workflow v2 does, so GitHub's 60 days without a commit never turn them off; no dummy
  commits. agros-iso has the same for its CachyOS sync. That it works can only be seen once 60 days pass with no
  commit; until then the status issue's "not seen for 3 days" is what says a schedule stopped.

## Troubleshooting

- **The login screen broke**: Ctrl+Alt+F2, log in, `sudo login-reset` (a text login; `sudo login-reset --back` undoes it)
- **Something stopped working after a Hyprland or Caelestia update**: run `dotfiles-check`. It lists Hyprland config
  errors (the config checked from disk with `Hyprland --verify-config`, by `hypr-config-check`: the running Hyprland's
  own list is cleared by every `hyprctl eval`) and outdated settings, Caelestia changes that no longer fit (skipped by the overlay), and parts that aren't
  running (Caelestia, the switcher, the widgets, the title bar plugin, the services) or logged errors, and my QML in
  Caelestia that fails to load (a Caelestia update renamed something it uses, which the patches can't see). It also runs
  30 s after login and sends a notification only if something's wrong
- **Caelestia's Hyprland config has an update** (a low-urgency note from `dotfiles-check`, once per new version): run
  `caelestia-hypr-refresh`. It refreshes `~/.config/hypr` alone (files you haven't edited replaced, Caelestia's new
  version written beside the ones you have as `.new`) and checks the config. Not `caelestia update`: its own system
  update skips the Qt rebuild (the boot update's and the Updates app's), and a new Qt leaves the shell unable to start
- **No title bar highlight**: see `~/.cache/hyprbars-build.log`, or run `hyprbars-build`
- **A first-login step failed**: `agros-welcome` runs again at the next login (or run it yourself); its log is
  `~/.local/state/agros/welcome.log`
