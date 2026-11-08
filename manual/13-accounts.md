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
Lutris's stores, Claude Code, GitHub and the weather widget's town.

## Restoring them (after installing)

Click **Restore my accounts** in the notification after your first login, or run `agros-personal`. Plug in the stick
and type your passphrase. Everything goes straight back where it belongs, and anything it replaces is backed up first.

No stick? `agros-personal` opens each app for you to sign in instead.
