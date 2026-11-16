# Installing

AgrOS installs from an ISO, using CachyOS's installer.

## 1. Get the ISO

**[Download the latest AgrOS ISO](https://pub-f1a3a482900748e8b69cd81361ab96e1.r2.dev/agros-latest.iso)** (about
2.1 GB; always the newest. Slow? The same ISO on [SourceForge](https://sourceforge.net/projects/agros-iso/files/latest/download)). To check the download, or build the ISO yourself, see
[agros-iso](https://github.com/CrimzoAgra/agros-iso).

## 2. Put it on a USB stick

Use [balenaEtcher](https://etcher.balena.io) (Windows, Mac or Linux) or [Rufus](https://rufus.ie) (Windows). Then
boot the computer from the stick: usually F11, F12 or Esc at power-on opens the boot menu.

_Turn off Secure Boot in the BIOS first._ CachyOS, and so AgrOS, doesn't boot with it on.

## 3. Run the installer

On the live desktop, click **Launch installer**. It needs an internet connection: AgrOS's packages are downloaded
during the install, so you get the latest versions.

1. Pick your language, location and keyboard.
2. Pick the drive. **Erase disk** takes over the whole drive; to keep Windows, choose **Install alongside** or
   **Manual partitioning**.
3. Create your user and password.
4. Click **Install**. There's no desktop to choose: AgrOS is the desktop.

When it's done, restart and take the USB stick out.

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

New accounts get AgrOS's settings. For your current account, copy `/etc/skel` into your home folder.

Next: [Your first login](03-first-login.md)
