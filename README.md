<p align="center">
  <picture>
    <source media="(prefers-reduced-motion: reduce)" srcset="docs/images/agros-banner.svg">
    <img src="docs/images/agros-banner-animated.png" alt="AgrOS" width="420">
  </picture>
</p>

# AgrOS

AgrOS is a ready-to-use Linux desktop built on [CachyOS](https://cachyos.org). Install it from the ISO and everything is
already set up: the [Hyprland](https://hyprland.org) desktop with the [Caelestia](https://github.com/caelestia-dots/shell)
shell, a dock, desktop widgets, your apps, gaming, and the settings that tie them together. There's no setup script to
run afterwards.

It's made for gaming and everyday use, and to feel familiar if you're coming from Windows: windows float by default,
Alt+Tab works the way you expect, and every app is listed next to the Windows app it replaces.

## Download

<p align="center">
  <a href="https://sourceforge.net/projects/agros-iso/files/latest/download"><img alt="Download the AgrOS ISO" src="https://img.shields.io/badge/Download-AgrOS%20ISO-4c6ef5?style=for-the-badge"></a>
  <br>
  <img alt="Latest ISO" src="https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fsourceforge.net%2Fprojects%2Fagros-iso%2Fbest_release.json&query=%24.release.date&label=latest%20ISO&color=4c6ef5">
</p>

The ISO is about 3.7 GB and always the newest: a new one is built and published by itself after each change. Put it
on a USB stick and install: [Installing](manual/02-installing.md). Earlier ISOs, with their checksums and signatures:
[all downloads](https://sourceforge.net/projects/agros-iso/files/iso/).

## The AgrOS Manual

- [Welcome to AgrOS](manual/01-welcome.md)

**Getting started**

- [Installing](manual/02-installing.md)
- [Your first login](manual/03-first-login.md)
- [Coming from Windows](manual/04-coming-from-windows.md)

**Using it**

- [The desktop](manual/05-the-desktop.md)
- [Keyboard shortcuts](manual/06-shortcuts.md)
- [Windows and workspaces](manual/07-windows-and-workspaces.md)
- [Apps](manual/08-apps.md)
- [Gaming](manual/09-gaming.md)
- [The terminal](manual/10-terminal.md)

**Looking after it**

- [Settings](manual/11-settings.md)
- [Updates](manual/12-updates.md)
- [Your accounts and the pen drive](manual/13-accounts.md)
- [Troubleshooting](manual/14-troubleshooting.md)

**For developers**

- [How AgrOS works](docs/how-it-works.md): the packages, the repo's layout, every script and the tests

## License

AgrOS is released under the [GPL-3.0-or-later](LICENSE). It builds on Caelestia, hyprland-plugins and Lutris; see
[credits](docs/how-it-works.md#credits-and-licenses).
