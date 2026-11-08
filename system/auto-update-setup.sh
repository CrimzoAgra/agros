#!/usr/bin/env bash
# Automatic update at every boot: system (kernel, CachyOS gaming packages), Flatpaks (the user's too) and any
# AppImages you've installed (through ~/.local/bin/appimage-update). Not AUR apps, nor Capri (her fork merged with the
# original's latest release, built and its tests run: ~/.local/bin/capri-update): they're built from code anyone can
# change, so they wait until you start an update (update-apps: in a terminal it shows the AUR build scripts' changes for
# review first; from the Updates app they're built without that review, listed first); Capri's new release is only
# looked for.
# The system's packages are only downloaded at boot and installed at shutdown: installed under the running session, a
# new NVIDIA driver didn't match the one loaded (games failed with "API mismatch" until a reboot) and a new kernel took
# the running one's modules (USB devices plugged in later got no driver).
# Run with: sudo bash system/auto-update-setup.sh
# Log: /var/log/auto-update.log. A Snapper snapshot is taken first when Snapper is set up,
# so a bad update can be undone by booting the snapshot from the boot menu.
# Remove: sudo systemctl disable auto-update auto-update-install && sudo rm -r /var/lib/auto-update
#   /etc/systemd/system/auto-update.service /etc/systemd/system/auto-update-install.service /usr/local/bin/auto-update
#   /etc/systemd/system/{poweroff,reboot,halt,kexec}.target.d/auto-update.conf
#
# Only full upgrades (pacman -Syu): on Arch, updating just the drivers without the rest of the
# system (a partial upgrade) is what breaks things.
set -e
[[ $EUID -eq 0 ]] || { echo "Run with sudo"; exit 1; }
user=${SUDO_USER:?run with sudo from your user}
home=$(getent passwd "$user" | cut -d: -f6)
# What takes pacman's lock (pacman and the programs on its library) and lock_holder, which finds one holding it:
# dotfiles-check's, the one definition (read as system/render.sh does, which dotfiles-check renders this script with
# to see whether it's the repo's)
repo=$(dirname "$(readlink -f "$0")")/..
# shellcheck source=/dev/null  # (system/render.sh)
source "$repo/system/render.sh"
holders=$(pacman_holders_of "$repo")
holder_fn=$(lock_holder_of "$repo")
[[ -n $holders && -n $holder_fn ]] || { echo "pacman_holders or lock_holder not found in $repo/.local/bin/dotfiles-check"; exit 1; }

cat >/usr/local/bin/auto-update <<EOF
#!/usr/bin/env bash
# Automatic system update: downloaded at boot, installed at shutdown with --install
# (installed by dotfiles/system/auto-update-setup.sh)
exec >>/var/log/auto-update.log 2>&1
echo "===== \$(date) \${1:-} ====="

# The download's own package lists (as checkupdates does): synced into pacman's own, the system would be on newer lists
# than packages all session, and installing any one package then a partial upgrade. Its lock is its own too, so setup
# and the Updates app aren't kept waiting on it
db=/var/lib/auto-update/db
mkdir -p "\$db/sync"
ln -sfn /var/lib/pacman/local "\$db/local"

# pacman's own lists an install replaced, kept until it's over ("installing" while it runs): an install that fails, or
# is cut off (shutdown's time limit, a power cut), must leave pacman on the lists its packages came from, not newer
# ones (a partial upgrade). restore puts them back (at the next boot for one cut off); settled drops them
au=/var/lib/auto-update
# What takes pacman's lock, and lock_holder finding one holding it (dotfiles-check's): pacman's lists aren't changed
# under any of them
pacdb=/var/lib/pacman
pacman_holders='$holders'
$holder_fn
prev=\$au/prev
restore() {
    local f
    for f in "\$prev"/*.db; do
        [[ -e \$f ]] || continue
        cp -a "\$f" /var/lib/pacman/sync/
        if [[ -e \$f.sig ]]; then cp -a "\$f.sig" /var/lib/pacman/sync/; else rm -f "/var/lib/pacman/sync/\${f##*/}.sig"; fi
        # (one this put back, older than the download it took out: the next install takes that download again)
        sha256sum <"\$f" >"\$au/copied/\${f##*/}.sum"
    done
    settled
}
settled() { rm -rf "\$prev" "\$au/installing"; }
# recover: an install cut off (shutdown's limit, a power cut), or its recovery put off: pacman's lists put back (its
# packages came from the older ones; those it got to install are taken up again by the next install), and the lock it
# left. Run at boot and before an install, each time until it's done (only with nothing holding pacman's lock)
recover() {
    [[ -e \$au/installing ]] || return 0
    echo "the last install was cut off: pacman's package lists put back as they were"
    restore
    if [[ -e \$pacdb/db.lck ]]; then
        echo "removing the lock it left: \$pacdb/db.lck"
        rm -f "\$pacdb/db.lck"
    fi
}
# held: pacman's lock there and one of its users running (not one cut off: its lock left with nothing behind it)
held() { [[ -e \$pacdb/db.lck ]] && lock_holder; }

