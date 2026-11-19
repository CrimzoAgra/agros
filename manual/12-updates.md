# Updates

You don't have to think about updates.

- **At every boot**, AgrOS updates your Flatpaks and AppImages, your Proton builds in Steam and Lutris (GE-Proton,
  dwproton) and your developer tools (npm's packages in your home, uv's tools, Rust, cargo's and pipx's programs), and
  downloads the system's updates. Your AUR apps are built then too, quietly in the background, by an account of
  their own (`agros-aur`) in a sandbox that sees none of your files, your desktop or the programs listening on your
  computer: only the internet and your LAN. Their build scripts aren't reviewed first (in a terminal, `update-apps`
  shows them), so this trusts the AUR as any AUR helper does: an AUR app runs its own install steps with full rights
  when it's installed. It also looks for firmware updates for your computer and devices.
- **At shutdown**, it installs the system's updates and the AUR apps together, after taking a snapshot of the system
  first. These are never installed under a running desktop, where a new graphics driver or kernel can break things
  until you restart (only **Update now** installs right away, when you ask). When an update brings a new version of
  Qt (what the desktop shell is built on) or Python, the AUR apps built on it are rebuilt for it at boot, before it's
  installed; if that rebuild fails, the whole update waits (installed alone, they wouldn't start) and a notification
  says so. **Update all** in the Updates app rebuilds them the same way.
  Any other AUR app that didn't build, or that can't be installed (it clashes with another package), just keeps its
  version until the next try, the rest of the update goes in without it, and a warning after you log in names it.
  On a laptop below 15% battery and unplugged, nothing is installed: it waits for the next shutdown.
- **Firmware** is installed at shutdown too, but only after a notification told you it's ready, and before the
  system's updates (which wait for the next shutdown if the firmware took long). A BIOS/UEFI update is applied as the
  computer next starts: don't turn it off then. On a laptop running low on battery, or unplugged when the device needs
  power, it waits for the next shutdown (a warning says so after you log in). One that doesn't fit on the boot
  partition (EFI) is said once ("Firmware update can't be installed... the boot partition (EFI) is too small for
  it"), and isn't tried again (nor listed in the Updates app) until a newer one comes (when it's the only firmware
  update waiting): installed beside
  Windows, that partition is often Windows' own small one.
- **Some updates wait for you.** An AUR app whose maintainers changed since it was last built waits until you review
  it: run `update-apps` in a terminal, which shows what its build script changed before building it (a warning after
  you log in names it, and the Updates app leaves it out and says so). An app installed from a Flatpak file (ArtCraft)
  whose new version asks for more access waits for the Updates app, which lists what it adds, and **Update all** asks
  before installing it: say yes only if you trust it with that.
- **A new Proton build** (GE-Proton, dwproton, in Steam or Lutris) shows up in Steam once you restart Steam, and in
  Lutris once you restart it and pick it in a game's **Configure**, **Runner options**, **Wine version** (a
  notification says so). The old one stays while a game uses it, and one you installed yourself is never removed.
- **Hyprland waits for AgrOS's check.** A new Hyprland (the desktop's window manager) and the libraries it's built on
  are installed by AgrOS's own updates (at shutdown, and the Updates app) only once AgrOS's automatic checks have passed
  with that version, usually the same day, so an update upstream can't break your desktop. A few other packages wait
  with it: a library whose update would break the Hyprland you have, and apps built for the newer one. Everything else
  updates as usual, and what waits isn't listed in the Updates app until it can be installed. `sudo pacman -Syu` in a
  terminal never updates them, and can stop with a dependency error while one is held: use the Updates app instead. A
  new install gets the Hyprland the ISO was checked with when a newer one is still waiting.
  If AgrOS's checks stop passing for more than about 10 days (something upstream broke them, or AgrOS's automatic
  checks stopped running), a warning after you log in says "AgrOS's checks haven't passed for N days: Hyprland
  updates wait until they do". Nothing's wrong with your computer: everything else still updates.
- **Every 6 hours** it checks again. When something's waiting, a notification offers **Update now** (to an
  administrator: other accounts get their updates at boot and shutdown all the same).
