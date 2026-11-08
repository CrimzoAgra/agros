#!/usr/bin/env bash
# No "no video" between the login screen and the desktop: installs system/boot-video-mode, which at every boot gives
# the kernel console each connected screen's best mode (highest resolution, then its highest refresh rate), the
# same one the desktop uses, so the screen doesn't resync when Hyprland takes over.
# Run with: sudo bash system/boot-video-mode.sh   (setup.sh asks to run it)
# Remove: sudo systemctl disable boot-video-mode && sudo rm -r /etc/systemd/system/boot-video-mode.service /usr/local/lib/boot-video-mode
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Run with sudo"; exit 1; }
# Only Limine and GRUB take the setting (as boot-video-mode decides): with another boot loader (systemd-boot, rEFInd),
# nothing to install
if [[ ! -f /etc/default/limine ]] && ! { [[ -f /etc/default/grub ]] && command -v grub-mkconfig >/dev/null; }; then
    echo "No GRUB or Limine here, screen mode at boot left as is."
    exit 0
fi
pacman -S --needed --noconfirm v4l-utils   # edid-decode: reads the screens' modes
# With screenmode.py, the mode rule it shares with the login screen
install -Dm 755 "$(dirname "$0")/boot-video-mode" /usr/local/lib/boot-video-mode/boot-video-mode
install -Dm 644 "$(dirname "$0")/../.local/share/caelestia-greeter/screenmode.py" /usr/local/lib/boot-video-mode/screenmode.py
rm -f /usr/local/bin/boot-video-mode   # where an earlier version put it
cat >/etc/systemd/system/boot-video-mode.service <<'EOF'
[Unit]
Description=Kernel console in each screen's best mode (from the next boot)
# shortcut: only after the boot-time update has started, not finished (it's Type=exec); both may rewrite the boot
# entries at once if the screens changed on a boot that also updates the kernel. Wait on pacman's lock if that bites
After=auto-update.service

[Service]
Type=oneshot
ExecStart=/usr/local/lib/boot-video-mode/boot-video-mode

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable boot-video-mode.service
# report <boot-video-mode> <its run's exit status>: what the console uses from the next boot. "Done" only when the run
# went through and the boot config now has the modes it meant to set (--current reads it as boot-video-mode does);
# else said as not set, with what the console keeps: the modes set before, or its default. None of the screens telling
# its modes (EDID: a VM's virtual one often doesn't) said as such. Never failing setup's step for what it only says
# (set -e there)
report() {
    local modes rc=0 before cur=0 m set=true
    modes=$("$1" --check) || rc=$?
    before=$("$1" --current 2>/dev/null) || { cur=$?; before=; }
    local keeps="its default"
    [[ -z $before ]] || keeps="the modes set before: $before"
    # (no Limine or GRUB settings, --current's 4: the boot loader's own mode, nothing for this to set)
    if ((cur == 4)); then
        echo "Nothing to do: no Limine or GRUB settings here, so the console keeps the mode its boot loader gives it"
        return 0
    fi
    case $rc in
        0) for m in $modes; do [[ " $before " == *" $m "* ]] || set=false; done
           if ((${2:-0} == 0)) && $set; then
               echo "Done: from the next boot the console uses: $modes"
           elif $set; then
               echo "!! The screens' modes ($modes) are in the boot config, but its boot entries couldn't be made again" \
                    "(see above): they apply once they are (the next kernel update, or limine-update / grub-mkconfig)"
           else
               echo "!! The screens' modes ($modes) couldn't be set in the boot config (see above): the console keeps $keeps"
           fi ;;
        3) if [[ -n $before ]]; then
               echo "Nothing new to set: no screen reports its modes now (EDID), so the console keeps the ones set" \
                    "before: $before"
           else
               echo "Nothing to set now: no screen reports its modes (EDID), so the console keeps its default. A screen" \
                    "that does gets its mode at the next boot."
           fi ;;
        *) echo "!! The screens' modes couldn't be read: the console keeps $keeps" ;;
    esac
}
# Now, for the next boot (failing: said by report, not setup's whole system step stopped here)
bvm=/usr/local/lib/boot-video-mode/boot-video-mode
ran=0
"$bvm" || ran=$?
report "$bvm" "$ran"