if [[ \${1:-} == --install ]]; then
    # How a real install went, for dotfiles-check (this runs at shutdown: its log alone was never seen): ok, held or
    # failed, when, and why. Shutdowns with nothing installed (skip, below) counted beside it, not over it: a held or
    # failed install is still said until one replaces it
    result() { printf '%s %s %s\n' "\$1" "\$(date '+%F %H:%M')" "\${2:-}" >"\$au/install-result"; rm -f "\$au/skipped"; }
    # Said on the splash, where its theme shows messages (the plain one looked stuck for the minutes a kernel takes)
    say() { command -v plymouth >/dev/null && plymouth --ping 2>/dev/null && plymouth display-message --text="\$1" 2>/dev/null; true; }
    # skip <why>: nothing installed this shutdown, counted ("<shutdowns> <since> <why>", dotfiles-check says it 3 in a row)
    skip() {
        echo "\$1: nothing installed"
        read -r skips since _ 2>/dev/null <"\$au/skipped" || true
        [[ \${skips:-} =~ ^[0-9]+\$ ]] || { skips=0 since=\$(date +%F); }
        echo "\$((skips + 1)) \$since \$1" >"\$au/skipped"
        exit 0
    }
    # A soft reboot (systemctl soft-reboot) stops this too, but keeps the kernel running: a kernel or driver installed
    # under it is the mismatch installing at shutdown is for. Left for a real shutdown
    ! systemctl list-jobs --no-legend 2>/dev/null | grep -q '^ *[0-9]* *soft-reboot\.target ' ||
        skip "a soft reboot (the kernel keeps running: installed at a real shutdown)"
    # Only what a finished download brought (its mark, "complete"): one cut off (its 2 h, a shutdown during it) has
    # lists newer than the packages it got, and installing from them would download the rest at shutdown
    [[ -e \$db/complete ]] || skip "the boot's download didn't finish"
    # (the boot partition, wherever fstab mounts it, mounted: a kernel or boot image written with it away would go to
    # the folder under it, and the boot use the old ones). An automount's (x-systemd.automount) placeholder counts as
    # mounted too: looked into first (that mounts it), then the real one there, not autofs. Then kept open (busy) for
    # the whole install: neither unmounted for being idle nor, "nofail" (not ordered at shutdown), under it
    for m in /boot /boot/efi /efi; do
        [[ \$(findmnt --fstab -n -o TARGET "\$m" 2>/dev/null) == "\$m" ]] || continue
        ls "\$m" >/dev/null 2>&1 || true
        # shellcheck disable=SC2034  # (busy: the open folder's number, only kept open)
        { mountpoint -q "\$m" && [[ \$(findmnt -n -l -o FSTYPE --mountpoint "\$m" 2>/dev/null | tail -1) != autofs ]] &&
            exec {busy}<"\$m"; } 2>/dev/null || skip "the boot partition (\$m) isn't mounted"
    done
    # (nor while something else using pacman holds its lock: its lists would change under it)
    ! holder=\$(held) || skip "something using pacman still ran (\$holder)"
    # A lock left by a pacman cut off outside this (an Updates run's paru, killed by shutdown or a power cut: pacman
    # leaves it on anything but Ctrl+C), with nothing having it open now (the sessions are all stopped): stale, else
    # every install after it failed on it. Something still having it open: left, nothing installed
    if [[ -e \$pacdb/db.lck && ! -e \$au/installing ]]; then
        for fd in /proc/[0-9]*/fd/*; do
            [[ \$(readlink "\$fd" 2>/dev/null) != "\$pacdb/db.lck" ]] || skip "something has pacman's lock open (\${fd%/fd/*})"
        done
        echo "removing a stale lock (a pacman cut off, nothing has it open): \$pacdb/db.lck"
        rm -f "\$pacdb/db.lck"
    fi
    recover
    # (gone once a real install runs: one with nothing to install, or nothing held back, leaves no "held back" for
    # dotfiles-check to keep saying)
    rm -f "\$au/held"
    # The lists the download used, each with its signature (a list without its own, pacman refuses it as invalid),
    # where newer than pacman's: by the mirror's time (the download's and pacman's own sync keep it; cp -p here too),
    # or pacman's is still the one this put there (by content: copied before -p, its time was the copy's, and a list
    # downloaded the next day looked older and was skipped). Not when the Updates app synced newer ones since. The ones
    # replaced kept aside
    rm -rf "\$prev"
    mkdir -p "\$prev" "\$au/copied"
    touch "\$au/installing"
    for f in "\$db"/sync/*.db; do
        name=\${f##*/}
        dst=/var/lib/pacman/sync/\$name
        ! cmp -s "\$f" "\$dst" || continue
        [[ \$f -nt \$dst || \$(sha256sum <"\$dst" 2>/dev/null) == "\$(cat "\$au/copied/\$name.sum" 2>/dev/null)" ]] || continue
        [[ ! -e \$dst ]] || cp -a "\$dst" "\$prev/"
        [[ ! -e \$dst.sig ]] || cp -a "\$dst.sig" "\$prev/"
        cp -p "\$f" "\$dst"
        if [[ -e \$f.sig ]]; then cp -p "\$f.sig" "\$dst.sig"; else rm -f "\$dst.sig"; fi
        sha256sum <"\$dst" >"\$au/copied/\$name.sum"
    done
    pending=\$(pacman -Qu 2>&1) || [[ -z \$pending ]] || {  # (pacman's error, not "none")
        echo "\$pending"
        result failed "pacman couldn't list the updates: \$(tail -1 <<<"\$pending")"
        restore
        exit 1
    }
    [[ -n \$pending ]] || { echo "nothing to install"; result ok; settled; exit 0; }
    # A new Qt (not a rebuild of the same version) would stop the shells, built against its private parts, from starting
    # at the next boot: Quickshell and Caelestia are AUR packages this can't rebuild. The whole update waits (a part of
    # it would be a partial upgrade) for the Updates app, which installs it and rebuilds them (dotfiles-check says so)
    if awk '\$1 ~ /^qt6-(base|declarative)\$/ { a = \$2; b = \$4; sub(/-[^-]*\$/, "", a); sub(/-[^-]*\$/, "", b); if (a != b) q = 1 } END { exit !q }' <<<"\$pending"; then
        grep -E '^qt6-(base|declarative) ' <<<"\$pending" | tee "\$au/held"
        echo "held back: a new Qt (run Updates)"
        result held
        restore
        exit 0
    fi
    # safety snapshot (pick it in the boot menu if an update breaks something). --no-dbus: this runs at shutdown, when
    # snapperd (started on demand over DBus) can't be started any more, and the snapshot was silently skipped
    # Then into the boot menu's snapshot list here: what does that otherwise (grub-btrfsd, Limine's snapper sync) is
    # stopped by now, and isn't started at shutdown, so this one never showed there. Neither installed: nothing to do
    if snapper --no-dbus -c root list >/dev/null 2>&1 &&
        snapper --no-dbus -c root create -c number -d "auto-update \$(date +%F_%H%M)"; then
        if [[ -x /etc/grub.d/41_snapshots-btrfs ]]; then
            /etc/grub.d/41_snapshots-btrfs >/dev/null || echo "the boot menu's snapshot list not refreshed (grub-btrfs)"
        elif command -v limine-snapper-sync >/dev/null; then
            limine-snapper-sync >/dev/null || echo "the boot menu's snapshot list not refreshed (limine-snapper-sync)"
        fi
    fi
    # Every package is here (the download finished); the network is still up all the same (ordered after it): pacman
    # hooks may use it (hyprbars' fetches its source). Its output into the log as it goes (cut off: what it got to)
    say "Installing updates, don't turn the computer off..."
    result failed "cut off before it finished"  # (until it says otherwise: shutdown's time limit, a power cut)
    # (SNAP_PAC_SKIP: snap-pac's own snapshots, over DBus, fail at shutdown like snapper's did; the one above covers it)
    SNAP_PAC_SKIP=y pacman -Su --noconfirm 2>&1 | tee "\$prev/out"
    if ((PIPESTATUS[0])); then
        echo "!! the install failed: pacman's package lists put back as they were"
        result failed "\$(grep -m1 '^error:' "\$prev/out")"
        say "The update failed: it's tried again at the next shutdown"
        restore
        exit 1
    fi
    result ok
    settled
    echo "===== done \$(date) ====="
    exit
