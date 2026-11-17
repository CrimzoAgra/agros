# Installing

AgrOS installs from an ISO, using CachyOS's installer.

## 1. Get the ISO

**[Download the latest AgrOS ISO](https://pub-f1a3a482900748e8b69cd81361ab96e1.r2.dev/agros-latest.iso)** (about
2.1 GB; always the newest. Slow? The same ISO on
[SourceForge](https://sourceforge.net/projects/agros-iso/files/latest/download)). To check the download, see
[Downloading and checking it](https://github.com/CrimzoAgra/agros-iso/blob/main/manual/03-building.md#downloading-and-checking-it);
to build the ISO yourself, [agros-iso](https://github.com/CrimzoAgra/agros-iso).

## 2. Put it on a USB stick

Use [balenaEtcher](https://etcher.balena.io) (Windows, Mac or Linux) or [Rufus](https://rufus.ie) (Windows; when it
asks, pick **DD Image mode**: in ISO mode the stick doesn't boot). Everything on the stick is erased. Then boot the
computer from the stick: usually F11, F12 or Esc at power-on opens the boot menu.

_Turn off Secure Boot in the BIOS first._ CachyOS, and so AgrOS, doesn't boot with it on.

## 3. Run the installer

The installer opens by itself once the live desktop is up (give it a minute or two). Closed it? Open it again with
**Install AgrOS** in the Super menu. It needs an internet connection: AgrOS's packages are downloaded during the
install, so you get the latest versions. Not connected yet? Connect (Wi-Fi from the bar) and it carries on by itself;
after 5 minutes it gives up, and you open it again.

1. Pick your language, location and keyboard.
2. Pick the drive. **Erase disk** takes over the whole drive. To keep Windows, see [Keeping Windows](#keeping-windows)
   below.
3. Create your user and password. This account is the computer's administrator: it installs updates and apps.
4. Click **Install**. There's no desktop to choose: AgrOS is the desktop.

When it's done, restart and take the USB stick out.

## Keeping Windows

AgrOS can sit beside Windows on the same drive. Before you start, in Windows:

- **Back up** what matters: the installer shrinks Windows' partition, and a mistake there can't be undone.
- **Turn off Fast Startup** (Control Panel, Power Options, *Choose what the power buttons do*). With it on, Windows
  never fully shuts down, and its drive can't be opened safely from AgrOS.
- **BitLocker or Device encryption on?** The installer can't shrink an encrypted partition. Shrink it in Windows
  instead (Disk Management, right-click **C:**, **Shrink Volume**, by 25 GB or more), and keep your BitLocker recovery
  key at hand: with Secure Boot off, Windows asks for it once, and started from AgrOS's boot menu it can ask every
  time. Start it from the computer's own boot menu instead (usually F11 or F12 at power-on).

In the installer, choose **Install alongside** and drag the divider to share the drive (AgrOS needs at least 20 GB),
or, for space you freed in Windows, **Replace a partition** and click the free space. AgrOS uses the small boot
partition Windows already has.

Afterwards AgrOS starts straight away, with no menu. To start Windows, press **Esc** as the computer starts: the
boot menu lists it (and the snapshots). Windows' clock an hour off after using AgrOS? See
[Troubleshooting](14-troubleshooting.md#windows-clock-is-wrong-after-using-agros).

## Already running CachyOS?

You can add AgrOS to an existing CachyOS system instead (only CachyOS: AgrOS needs packages from CachyOS's own repos,
such as its gaming packages, paru and VSCodium; on Arch, add CachyOS's repos first). Add AgrOS's repo to
`/etc/pacman.conf`:

```ini
[agros]
Server = https://crimzoagra.github.io/agros/$arch
```

Then trust AgrOS's signing key (pacman refuses the repo until you do), and install:

```bash
curl -fsSL https://raw.githubusercontent.com/CrimzoAgra/agros/main/ci/agros.asc | sudo pacman-key --add -
sudo pacman-key --lsign-key BFE9289F7759E521AE60CFCD23B6096B42D05E1E
sudo pacman -Syu agros-keyring agros-desktop
```

Installing it adds the repo's second server (a mirror) and requires its database to be signed, and AgrOS's login
screen takes over from the one you had: restart to get it. New accounts get AgrOS's settings (see
[Another person on this PC](13-accounts.md#another-person-on-this-pc)). To give them to your current account, copy
them over your own (back up `~/.config` first: files with the same name are replaced), then log out and back in:

```bash
cp -r /etc/skel/. ~/
```

Next: [Your first login](03-first-login.md)
