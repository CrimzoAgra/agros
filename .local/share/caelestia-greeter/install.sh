#!/usr/bin/env bash
# Installs the Caelestia-style login screen (shell.qml here) for greetd.
# Run with: sudo bash ~/.local/share/caelestia-greeter/install.sh
# If it fails to show, it falls back to the Noctalia login (or greetd's text login) on its own after 20 s.
# Undo for good (e.g. from a TTY with Ctrl+Alt+F2): sudo login-reset
set -e
[[ $EUID -eq 0 ]] || { echo "Run with sudo"; exit 1; }

user=${SUDO_USER:?run it with sudo from your own account}
src=$(dirname "$(readlink -f "$0")")
dst=/etc/greetd/caelestia-greeter

# greetd-agreety: the text login the start script and login-reset fall back to (greetd only needs some greeter, so it
# can be missing, e.g. where tuigreet is greetd's)
# (greetd too: its greeter user and config.toml are needed below, and this can run without the packages step)
pacman -S --needed --noconfirm greetd cage wlr-randr greetd-agreety

install -d -m 755 "$dst"
install -m 644 "$src/shell.qml" "$dst/shell.qml"
install -m 755 "$src/make-theme.sh" "$dst/make-theme.sh"
install -m 755 "$src/best-mode" "$dst/best-mode"
install -m 644 "$src/screenmode.py" "$dst/screenmode.py"

# Wallpaper + colours: a folder you own, refreshed at every login (no sudo needed)
install -d -m 755 -o "$user" -g "$(id -gn "$user")" "$dst/theme"
runuser -u "$user" -- "$dst/make-theme.sh" "$dst/theme" "$user"

# Who logs in, should theme.json break. Lines of your own there stay (a VM's LD_PRELOAD for its graphics: run again,
# this step dropped it and the login screen fell back)
{ grep -v '^CAELESTIA_GREETER_USER=' "$dst/env" 2>/dev/null || true; echo "CAELESTIA_GREETER_USER=$user"; } >"$dst/env.new"
chmod 644 "$dst/env.new" && mv "$dst/env.new" "$dst/env"

# The login screen runs as the "greeter" user; give Quickshell writable cache/state folders
install -d -m 755 -o greeter -g greeter /var/lib/caelestia-greeter /var/cache/caelestia-greeter
touch /var/log/caelestia-greeter.log && chown greeter:greeter /var/log/caelestia-greeter.log

# (each file written beside, then renamed over the old one: cut off midway, never half a file there)
cat >"$dst/run.new" <<'EOF'
#!/bin/sh
# Started by greetd as the "greeter" user: a kiosk compositor (cage) showing the Quickshell login screen
export XDG_CONFIG_HOME=/var/lib/caelestia-greeter XDG_DATA_HOME=/var/lib/caelestia-greeter
export XDG_STATE_HOME=/var/lib/caelestia-greeter XDG_CACHE_HOME=/var/cache/caelestia-greeter
export QT_WAYLAND_DISABLE_WINDOWDECORATION=1   # no title bar
export WLR_NO_HARDWARE_CURSORS=1   # pointer drawn in the picture, so it doesn't stay on the shutdown screen
set -a; . /etc/greetd/caelestia-greeter/env; set +a
# Keyboard layout for typing the password: the system's (localectl), as Hyprland uses, variant and options too. Read at
# each start, so a layout changed later (setup's keyboard step) applies here too
xkb() { sed -n "s/.*\"Xkb$1\"[[:space:]]*\"\([^\"]*\)\".*/\1/p" /etc/X11/xorg.conf.d/00-keyboard.conf 2>/dev/null | head -1; }
XKB_DEFAULT_LAYOUT=$(xkb Layout) XKB_DEFAULT_VARIANT=$(xkb Variant) XKB_DEFAULT_OPTIONS=$(xkb Options)
export XKB_DEFAULT_LAYOUT="${XKB_DEFAULT_LAYOUT:-us}" XKB_DEFAULT_VARIANT XKB_DEFAULT_OPTIONS
if [ -z "$XDG_RUNTIME_DIR" ]; then
    XDG_RUNTIME_DIR=/tmp/caelestia-greeter-$(id -u)
    mkdir -p "$XDG_RUNTIME_DIR" && chmod 700 "$XDG_RUNTIME_DIR"
    export XDG_RUNTIME_DIR
fi
# Wipe leftover boot text from this console, so it can't flash between screens
clear_console() { printf '\033[H\033[2J\033[3J\033[?25l' >/dev/tty 2>/dev/null || true; }
clear_console
exec >>/var/log/caelestia-greeter.log 2>&1   # keep the text console clean
echo "=== $(date -Is) starting"

