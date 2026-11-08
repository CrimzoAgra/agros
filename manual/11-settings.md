# Settings

## Desktop Settings

Open **Desktop Settings** from the app menu. Changes apply straight away.

- **Windows**: floating or tiling, focus on click or hover, title bars, mouse acceleration and DPI
- **Features**: low input lag in games, how games and their launchers behave, and each of AgrOS's changes to the
  desktop and Lutris, which you can turn off one by one
- **Startup**: which apps start when you log in
- **Keyboard**: every shortcut. Click **+** next to one and press the new keys

## Caelestia's own settings

The quick-settings panel (**Super+K**) and the dashboard hold sound, network, Bluetooth, the wallpaper and the
colour scheme.

## Screens

Every screen runs at its own resolution and its fastest refresh rate, without you doing anything. To set a screen's
resolution or position by hand, see [Screens](../docs/how-it-works.md#screens-and-colours).

## Keyboard layout

Your layout is the one you picked in the installer. To change it: `sudo localectl set-x11-keymap <layout>`, for example
`pt` or `us`, then log out and back in.
