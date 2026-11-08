"""Which screen mode is best, shared by the login screen (best-mode, from the compositor's modes) and the kernel
console (system/boot-video-mode, from the screen's EDID), so both, and the desktop, use the same one: the highest
resolution, then its highest refresh rate."""


def rank(width, height, refresh):
    """Sort key: the best mode is the max."""
    return (width * height, refresh)
