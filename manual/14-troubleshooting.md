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

## Running AgrOS in a virtual machine

AgrOS works in VMware. The desktop and apps draw on VMware's virtual graphics card (`agros-vmware`), which is still
slower than real hardware: turn on **Accelerate 3D graphics** in the VM's display settings.

## Still stuck?

[Open an issue](https://github.com/CrimzoAgra/agros/issues).