fi

# The last shutdown's install cut off before it finished: recovered now, or (something using pacman holding its lock)
# at the next install or boot
if [[ -e \$au/installing ]] && holder=\$(held); then
    echo "the last install was cut off, but something using pacman runs (\$holder): recovered later"
else
    recover
fi

# wait for the network (max ~60 s)
for _ in \$(seq 30); do curl -fsI --max-time 2 https://archlinux.org >/dev/null 2>&1 && break; sleep 2; done

# system and CachyOS gaming packages, the NVIDIA driver too: downloaded now, installed at shutdown (only once this
# finished: its mark, complete).
# A lock a download cut off left (shutdown stopped it mid-way) taken out first, only with no pacman on these lists
# running; else every boot's download failed on it (dotfiles-check says when one is left)
if [[ -e \$db/db.lck ]] && ! pgrep -f -- "--dbpath \$db" >/dev/null; then
    echo "removing a stale lock: \$db/db.lck"
    rm -f "\$db/db.lck"
fi
rm -f "\$db/complete"
pacman -Syuw --noconfirm --dbpath "\$db" --logfile /dev/null && touch "\$db/complete"

# flatpak apps: the system-wide ones, then the user's (Spotify: user-installed so spicetify can change it) and those
# installed from a downloaded file (Nuvio, ArtCraft), as the user
if command -v flatpak >/dev/null; then
    # (each given up on after half an hour: a stalled one held shutdown off for as long as it hung)
    timeout 30m flatpak update -y --noninteractive
    timeout 30m sudo -u "$user" -H flatpak update --user -y --noninteractive
    # Those from a file: downloaded first (as the user, nothing held), then reinstalled (old one out first) with sleep and
    # power off held for that step alone: by root, here (logind refuses the user that hold outside a session). Usually
    # seconds; a runtime the new version needs is downloaded in it too, so it's given up on after half an hour as well
    if [[ -x "$home/.local/bin/flatpak-bundle-update" ]] && fetched=\$(sudo -u "$user" mktemp -d); then
        sudo -u "$user" -H "$home/.local/bin/flatpak-bundle-update" --fetch "\$fetched"
        [[ ! -s \$fetched/fetched ]] ||
            timeout 30m systemd-inhibit --what=sleep:shutdown --mode=block --who="Flatpak update" \
                --why="Reinstalling apps from their files" sudo -u "$user" -H "$home/.local/bin/flatpak-bundle-update" --install-fetched "\$fetched"
        rm -rf "\$fetched"
    fi
