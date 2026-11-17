# Gaming

AgrOS comes with CachyOS's gaming packages: Steam, Proton, Wine, MangoHud, Gamescope and GOverlay.

There's one Wine, CachyOS's: the `wine` command, `winetricks` and Lutris's system Wine all use it. A Windows program
you double-click (an `.exe`) opens in Faugus Launcher, which runs it with Proton. If a program needs .NET or Internet
Explorer's engine, Wine offers to download them the first time.

## Playing a Windows game

Windows games run through Proton, without you setting anything up:

- **On Steam**, install and play as on Windows. A game Steam hasn't marked as working on Linux may show no Play
  button: in its **Properties**, **Compatibility**, tick **Force the use of a specific Steam Play compatibility
  tool**.
- **On another store** (EA, Ubisoft, Epic, GOG, Battle.net, Rockstar), use Lutris, below.
- **A game with its own installer** (an `.exe`): double-click it, and it runs through Proton in Faugus Launcher. Once
  it's installed, add the game in **Faugus Launcher** (in the app menu) to start it from there.

Most games run. Those whose anti-cheat refuses Linux (Valorant, Fortnite and some other online games) don't, whatever
you try: look a game up on [ProtonDB](https://www.protondb.com) before you buy it.

## Lutris: one library for every store

Lutris lists every game you own, on every store, in one place: Steam, EA, Ubisoft, Epic, GOG, Battle.net and
Rockstar. Installed games come first, the rest below; opening one you haven't installed installs it through its store.

The store launchers (EA app, Ubisoft Connect, Battle.net, Epic, GOG Galaxy, Rockstar) are under **Launchers** in
Lutris's sidebar: open one there to install it. To add Battle.net or Rockstar games, sign in to them from Lutris's
sources.

Lutris starts in the tray when you log in.

## While you play

- **Sound follows focus**: a game's sound mutes while you're in another window, and comes back when you return.
- **Alt+Tab** away from a fullscreen game minimises it, like on Windows.
- **Store launchers tidy up**: when you close a game, its launcher closes too (after it has uploaded your saves), and
  so does Steam if its window wasn't open.
- When a game wants your attention, you get a notification. Click it to go back.
- Updates and background checks wait until you've finished playing.

## MangoHud

To show FPS and temperatures in a game, add `mangohud %command%` to its launch options in Steam, or turn MangoHud
on in Lutris's game options. GOverlay sets up what it shows.
