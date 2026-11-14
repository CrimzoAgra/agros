# Troubleshooting

## Something stopped working

Run `dotfiles-check` in a terminal. It checks the desktop's settings, AgrOS's changes, and that everything that should be
running is, and tells you what's wrong. It also runs by itself 30 seconds after you log in, and only sends a
notification when it finds something.

## The bar or widgets look wrong

Press **Ctrl+Super+Alt+R** to restart the shell.

## The login screen doesn't appear

Press **Ctrl+Alt+F2**, log in with your username and password, run `sudo login-reset`, then restart. That gives you
a plain text login; `sudo login-reset --back` brings the AgrOS login screen back once it works again.

## An update broke something

Restart, press **Esc** as the computer starts, and pick the snapshot from before the update. See
[Updates](12-updates.md).

## Something went wrong while the computer started or shut down

Starting and shutting down show only the splash, no text. What happened is kept in the system's log: `journalctl -b
-p err` lists this start-up's errors, `journalctl -b -1 -p err` the last session's (its shutdown too). Pressing **Esc**
on the splash shows the text as it goes.

## A first-login step failed

AgrOS Welcome tries again at your next login. You can also run `agros-welcome` yourself. Its log is in
`~/.local/state/agros/welcome.log`.

## The wired network keeps dropping

AgrOS watches wired network cards. When one loses its connection for a moment again and again (3 times in 2 minutes),
it changes one thing on that card, tells you in a notification, and waits to see if that was enough:

1. It turns off the card's power saving (Energy-Efficient Ethernet), which often causes this.
2. If it still drops and the card runs faster than 1 Gbps (2.5 Gbps cards), it makes the card connect at 1 Gbps.
3. If it still drops, it tells you once to check the cable, the router or switch, and its port: there's nothing more
   to change on the computer.

Each change is saved in the card's network profile, so it stays after a restart, and is never made twice. A cable
pulled out isn't counted, and Wi-Fi and virtual cards (VPNs, VMware's) are left alone. The notification gives the
command that undoes the change; you can also run it later, with the profile's ID from `nmcli connection show`:

- Power saving back: `nmcli connection modify uuid <ID> ethtool.eee-enabled ""` (back on after a restart)
- All speeds back: `nmcli connection modify uuid <ID> 802-3-ethernet.speed "" 802-3-ethernet.duplex ""`, then
  `nmcli connection up uuid <ID>`

A card with no network profile gets the change until you undo it with `sudo rm /var/lib/agros/wired-link/<its
address>` and a restart (the notification names the file). A new card starts fresh. To turn the watch off:
`sudo systemctl disable --now agros-wired-link`.

## Running AgrOS in a virtual machine

AgrOS works in VMware. The desktop and apps draw on VMware's virtual graphics card (`agros-vmware`), which is still
slower than real hardware: turn on **Accelerate 3D graphics** in the VM's display settings.

## Still stuck?

[Open an issue](https://github.com/CrimzoAgra/agros/issues).