fi

# AppImages you've installed, from their GitHub releases, as the user (they live in ~/Applications)
[[ -x "$home/.local/bin/appimage-update" ]] && sudo -u "$user" -H "$home/.local/bin/appimage-update"

# Capri (capri-update's), when she's installed: only whether her fork or the original's release moved on
# (in this log; the Updates app lists it), as the user. Merged, built and tested when you start it from Updates, as
# AUR apps. capri-update itself finds whether she's installed (nothing when not), in the user's own data folder
[[ -x "$home/.local/bin/capri-update" ]] && sudo -u "$user" -H "$home/.local/bin/capri-update" --check

echo "===== done \$(date) ====="
EOF
chmod 755 /usr/local/bin/auto-update

cat >/etc/systemd/system/auto-update.service <<'EOF'
[Unit]
Description=Automatic system update at boot
# No network-online.target: the desktop's login waits for everything ordered before it (3 s at boot); the script
# waits for the network itself

[Service]
# exec, not oneshot: boot (and the desktop, which waits for it) doesn't wait for the update to finish
Type=exec
# No shutdown/sleep inhibitor for the run: its system part only downloads (installed at shutdown,
# auto-update-install.service; a download cut off is picked up again: no "complete" mark, its lock taken out and the
# files resumed at the next boot), and blocking would refuse power off, sleep and the power button for as long as a
# slow download took. What it does install now: Flatpak updates (flatpak swaps an app's new version in whole) and
# AppImages (moved in place once downloaded); a Flatpak from a file is reinstalled, old one out first, so the script
# holds sleep and power off (as root) around that step alone (30 min at most), its file's download done before
ExecStart=/usr/local/bin/auto-update
Nice=10
IOSchedulingClass=idle
TimeoutStartSec=1h
# (exec: "started" at once, so that limit never applied, and a hung download ran on for good) The whole run ends after
# 2 h; a download cut off leaves its lock, taken out at the next boot
RuntimeMaxSec=2h

