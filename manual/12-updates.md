# Updates

You don't have to think about updates.

- **At every boot**, AgrOS updates your Flatpaks and AppImages, your Proton builds in Steam and Lutris (GE-Proton,
  dwproton) and your developer tools (npm's packages in your home, uv's tools, Rust, cargo's and pipx's programs), and
  downloads the system's updates. Your AUR apps are built then too, quietly in the background: not as you, nor as
  the system's administrator, but as an account of their own (`agros-aur`, which can't log in and owns nothing but
  its build folder, out of your programs' reach), in a sandbox that sees no one's files (yours neither), no other
  drives, nothing of your desktop session, and none of the programs listening on your computer (Capri's bridge, the
  printer service, a VM's or Docker's network, a VPN's): its internet is its own, out to the web and your LAN only, so
  apps that download their own parts while building still build. Their build scripts aren't reviewed first (in a
  terminal, `update-apps` shows them), so this is a trust in the AUR: like any AUR helper, an AUR app installed at
  shutdown runs its own install steps with full rights, and one AUR app's build could tamper with another's built in
  the same boot. It also looks for firmware updates for your computer and devices.
- **At shutdown**, it installs the system's updates and the AUR apps together, after taking a snapshot of the system
  first. These are never installed under a running desktop, where a new graphics driver or kernel can break things
  until you restart (only **Update now** installs right away, when you ask). When an update brings a new version of
  Qt (what the desktop shell is built on) or Python, the AUR apps built on it are rebuilt for it at boot, before it's
  installed; if that rebuild fails, the whole update waits (installed alone, they wouldn't start) and a notification
  says so. **Update all** in the Updates app rebuilds them the same way.
  Any other AUR app that didn't build, or that can't be installed (it clashes with another package), just keeps its
  version until the next try, the rest of the update goes in without it, and a warning after you log in names it.
- **Firmware** is installed at shutdown too, but only after a notification told you it's ready. It starts only when
  there's time for it (the shutdown's install gets an hour), with no shorter limit of its own, and if it takes long the
  system's updates wait for the next shutdown instead; a flash still running at the hour's end is stopped, as one that
  has hung. A BIOS/UEFI update is
  applied as the computer next starts: don't turn it off then. On a laptop running low on battery, or unplugged when
  the device needs power, it waits for the next shutdown (a warning says so after you log in).
- **A new Proton build** (GE-Proton, dwproton, in Steam or Lutris) shows up in Steam once you restart Steam, and in
  Lutris once you restart it and pick it in a game's **Configure**, **Runner options**, **Wine version** (a
  notification says so). The old one stays while a game uses it, and one you installed yourself is never removed.
- **Hyprland waits for AgrOS's check.** A new Hyprland (the desktop's window manager) and the libraries it's built on
  are installed by AgrOS's own updates (at shutdown, and the Updates app) only once AgrOS's automatic checks have passed
  with that version, usually the same day, so an update upstream can't break your desktop. A few other packages wait
  with it: a library whose update would break the Hyprland you have, and apps built for the newer one. Everything else
  updates as usual, and what waits isn't listed in the Updates app until it can be installed. `sudo pacman -Syu` in a terminal never updates them, and can stop with a dependency error while one is held:
  use the Updates app instead. A new install gets the Hyprland the ISO was checked with when a newer one is still
  waiting.
- **Every 6 hours** it checks again. When something's waiting, a notification offers **Update now**.
- **At your next login** after an update, the desktop's settings files you never changed get AgrOS's new version. One
  you changed is left as you have it: AgrOS's new version goes beside it, named `<file>.agros-new`, and a notification
  lists them, so you can compare and copy over what you want. Your own choices (Caelestia's settings and weather
  location, the dock's pins, default apps, startup apps) are never touched.

## The Updates app

Open **Updates** from the app menu, or click the button next to the app menu's search bar. It lists what's waiting, app
by app, with old and new versions: system and AUR apps, firmware, Flatpaks, AppImages, Proton builds and developer
tools. **Update all** installs everything now, firmware included.

In a terminal, `update-apps` does the same and shows what each AUR package's build script changed before building it.

## If an update goes wrong

The system takes a snapshot before every update (on the btrfs drive AgrOS installs by default, where snapshots are set
up). To go back, restart, press **Esc** as the computer starts to show the boot menu, and pick a snapshot.