# Safety net: if the login screen hasn't shown up after 20 s (crash, black screen), or closes without a login (a crash
# after its first frame: greetd would restart it in a loop, then give up on a black screen), use the Noctalia one
# instead, or greetd's text login if that's gone too
ready="$XDG_RUNTIME_DIR/caelestia-greeter-ready"
rm -f "$ready"
# shell.qml writes the time there when it starts a session: unchanged once it closes, no login (not compared with the
# clock, which can jump at boot)
launched="$XDG_STATE_HOME/caelestia-greeter-last-launch"
before=$(cat "$launched" 2>/dev/null)
fall_back() {
    echo "$1, falling back"
    kill -- -$pid 2>/dev/null
    wait $pid 2>/dev/null
    [ -x /usr/bin/noctalia-greeter-session ] && exec /usr/bin/noctalia-greeter-session
    # On the console, not the log, and with the cursor back
    printf '\033[?25h' >/dev/tty 2>/dev/null
    exec agreety --cmd hyprland-session </dev/tty >/dev/tty 2>&1
}
# In a process group of its own: the fallback stops all of it (dbus-run-session alone would leave cage on the screen)
setsid dbus-run-session -- cage -s -- sh -c '/etc/greetd/caelestia-greeter/best-mode; exec qs -p /etc/greetd/caelestia-greeter' &
pid=$!
i=0
while [ $i -lt 20 ] && [ ! -e "$ready" ] && kill -0 $pid 2>/dev/null; do
    sleep 1
    i=$((i + 1))
done
[ -e "$ready" ] || fall_back "login screen didn't start"
wait $pid
[ "$(cat "$launched" 2>/dev/null)" != "$before" ] || fall_back "login screen closed without a login"
clear_console   # again before the desktop starts
EOF
chmod 755 "$dst/run.new" && mv "$dst/run.new" "$dst/run"

# One-word desktop command for the text login fallback (the plain "Hyprland" session exits; uwsm works)
printf '#!/bin/sh\nexec uwsm start -e -D Hyprland hyprland.desktop\n' >/usr/local/bin/hyprland-session
chmod 755 /usr/local/bin/hyprland-session

# Manual way back, easy to type from a text console: sudo login-reset
cat >/usr/local/bin/login-reset.new <<'EOF'
#!/bin/sh
# Puts back the previous login screen (Noctalia), or greetd's text login if Noctalia is gone,
# and restarts the login service
[ "$(id -u)" -eq 0 ] || { echo "Run: sudo login-reset"; exit 1; }
if [ -x /usr/bin/noctalia-greeter-session ] && [ -f /etc/greetd/config.toml.noctalia ]; then
    cp /etc/greetd/config.toml.noctalia /etc/greetd/config.toml.new
else
    printf '[terminal]\nvt = 1\n\n[default_session]\ncommand = "agreety --cmd hyprland-session"\nuser = "greeter"\n' >/etc/greetd/config.toml.new
fi
# (beside it, then renamed over it: cut off midway, never half a file greetd can't start from)
chmod 644 /etc/greetd/config.toml.new && mv /etc/greetd/config.toml.new /etc/greetd/config.toml
systemctl restart greetd
EOF
chmod 755 /usr/local/bin/login-reset.new && mv /usr/local/bin/login-reset.new /usr/local/bin/login-reset

# Its PAM service (greetd): greetd's own made with the system's auth lines as they are now, a wrong password said at
# once (greetd-pam, from greetd.pam: nodelay on pam_unix and pam_faillock; the keyring's lines there kept), and made
# again after each pambase or pam update (the hook below), so it follows the system's. Not made (a stack it can't
# follow): the one there left as it is, and said
install -m 755 "$src/greetd-pam" "$dst/greetd-pam"
install -m 644 "$src/greetd.pam" "$dst/greetd.pam"
"$dst/greetd-pam" || true
install -d /etc/pacman.d/hooks
cat >/etc/pacman.d/hooks/caelestia-greeter-pam.hook <<'EOF'
# Installed by dotfiles/.local/share/caelestia-greeter/install.sh: the login screen's PAM service made again from the
# system's new one (greetd-pam)
[Trigger]
Operation = Install
Operation = Upgrade
Type = Package
Target = pambase
Target = pam

[Action]
Description = Updating the login screen's PAM service from the system's (caelestia-greeter)...
When = PostTransaction
Exec = /etc/greetd/caelestia-greeter/greetd-pam
EOF

cfg=/etc/greetd/config.toml
[[ -f $cfg.noctalia ]] || cp "$cfg" "$cfg.noctalia"
cat >"$cfg.new" <<EOF
[terminal]
vt = 1

[default_session]
command = "$dst/run"
user = "greeter"
EOF
chmod 644 "$cfg.new" && mv "$cfg.new" "$cfg"

echo "== $cfg"; cat "$cfg"
echo
echo "Done. Reboot to see the new login screen (log: /var/log/caelestia-greeter.log)."
echo "If it fails it falls back to the Noctalia login (or greetd's text login if Noctalia is gone) on its own after 20 s."
echo "To go back for good: Ctrl+Alt+F2, log in, then: sudo login-reset"