[Install]
WantedBy=multi-user.target
EOF

# At shutdown (and reboot): what the boot downloaded installed, with nothing running from it. Ordered after the
# filesystems, so it's stopped (installs) before they're unmounted
cat >/etc/systemd/system/auto-update-install.service <<'EOF'
[Unit]
Description=Install the system update downloaded at boot
# After the network too, so it's still up while this installs: the hyprbars pacman hook downloads its source then.
# Before the boot's download and before systemd-user-sessions: units stop in the reverse order, so at shutdown the
# download (if still running) is stopped first, and every user session with it (Hyprland, the shell, the apps, an
# Updates run's pacman or paru: user@.service and the session scopes come after systemd-user-sessions), and this
# installs after them, never under a running desktop or alongside another pacman. Not ordered on /boot's mount: being
# before systemd-user-sessions, that made the login screen wait at boot for a slow or "nofail" boot partition (up to
# 90 s); /boot is after local-fs.target (so still mounted when this stops) unless "nofail", and the install itself
# checks it's mounted
After=local-fs.target network.target
Before=auto-update.service systemd-user-sessions.service
RequiresMountsFor=/var/lib/pacman /var/cache/pacman

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/true
ExecStop=/usr/local/bin/auto-update --install
# A kernel or NVIDIA driver update rebuilds the boot image: minutes. Its own limit, 30 min; shutdown's (the targets'
# JobTimeoutSec, also 30 min, then forced) is made longer below, so it can't cut this off first
TimeoutStopSec=30min

[Install]
WantedBy=multi-user.target
EOF

# Older versions let you run pacman without a password (for AUR updates at boot): anything running as you could
# then install a package and be root
rm -f /etc/sudoers.d/99-auto-update /etc/sudoers.d/10-auto-update

# Shutdown, reboot, halt and kexec give up after 30 min and force it (their JobTimeoutSec, counted from the start of the
# shutdown): with the install's own 30 min that came first, possibly in the middle of a boot image being made. Theirs
# 45 min: still a limit, a shutdown never hangs for good
for target in poweroff reboot halt kexec; do
    mkdir -p "/etc/systemd/system/$target.target.d"
    printf '%s\n' "[Unit]" "# Longer than auto-update-install.service's TimeoutStopSec (dotfiles/system/auto-update-setup.sh)" \
        "JobTimeoutSec=45min" >"/etc/systemd/system/$target.target.d/auto-update.conf"
done
systemctl daemon-reload
# Every boot downloads into pacman's cache, which nothing emptied: paccache's weekly clean-up (the last 3 versions of
# each package kept, to go back to)
pacman -S --needed --noconfirm pacman-contrib >/dev/null && systemctl enable --now paccache.timer ||
    echo "!! paccache.timer couldn't be turned on: pacman's cache (/var/cache/pacman/pkg) isn't cleaned"
systemctl enable auto-update.service
# (started now: else this boot's shutdown wouldn't install)
systemctl enable --now auto-update-install.service
echo "Done: the system downloads its update at every boot and installs it at shutdown (log: /var/log/auto-update.log)."
