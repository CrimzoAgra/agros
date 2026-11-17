# Settings

## Desktop Settings

Open **Desktop Settings** from the app menu. Changes apply straight away. The search box above the pages finds a
setting on any page.

- **Windows**: floating or tiling, focus on click or hover, cascading new windows, title bars
- **Mouse and keyboard**: mouse DPI, acceleration and speed, natural scrolling, the touchpad (tap to click, scrolling
  speed), key repeat, and the keyboard layout (it asks for your password: it's the whole PC's, the login screen's too)
- **Screens**: each screen's resolution and refresh rate, scale and position, which one is the main screen, and turning
  one off
- **Look**: the wallpaper, the colour scheme, light or dark, the shell's fonts and text size, the gaps between windows,
  borders, rounded corners and transparency
- **Bar**, **Panels**, **Launcher**, **Notifications**, **Lock and session**, **Region and services**: what the bar
  shows, the dashboard, sidebar and quick settings, the Super menu, notifications, the lock screen and when the PC
  sleeps, the weather place, clock and units
- **Features**: low input lag in games, how games and their launchers behave, and each of AgrOS's changes to the
  desktop and Lutris, which you can turn off one by one
- **Startup**: which apps start when you log in
- **Shortcuts**: every shortcut. Click **+** next to one and press the new keys. One used twice shows in red. The
  fixed ones at the bottom can't be changed, but show so you don't pick their keys
- **All Caelestia options**: every option the shell has, by area: click an area to open it

A setting you've changed has a ↺ button that puts it back as AgrOS set it; not the ones kept by the system or by
Caelestia (the window mode, the keyboard layout, the wallpaper and colours): pick those again. A note under a setting
says where AgrOS relies on it.

## Caelestia's own settings

The quick-settings panel (the screen's bottom-right corner, or **Super+K** with the other panels) holds sound,
network and Bluetooth.

Caelestia's Settings app, under **Language & region**, has the weather location too. Turn on **Set the time
zone automatically** and the time zone follows the weather location (or your internet connection, when that's
automatic), set at every login without asking for your password.

## Night light

After sunset the screens turn warmer by themselves, from where your PC finds you on the network. To set your location
or the colours yourself, see `~/.config/gammastep/config.ini`.

## Screens

Every screen runs at its own resolution and its fastest refresh rate, without you doing anything. To change that, use
the **Screens** page of Desktop Settings. Leave a screen's position empty to have it to the right of the others; don't
place one left of or above another at 0x0, as Proton games then aim the mouse somewhere else than the pointer.

## Keyboard layout

Your layout is the one you picked in the installer. Change it under **Mouse and keyboard** in Desktop Settings: `pt`,
`us`, or several separated by commas.
