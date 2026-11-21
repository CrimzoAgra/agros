"""lutris-overlay: services_on_desktop (patch.py). Copied into the patched Lutris as lutris/util/wine/services.py

Wine runs a prefix's Windows services on a hidden desktop of their own with no display driver, and what a service
starts stays there. A launcher whose updater is a service (Epic's EpicGamesUpdater, EA's background service...) then
starts the launcher, or its update step, without Vulkan: DXVK can't make its Vulkan instance there and the launcher
crashes in dxgi.dll, so its update never finishes and it asks again at every start. Wine puts a service flagged
"interactive" (SERVICE_INTERACTIVE_PROCESS) on the user's desktop instead, where Vulkan works: every program's own
service is flagged so before each start (Wine's own, under C:\\windows, left as they are)

And Epic's overlay (Epic Online Services, which its launcher installs and puts back on every update) turned off before
each start, as Heroic turns it off: its path taken out of the registry, so no game loads it. Hooked into a game's
Direct3D under DXVK it left the game black, and the mouse dead in it (Batman: Arkham Knight)

And Wine's standalone tray window off (user.reg: HKCU\\Software\\Wine\\Explorer, ShowSystray=0): with no XEmbed tray to
dock in (Hyprland has none, Wine's Wayland driver none either) a program's tray icon showed as a small untitled window
of its own (class steam_app_default) beside Epic and every game started through it. Its icons had nowhere to go anyway
(Epic's menu is epic-tray's, in the shell)"""

import os
import re
import time

# A service's key in system.reg, with its values: up to the next key
_SERVICE = re.compile(r"^\[System\\\\ControlSet001\\\\Services\\\\[^\\\]]+\][^\n]*\n(?:(?!\[)[^\n]*\n?)*", re.M)
_IMAGE = re.compile(r'^"ImagePath"=(?:str\(2\):)?"(.*)"$', re.M)
_TYPE = re.compile(r'^"Type"=dword:([0-9a-fA-F]{8})$', re.M)
_WINE = re.compile(r'^(\\")?[a-z]:\\\\windows\\\\', re.I)
OWN_PROCESS, SHARE_PROCESS, INTERACTIVE = 0x10, 0x20, 0x100
# Epic Online Services' key (64- and 32-bit views), with its values: up to the next key
_EOS = re.compile(r"^\[Software\\\\(?:Wow6432Node\\\\)?Epic Games\\\\EOS\][^\n]*\n(?:(?!\[)[^\n]*\n?)*", re.M)
_OVERLAY = re.compile(r'^"OverlayPath"=[^\n]*\n?', re.M)
# Wine's Explorer key in user.reg (its own, not Explorer\\Desktops), with its values: up to the next key
_EXPLORER = re.compile(r"^\[Software\\\\Wine\\\\Explorer\][^\n]*\n(?:(?!\[)[^\n]*\n?)*", re.M)
_SYSTRAY = re.compile(r'^"ShowSystray"=[^\n]*\n?', re.M)


def _flag(match):
    block = match.group(0)
    image, kind = _IMAGE.search(block), _TYPE.search(block)
    # (drivers and services already flagged, or with flags of their own: left)
    if not image or not kind or _WINE.match(image.group(1)) or int(kind.group(1), 16) not in (OWN_PROCESS, SHARE_PROCESS):
        return block
    return block[:kind.start(1)] + f"{int(kind.group(1), 16) | INTERACTIVE:08x}" + block[kind.end(1):]


def _no_systray(text):
    key = _EXPLORER.search(text)
    if key and '"ShowSystray"=dword:00000000' in key.group(0):
        return text
    if not key:  # (as Wine writes a key: its time after the name)
        return text.rstrip("\n") + f'\n\n[Software\\\\Wine\\\\Explorer] {int(time.time())}\n"ShowSystray"=dword:00000000\n'
    block = _SYSTRAY.sub("", key.group(0)).rstrip("\n") + '\n"ShowSystray"=dword:00000000\n'
    return text[:key.start()] + block + ("\n" if key.end() < len(text) else "") + text[key.end():]


def services_on_desktop(prefix):
    """Flag the prefix's own (non-Wine) services interactive, turn Epic's overlay and Wine's tray window off. Written only when one changes, and whole (a new file
    swapped in): Wine reading it at that moment gets the old one or the new one. (A wineserver of the prefix already
    running keeps the old values in memory and can write them back: flagged again at the next start)"""
    _edit(os.path.join(prefix, "system.reg"), lambda text: _EOS.sub(lambda m: _OVERLAY.sub("", m.group(0)), _SERVICE.sub(_flag, text)))
    _edit(os.path.join(prefix, "user.reg"), _no_systray)


def _edit(path, change):
    try:
        with open(path, encoding="utf-8", errors="surrogateescape") as f:
            text = f.read()
    except OSError:
        return  # (no prefix yet: Wine makes it, and the next start edits it)
    new = change(text)
    if new == text:
        return
    tmp = path + ".lutris-overlay"
    try:
        with open(tmp, "w", encoding="utf-8", errors="surrogateescape") as f:
            f.write(new)
        os.replace(tmp, path)
    except OSError:  # (a full disk, a read-only prefix: the launch goes on as before)
        try:
            os.remove(tmp)
        except OSError:
            pass
