# Updates

You don't have to think about updates.

- **At every boot**, AgrOS downloads updates for the system, your apps, Flatpaks and AppImages.
- **At shutdown**, it installs them, after taking a snapshot of the system first. Updates never get installed under a
  running desktop, where a new graphics driver or kernel can break things until you restart.
- **Every 6 hours** it checks again. When something's waiting, a notification offers **Update now**.

## The Updates app

Open **Updates** from the app menu, or click the button next to the app menu's search bar. It lists what's waiting, app
by app, with old and new versions. **Update all** installs everything now, including AUR apps, which aren't built at
boot.

In a terminal, `update-apps` does the same and shows what each AUR package's build script changed before building it.

## If an update goes wrong

The system takes a snapshot before every update. To go back, restart, press **Esc** as the computer starts to show the
boot menu, and pick a snapshot.
