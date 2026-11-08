# Troubleshooting

## Something stopped working

Run `dotfiles-check` in a terminal. It checks the desktop's settings, AgrOS's changes, and that everything that should be
running is, and tells you what's wrong. It also runs by itself 30 seconds after you log in, and only sends a
notification when it finds something.

## The bar or widgets look wrong

Press **Ctrl+Super+Alt+R** to restart the shell.

## The login screen doesn't appear

Press **Ctrl+Alt+F2**, log in with your username and password, run `sudo login-reset`, then restart.

## An update broke something

Restart, press **Esc** as the computer starts, and pick the snapshot from before the update. See
[Updates](12-updates.md).

## A first-login step failed

AgrOS Welcome tries again at your next login. You can also run `agros-welcome` yourself. Its log is in
`~/.local/state/agros/welcome.log`.

## Running AgrOS in a virtual machine

AgrOS works in VMware. The desktop draws on the CPU there (VMware's virtual graphics card can't draw it), so it's
slower than on real hardware, and the CPU works harder whenever something animates.

## Still stuck?

[Open an issue](https://github.com/CrimzoAgra/agros/issues).
