# Coming from Windows

Most things work the way you're used to. A few are different.

| On Windows | On AgrOS |
|---|---|
| Start menu | **Super**: the app menu (type to search) |
| Taskbar | The **bar** on the left: the dock shows pinned and open apps |
| Alt+Tab | **Alt+Tab**: the same, with live previews |
| Task Manager (Ctrl+Shift+Esc) | **Ctrl+Shift+Esc** opens btop |
| Win+D, virtual desktops | **Workspaces**: Super+1...0 jumps to one (see [Windows and workspaces](07-windows-and-workspaces.md)) |
| Snipping Tool (Win+Shift+S) | **Print** selects an area; **Super+Shift+S** freezes the screen first |
| Clipboard history (Win+V) | **Super+V** |
| Emoji panel (Win+.) | **Super+.** |
| Lock (Win+L) | **Super+L** |
| Ctrl+Alt+Del | **Ctrl+Alt+Del**: log out, restart, shut down |
| Settings | **Desktop Settings** in the app menu (see [Settings](11-settings.md)) |
| Windows Update | Automatic, at boot and shutdown (see [Updates](12-updates.md)) |

## Things that are different

- **Tiling, if you want it.** Windows float like on Windows. Press **Super+Alt+Space** to switch every window to tiling,
  where they fill the screen side by side, and again to switch back.
- **Installing apps** goes through the package manager rather than downloading installers. Most apps you'll want are
  already installed (see [Apps](08-apps.md)). For others, ask the terminal: `paru -S <name>` searches Arch's repos and
  the AUR. AppImages open with a double-click and install themselves.
- **Drives** have no letters: your files are in your home folder (`/home/<you>`), and USB drives appear in the file
  manager's sidebar.
