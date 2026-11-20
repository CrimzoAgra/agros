"""lutris-overlay: services_on_desktop (patch.py). Copied into the patched Lutris as lutris/util/wine/services.py

Wine runs a prefix's Windows services on a hidden desktop of their own with no display driver, and what a service
starts stays there. A launcher whose updater is a service (Epic's EpicGamesUpdater, EA's background service...) then
starts the launcher, or its update step, without Vulkan: DXVK can't make its Vulkan instance there and the launcher
crashes in dxgi.dll, so its update never finishes and it asks again at every start. Wine puts a service flagged
"interactive" (SERVICE_INTERACTIVE_PROCESS) on the user's desktop instead, where Vulkan works: every program's own
service is flagged so before each start (Wine's own, under C:\\windows, left as they are)"""

import os
import re

# A service's key in system.reg, with its values: up to the next key
_SERVICE = re.compile(r"^\[System\\\\ControlSet001\\\\Services\\\\[^\\\]]+\][^\n]*\n(?:(?!\[)[^\n]*\n?)*", re.M)
_IMAGE = re.compile(r'^"ImagePath"=(?:str\(2\):)?"(.*)"$', re.M)
_TYPE = re.compile(r'^"Type"=dword:([0-9a-fA-F]{8})$', re.M)
_WINE = re.compile(r'^(\\")?[a-z]:\\\\windows\\\\', re.I)
OWN_PROCESS, SHARE_PROCESS, INTERACTIVE = 0x10, 0x20, 0x100


def _flag(match):
    block = match.group(0)
    image, kind = _IMAGE.search(block), _TYPE.search(block)
    # (drivers and services already flagged, or with flags of their own: left)
    if not image or not kind or _WINE.match(image.group(1)) or int(kind.group(1), 16) not in (OWN_PROCESS, SHARE_PROCESS):
        return block
    return block[:kind.start(1)] + f"{int(kind.group(1), 16) | INTERACTIVE:08x}" + block[kind.end(1):]


def services_on_desktop(prefix):
    """Flag the prefix's own (non-Wine) services interactive. Written only when one changes, and whole (a new file
    swapped in): Wine reading it at that moment gets the old one or the new one. (A wineserver of the prefix already
    running keeps the old values in memory and can write them back: flagged again at the next start)"""
    path = os.path.join(prefix, "system.reg")
    try:
        with open(path, encoding="utf-8", errors="surrogateescape") as f:
            text = f.read()
    except OSError:
        return
    new = _SERVICE.sub(_flag, text)
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
