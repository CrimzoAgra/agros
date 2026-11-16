<p align="center">
  <picture>
    <source media="(prefers-reduced-motion: reduce)" srcset="docs/images/agros-banner.svg">
    <img src="docs/images/agros-banner-animated.png" alt="AgrOS" width="420">
  </picture>
</p>

# AgrOS

AgrOS is a ready-to-use Linux desktop for gaming and everyday use, built on [CachyOS](https://cachyos.org). Install it
from the ISO and everything is already set up: the [Hyprland](https://hyprland.org) desktop with the
[Caelestia](https://github.com/caelestia-dots/shell) shell, a dock, desktop widgets, your apps and gaming. There's no
setup script to run afterwards. Coming from Windows? Windows float, Alt+Tab works as you expect, and every app is listed
next to the Windows app it replaces.

Read more in [Welcome to AgrOS](manual/01-welcome.md).

## Download

<p align="center">
  <a href="https://pub-f1a3a482900748e8b69cd81361ab96e1.r2.dev/agros-latest.iso"><img alt="Download the AgrOS ISO" src="https://img.shields.io/badge/Download-AgrOS%20ISO-4c6ef5?style=for-the-badge"></a>
  <br>
  <img alt="Latest ISO" src="https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fsourceforge.net%2Fprojects%2Fagros-iso%2Fbest_release.json&query=%24.release.date&label=latest%20ISO&color=4c6ef5">
</p>

About 3.6 GB, and always the newest: a new ISO is built and published by itself after each change. Check it with its
[.sha256](https://pub-f1a3a482900748e8b69cd81361ab96e1.r2.dev/agros-latest.iso.sha256) and
[.sig](https://pub-f1a3a482900748e8b69cd81361ab96e1.r2.dev/agros-latest.iso.sig), put it on a USB stick and see
[Installing](manual/02-installing.md). Slow, or want an earlier one? Every ISO, with its checksum and signature, is on
[SourceForge](https://sourceforge.net/projects/agros-iso/files/iso/).

## The AgrOS Manual

The manual lives in [`manual/`](manual/).

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

## How updates stay safe

AgrOS is built on others' work: Arch and CachyOS (the system), the AUR (Caelestia, Quickshell and the other apps AgrOS
builds for you) and CachyOS's ISO (what the live USB is made from). Every change from them is checked before it reaches
you. When one breaks something, only that piece waits; the rest keeps updating. (Also in the manual:
[How updates stay safe](manual/12-updates.md#how-updates-stay-safe).)

| When upstream... | AgrOS... | Your machine... |
|---|---|---|
| updates Hyprland or its libraries | tests its config, title bar plugin and shell against it every day, and approves a version that passes | takes only approved Hyprland versions; meanwhile everything else updates |
| ships an Arch update that breaks AgrOS's tests | finds it by running the tests again on Arch as of the last good day | keeps the Hyprland that works |
| changes an AUR app so it no longer builds (or AgrOS's fix to it no longer fits) | keeps the published package | keeps the version that works |
| changes an AUR app so the tests fail | swaps the new build back for the published one | keeps the version that works |
| (AgrOS's own change fails its tests) | publishes nothing | doesn't change |
| changes its ISO | merges it into AgrOS's ISO by itself each day, if it merges cleanly, brings back nothing AgrOS removed, adds no KDE, keeps AgrOS's installer, and the ISO still builds | isn't affected: installed machines update from the repos above |
| changes its ISO in a way that can't be merged by itself | opens a pull request saying what changed and why | isn't affected; the ISO stays as it is until it's merged |

**When you're told:** by email, through GitHub issues that mention you. One issue, labelled `held`, says what's held
back and why, and closes by itself once everything goes out again. Every Friday at 17:00 Lisbon time a status issue
says "Nothing broke this week" or what needs a look: a build failing, something held, a CachyOS pull request waiting, or
Arch's newest Hyprland not approved yet.

**What needs you:** only a CachyOS pull request (resolve its conflict and merge it), or something held for more than a
few days (an upstream change AgrOS's own code has to be adapted to). Everything else sorts itself out. The details:
[Keeping itself up](docs/how-it-works.md#keeping-itself-up) and [the upstream gate](docs/how-it-works.md#updates-and-system).

## License

AgrOS is released under the [GPL-3.0-or-later](LICENSE). It builds on Caelestia, hyprland-plugins and Lutris; see
[credits](docs/how-it-works.md#credits-and-licenses).
