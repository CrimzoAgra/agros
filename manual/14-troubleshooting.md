# Troubleshooting

## Something stopped working

Run `dotfiles-check` in a terminal. It checks the desktop's settings, AgrOS's changes, and that everything that should
be running is, and tells you what's wrong. It also runs by itself 30 seconds after you log in, and only sends a
notification when it finds something.

## The bar or widgets look wrong

Press **Ctrl+Super+Alt+R** to restart the shell.

## The bar came back without the dock

If AgrOS's changes to the shell stop it from loading (after an update to Caelestia or Quickshell), it starts without
them rather than not at all: the bar as Caelestia has it, no dock, and a notification says so. `dotfiles-check` says
why. Your changes are tried again at your next login and after each update.

## The login screen doesn't appear

Press **Ctrl+Alt+F2**, log in with your username and password, run `sudo login-reset`, then restart. That gives you
a plain text login; `sudo login-reset --back` brings the AgrOS login screen back once it works again.

## An update broke something

Restart, press **Esc** as the computer starts, and pick the snapshot from before the update. That's for now: to keep
it, see [If an update goes wrong](12-updates.md#if-an-update-goes-wrong).

## Something went wrong while the computer started or shut down

Starting and shutting down show only the splash, no text. What happened is kept in the system's log: `journalctl -b
-p err` lists this start-up's errors, `journalctl -b -1 -p err` the last session's (its shutdown too). Pressing **Esc**
on the splash shows the text as it goes.

## Windows' clock is wrong after using AgrOS

Windows keeps the computer's clock in local time, AgrOS (like every Linux) in UTC, so each moves it by your time zone.
Have Windows use UTC too: in Windows, open **Terminal (Admin)** and run this, then restart.

```
reg add "HKLM\System\CurrentControlSet\Control\TimeZoneInformation" /v RealTimeIsUniversal /d 1 /t REG_DWORD /f
```

## A first-login step failed

AgrOS Welcome tries again at your next login. You can also run `agros-welcome` yourself. Its log is in
`~/.local/state/agros/welcome.log`.

## Running AgrOS in a virtual machine

AgrOS works in VMware. The desktop and apps draw on VMware's virtual graphics card (`agros-vmware`), which is still
slower than real hardware: turn on **Accelerate 3D graphics** in the VM's display settings.

If the VM's window freezes for about a second while you drag a window against the screen's edge (the snap preview
showing), that's VMware's mouse: AgrOS holds the pointer inside Caelestia's border while you drag, and with VMware's
usual mouse that makes VMware move your own computer's pointer too, which stalls it. Give the VM an ordinary mouse
instead: with it shut down, add these lines to its `.vmx` file. You then click into the VM to use it, and press
Ctrl+Alt to get your pointer back.

```
vmmouse.present = "FALSE"
mouse.vusb.enable = "TRUE"
mouse.vusb.useBasicMouse = "TRUE"
```

## Still stuck?

[Open an issue](https://github.com/CrimzoAgra/agros/issues).
