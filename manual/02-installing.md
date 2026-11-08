# Installing

AgrOS installs from an ISO, using CachyOS's installer.

## 1. Get the ISO

There are no ready-made downloads yet: build the ISO from [agros-iso](https://github.com/CrimzoAgra/agros-iso) on any
Arch or CachyOS machine:

```bash
git clone https://github.com/CrimzoAgra/agros-iso && cd agros-iso
sudo pacman -S archiso mkinitcpio-archiso git squashfs-tools grub --needed
sudo ./buildiso.sh -p desktop -v -w
```

The ISO ends up in `out/`.

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

## Already running CachyOS or Arch?

You can add AgrOS to an existing system instead. Add its repo to `/etc/pacman.conf`:

```ini
[agros]
Server = https://crimzoagra.github.io/agros/$arch
```

Then run `sudo pacman -Sy agros-keyring agros-desktop`. New accounts get AgrOS's settings. For your current account,
copy `/etc/skel` into your home folder.

Next: [Your first login](03-first-login.md)
