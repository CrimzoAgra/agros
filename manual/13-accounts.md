# Your accounts and the pen drive

AgrOS holds none of your personal data, so a fresh install starts signed out of everything. To avoid signing in to every
app again, carry your logins on a pen drive.

## Saving them (before reinstalling)

Plug in a USB stick and run:

```bash
agros-personal --save
```

Close your apps first. It saves your logins into one file on the stick, encrypted with a passphrase you choose. Without
that passphrase, a lost stick gives nothing away. Save again every so often, because logins expire.

It covers your LibreWolf profile (bookmarks, passwords, extensions), Discord, Spotify, Nuvio, Proton VPN, Steam,
Lutris's stores and the launchers you installed in it (Epic, EA, Ubisoft...: they come back installed and signed in),
VSCodium's extension data, all of Claude Code (login, settings, sessions, memories, plugins), GitHub and the weather
widget's town. Your VSCodium extensions themselves are installed by AgrOS. With launchers installed the file is a few
GB, so use a stick with room for it.

## Restoring them (after installing)

Click **Restore my accounts** in the notification after your first login, or run `agros-personal`. Plug in the stick
and type your passphrase. Everything goes straight back where it belongs, and anything it replaces is backed up first.
Capri, the desktop companion, installs right after: her code is in a private GitHub repo, so she installs only for a
GitHub login that can read it. If your GitHub login only works once you've logged out and in again, she installs at
that next login. Lutris and Proton VPN, open in the tray as they are after logging in (Proton VPN if you set it to
start then), are closed for it (it asks first).

No stick? `agros-personal` opens each app for you to sign in instead.

## Another person on this PC

Each person gets an account of their own, with their own desktop, settings, apps' logins and pen drive. There's no
settings page for it yet: in a terminal, as the administrator (the account made in the installer), run

```bash
sudo useradd -m -G wheel <name>   # an administrator; leave out "-G wheel" for an account that can't change the system
sudo passwd <name>
```

The login screen then lists both accounts: click the person button next to the session's to pick one. The new
account's first login runs AgrOS Welcome for it, as yours did. Updates are the whole computer's: they happen at boot
and shutdown whoever logs in, and only administrators are offered **Update now**, the Updates app's **Update all**
and the hardware apps.