- **Right after an update** (and at each login), the desktop's settings files you never changed get AgrOS's new
  version, and new ones are added, with no need to log in again. One you changed is left as you have it: AgrOS's new
  version goes beside it, named `<file>.agros-new`, and a notification lists them, so you can compare and copy over
  what you want. Your own choices (Caelestia's settings and weather
  location, the dock's pins, default apps, startup apps) are never touched.

## The Updates app

Open **Updates** from the app menu, or click the button next to the app menu's search bar. It lists what's waiting, app
by app, with old and new versions: system and AUR apps, firmware, Flatpaks, AppImages, Proton builds and developer
tools (point at a version cut short to see all of it). **Update all** installs everything now, firmware included, and keeps the laptop awake meanwhile, closing the
lid included. It installs nothing on a laptop below 15% battery and unplugged: plug the charger in first. An account
that isn't an administrator sees the list, with "An administrator has to install these updates", and no **Update all**
(its updates are installed at boot and shutdown all the same).

In a terminal, `update-apps` does the same and shows what each AUR package's build script changed before building it.

## How updates stay safe

AgrOS is built on others' work: Arch and CachyOS (the system), the AUR (Caelestia, Quickshell and the other apps AgrOS
builds for you) and CachyOS's ISO (what the live USB is made from). Every change from them is checked before it reaches
you. When one breaks something, only that piece waits; the rest keeps updating.

| When upstream... | AgrOS... | Your computer... |
|---|---|---|
| updates Hyprland or its libraries | tests its config, title bar plugin and shell against it every day, and approves a version that passes | takes only approved Hyprland versions; meanwhile everything else updates |
| ships an Arch update that breaks AgrOS's tests | finds it by running the tests again on Arch as of the last good day | keeps the Hyprland that works |
| changes an AUR app so it no longer builds (or AgrOS's fix to it no longer fits) | keeps the published package | keeps the version that works |
| changes an AUR app so the tests fail | swaps the new build back for the published one | keeps the version that works |
| changes its next release (Caelestia's, Lutris's or Hyprland's main branch) so AgrOS's changes won't fit | says so in the `held` issue, as a heads-up, and publishes as usual | isn't affected: the release is checked once it comes |
| (AgrOS's own change fails its tests) | publishes nothing | doesn't change |
| changes its ISO | merges it into AgrOS's ISO by itself each day, if it merges cleanly, brings back nothing AgrOS removed, adds no KDE, keeps AgrOS's installer, changes nothing that runs as root or decides what's trusted, and the ISO still builds | isn't affected: it updates from the repos above |
| changes its ISO in a way that can't be merged by itself | opens a pull request saying what changed and why | isn't affected; the ISO stays as it is until it's merged |

A held Hyprland update isn't listed in the Updates app; the update log says it "waits for AgrOS's check".

**AgrOS's maintainer is told** by email, through GitHub issues that mention them. One issue, labelled `held`, says
what's held back and why (or, as a heads-up, what of an upstream's next release AgrOS's changes don't fit yet), and
closes by itself once everything goes out again. Every Friday at 17:00 Lisbon time a
status issue says "Nothing broke this week" or what needs a look: a build failing, something held (and since when), an
ISO waiting for AgrOS's check of its Hyprland, a CachyOS pull request waiting or the CachyOS sync failing, a daily job
that stopped running, Arch's newest Hyprland not approved yet, CachyOS's installer changed since AgrOS last checked
it, or anything it couldn't check. It also checks how big
the ISO and a new install are against the week before, and says when either grew a lot, when something AgrOS took out
came back, or when a trim stopped working (files AgrOS skips that are installed again), so neither quietly gets bigger.

**What needs a person:** only a CachyOS pull request (resolve its conflict and merge it), or something held for more
than a few days (an upstream change AgrOS's own code has to be adapted to). Everything else sorts itself out. The
details: [Keeping itself up](../docs/how-it-works.md#keeping-itself-up) and
[the upstream gate](../docs/how-it-works.md#updates-and-system).

## If an update goes wrong

The system takes a snapshot before every update (on the btrfs drive AgrOS installs by default, where snapshots are set
up). Snapshots hold the system only: your home folder and its files are never rolled back.

1. **Try it.** Restart, press **Esc** as the computer starts to show the boot menu, open the snapshots and pick the one
   named `auto-update` with the date and time before the update. The system starts as it was then. It's for checking,
   or for getting by: whatever changes in the system meanwhile is kept in memory only (nothing is updated there), and
   the next normal start is the updated system again.
2. **Keep it.** Started from that snapshot, open **Btrfs Assistant** from the app menu (it asks for your password), go
   to **Snapper**, **Browse/Restore**, pick the same snapshot and click **Restore**, then restart. The system is now
   the snapshot's for good.

The same update is downloaded again at the next start, unless a fix has come out meanwhile. If it breaks the same
thing again, [open an issue](https://github.com/CrimzoAgra/agros/issues).
