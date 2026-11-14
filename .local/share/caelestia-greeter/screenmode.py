"""Which screen mode is best, shared by the login screen (best-mode, from the compositor's modes) and the kernel
console (system/boot-video-mode, from the screen's EDID), so both, and the desktop, use the same one: the screen's own
(preferred) resolution, the highest when it names none, then its highest refresh rate there: best()."""


def rank(width, height, refresh):
    """Sort key: the best mode is the max."""
    return (width * height, refresh)


def best(modes, preferred=()):
    """The best of modes, each (width, height, refresh, ...: anything after is the caller's, returned with it): at a
    preferred resolution ((width, height) pairs: the screen's own) when it has a mode there, else of them all. None
    when there are no modes"""
    preferred = set(preferred)
    modes = [m for m in modes if (m[0], m[1]) in preferred] or list(modes)
    return max(modes, key=lambda m: rank(*m[:3])) if modes else None


if __name__ == "__main__":  # (a self-check: python3 screenmode.py)
    assert best([(1920, 1080, 60.0), (3840, 2160, 30.0), (1920, 1080, 144.0)], [(1920, 1080)]) == (1920, 1080, 144.0)
    assert best([(1920, 1080, 60.0), (3840, 2160, 30.0)], [(1280, 720)]) == (3840, 2160, 30.0)  # (none there)
    assert best([(800, 600, 60.0, "x")]) == (800, 600, 60.0, "x") and best([]) is None
    print("ok screenmode")
