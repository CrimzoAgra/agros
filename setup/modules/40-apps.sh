# shellcheck shell=bash disable=SC2154  # $repo and $yes come from setup.sh
# about: Drivers, CachyOS gaming packages and the apps (Linux replacements for the Windows ones)
# scope: system

# Apps (the Windows ones they replace in brackets), as
# "name|packages|flatpaks|GitHub repo of an AppImage|GitHub repo of a .flatpak file|USB vendor ids".
# With vendor ids (hardware tools), only when a device of one is plugged in: OpenTabletDriver turns off the kernel's
# own pen drivers (a convertible laptop's pen stopped working), OpenRazer builds a kernel module at every update. Plug
# the device in and run ./setup.sh --only apps to add one later
# Packages come from the repos when there, otherwise from the AUR. An AppImage (its latest release) is installed by
# ~/.local/bin/appimage-open, so the app's own Update button works (it opens the new AppImage). A .flatpak file (its
# latest release) is installed for the user by ~/.local/bin/flatpak-bundle-update, which also keeps it updated (it
# has no Flatpak repo to update from).
# Left out, use the web versions: WhatsApp, Outlook, Teams, OneDrive.
APPS=(
    # cachyos-gaming-applications without Heroic (Lutris holds every store's library; python-protobuf: its Battle.net source). mesa and lib32-mesa named: with no
    # driver set up yet (chwd failed) the first offer for the graphics driver is mesa-git, which conflicts with mesa.
    # libayatana-appindicator: Lutris's tray icon (it starts hidden in the tray; without it, no icon on Wayland).
    # wine-mono, wine-gecko: Wine's .NET and web view, which it otherwise offers to download in a dialog at each new
    # prefix made with the system Wine (a store launcher installed from Lutris)
    # @gaming-meta@: CachyOS's gaming meta package, or on Arch what it brings (gaming_meta)
    "CachyOS gaming (Proton, Wine, Steam, Lutris, MangoHud, Gamescope...)|mesa lib32-mesa @gaming-meta@ steam lutris libayatana-appindicator wine-mono wine-gecko python-protobuf gamescope mangohud lib32-mangohud goverlay faugus-launcher wqy-zenhei xorg-fonts-misc|"
    "Equibop (Discord: themed with your colours by Caelestia)|equibop-bin|"
    "Spotify + Spicetify (themed with your colours by Caelestia, marketplace)|spicetify-cli spicetify-marketplace-bin|" # Spotify itself: apps_after
    "LibreWolf (Firefox without telemetry, privacy settings on; keeps cookies and history: .config/librewolf)|librewolf|"
    "Nuvio||||NuvioMedia/NuvioDesktop"
    "ArtCraft Launcher (ArtCraft)||||storytold/craft-launcher"
    "Boxflat (Moza Pit House)|boxflat-git||||346e"
    "Proton VPN|proton-vpn-gtk-app|"
    "OpenRazer + Polychromatic (Razer Synapse)|openrazer-daemon openrazer-driver-dkms polychromatic||||1532"
    "Solaar (Logitech G Hub, Logi Options+)|solaar||||046d"
    "OpenTabletDriver (Wacom tablet app; USB tablets: Wacom, Huion, XP-Pen, Gaomon)|opentabletdriver||||056a 256c 28bd 5543"
    "File Roller + 7-Zip (WinRAR, 7-Zip File Manager): Extract/Compress in Thunar's right-click menu|file-roller thunar-archive-plugin 7zip|"
    "VSCodium (VS Code's open-source build, no Microsoft telemetry; extensions from Open VSX)|vscodium|"
    "LibreOffice (Microsoft Office)|libreoffice-fresh|"
    "qBittorrent|qbittorrent|"
    "AntiMicroX (JoyToKey)|antimicrox|"
    "balenaEtcher (Rufus: writes a USB stick from an .iso or .img)|etcher-bin|"
    # scrcpy shown as Phone Link (.local/share/applications/phone-link.desktop); android-tools: adb, which it uses;
    # android-udev: the phone's USB device yours to use (without it adb sees it with "no permissions", only root reaches it)
    "Phone Link (scrcpy: your Android phone's screen on the computer)|scrcpy android-tools android-udev|"
    # The AUR package: Broadcom gives the installer only to signed-in users, so it takes the same file from a copy on
    # archive.org, checked against the checksum its maintainer pinned. Its kernel modules are built by DKMS for every
    # installed kernel (@kernel-headers@: their headers). Services: apps_after. vmware-keymaps named first: the package
    # needs it but sets that in its build script only, which the AUR helper doesn't read ("missing dependencies")
    "VMware Workstation (free for personal use)|vmware-keymaps vmware-workstation @kernel-headers@|"
    # HP's Linux driver (HPLIP) has the Deskjet 1050 J410 (and 1051/1055/1056): printing and scanning over USB, without
    # HP's closed plugin. CUPS prints (cups.socket: apps_after), Print Settings adds the printer, Document Scanner scans.
    # cups-pk-helper: Print Settings adds a printer after the desktop's own password prompt (polkit), not CUPS's login
    "HP Deskjet 1050 J410 (HP's printer software: printing and scanning with HPLIP)|cups cups-pk-helper hplip sane simple-scan system-config-printer|"
    "Steam extras (controller support, shader fix)|steam-devices spirv-tools|" # Steam comes with CachyOS gaming; spirv-tools: nvidia-shader-fix
)

module_apps() {
    ask "Install the apps (CachyOS gaming packages, Equibop (Discord), Spotify with Spicetify, LibreWolf, Steam, Lutris, Nuvio, Boxflat, Proton VPN, Razer/Logitech/Moza/tablet tools if that hardware is plugged in, File Roller, VSCodium, LibreOffice, qBittorrent, AntiMicroX, balenaEtcher, Phone Link (scrcpy), VMware Workstation, HP printing and scanning (HPLIP))?" ||
        return 0
    # Up to date first: this step can run alone (--only apps after plugging in a device), and packages from a stale
    # database fail to download once the mirrors moved on
    wait_boot_update
    "$repo/.local/bin/update-apps" --qt-mark  # (a new Qt: Quickshell and Caelestia rebuilt for it after, as 20-packages.sh)
    sudo pacman -Syu --noconfirm || echo "!! The system update failed; the apps may fail to install"
    "$repo/.local/bin/update-apps" --qt-rebuild || echo "!! Quickshell and Caelestia weren't rebuilt for the new Qt: run Updates"
    command -v flatpak >/dev/null || pkg_install flatpak
    # Mission Center, the Task Manager before btop: removed where an earlier run installed it
    if installed mission-center; then
        sudo pacman -Rns --noconfirm mission-center || echo "!! Mission Center couldn't be removed"
    fi
    install_drivers
    local apps=("${APPS[@]//@gaming-meta@/$(gaming_meta)}")
    install_apps "${apps[@]//@kernel-headers@/$(kernel_headers)}"
    # Firefox, which CachyOS installs: LibreWolf replaces it, so removed once LibreWolf is in (never left without a
    # browser), with its language packs and CachyOS's settings for it (they depend on it, so would block it). Its
    # profile (~/.mozilla) stays
    if installed firefox && installed librewolf; then
        # shellcheck disable=SC2046  # package names, one word each
        sudo pacman -Rns --noconfirm firefox $(pacman -Qq | grep -E "^(firefox-i18n-|cachyos-firefox-settings$)") || echo "!! Firefox couldn't be removed"
    fi
    apps_after
}

# gaming_meta: cachyos-gaming-meta where CachyOS's repos have it; on Arch (in no repo, nor the AUR: it took the AUR
# batch with Faugus down) what it brings, from Arch's own repos: Wine and its tools, umu (Faugus runs games with it),
# the libraries games load. Proton itself comes with Steam (and umu fetches its own for Faugus)
gaming_meta() {
    if pacman -Si cachyos-gaming-meta >/dev/null 2>&1; then
        echo cachyos-gaming-meta
    else
        echo wine winetricks protontricks umu-launcher alsa-plugins lib32-alsa-plugins giflib glfw gst-plugins-base-libs \
            lib32-gtk3 libjpeg-turbo lib32-libjpeg-turbo libva lib32-libva libxslt mpg123 opencl-icd-loader \
            lib32-opencl-icd-loader openal ttf-liberation vulkan-tools
    fi
}

# kernel_headers: the headers of every installed kernel (linux-cachyos-headers...), which DKMS builds modules against
kernel_headers() {
    local f
    for f in /usr/lib/modules/*/pkgbase; do
        [[ -f $f ]] && echo "$(<"$f")-headers"
    done | sort -u | tr '\n' ' '
}

# Graphics drivers (CachyOS's hardware detection picks the right ones for this GPU). Not over an NVIDIA driver already
# in (the one you have stays, updated with the system)
install_drivers() {
    # (or a driver providing it, e.g. a legacy branch's nvidia-580xx-utils: that one stays too)
    pacman -Q nvidia-utils >/dev/null 2>&1 && return 0
    if command -v chwd >/dev/null; then
        sudo chwd -a || echo "!! chwd reported a problem (drivers are usually already set up)"
    fi
    # Still no Vulkan driver (a GPU chwd has no profile for, a VM, Arch): Mesa's CPU one, or the gaming packages'
    # first offer for it is mesa-git, which conflicts with mesa and fails that whole entry
    pacman -T vulkan-driver lib32-vulkan-driver >/dev/null ||
        pkg_install vulkan-swrast lib32-vulkan-swrast || echo "!! No Vulkan driver: the gaming packages may fail"
}

# install_apps <entries...>: each app on its own, so one failure doesn't stop the rest
install_apps() {
    # System-wide Flatpaks, so the boot-time auto-update keeps them updated too
    sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo ||
        echo "!! Flathub couldn't be added (offline?): its apps won't install"
    local failed=() entry name pkgs flat_p gh_p bundle_p usb ok vendors
    # USB devices (behind hubs and receivers too) and Bluetooth ones (HID names: 0005:046D:B023.0001). Not built-in I2C
    # ones (0018:…): a convertible's own Wacom pen would pull in OpenTabletDriver, which breaks it
    # (|| true: with no HID bus yet (a VM with PS/2 input) the ls fails, and set -e would stop the step here)
    vendors=$({ cat /sys/bus/usb/devices/*/idVendor; ls /sys/bus/hid/devices | awk -F: '$1 == "0005" {print tolower($2)}'; } 2>/dev/null | sort -u) || true
    for entry in "$@"; do
        IFS='|' read -r name pkgs flat_p gh_p bundle_p usb <<<"$entry"
        if [[ -n $usb ]] && ! grep -qxFf <(tr ' ' '\n' <<<"$usb") <<<"$vendors"; then
            echo "-- $name: skipped (no such device plugged in)"
            continue
        fi
        echo "-- $name"
        ok=true
        # shellcheck disable=SC2086  # package and flatpak ids are space-separated on purpose
        {
            [[ -z $pkgs ]] || pkg_install $pkgs || ok=false
            [[ -z $flat_p ]] || sudo flatpak install -y --noninteractive flathub $flat_p || ok=false
        }
        # AppImage: the latest release's, checked against its SHA256SUMS when the release has one, installed by
        # appimage-open (~/Applications, launcher entry); the boot-time auto-update keeps it updated the same way
        [[ -z $gh_p ]] || "$repo/.local/bin/appimage-update" "$gh_p" || ok=false
        [[ -z $bundle_p ]] || "$repo/.local/bin/flatpak-bundle-update" --install "$bundle_p" || ok=false
        $ok || failed+=("$name")
    done
    if ((${#failed[@]})); then
        echo "Couldn't install: ${failed[*]}"
        echo "(Steam needs the [multilib] repo enabled in /etc/pacman.conf; OpenRazer needs your kernel's headers.)"
    else
        echo "All installed."
    fi
}

# Things some apps need after installing
apps_after() {
    # The store launchers (EA app, Ubisoft Connect...) listed under Launchers in Lutris's sidebar, by lutris-library (which
    # also runs whenever Lutris's database changes, and makes the database if Lutris hasn't run yet). A Lutris open now
    # shows them at once, unless it's an older build than the overlay's refresh change (the script's last line says)
    # (Lutris itself: on the desktop's PATH "lutris" is also ~/.local/bin/lutris, there without it)
    if [[ -x /usr/bin/lutris ]]; then
        local out
        if out=$("$repo/.local/bin/lutris-library" 2>&1); then
            [[ $out == *"once restarted"* ]] && out="; once Lutris restarts" || out=
            echo "Store launchers listed in Lutris (sidebar: Launchers$out)."
        else
            echo "!! lutris-library failed (run it to see why)"
        fi
    fi
    # OpenRazer only talks to users in its group (openrazer; plugdev in older versions), and runs as a user service
    if installed openrazer-daemon; then
        local g
        g=$(getent group openrazer >/dev/null && echo openrazer || echo plugdev)
        getent group "$g" >/dev/null || sudo groupadd -r "$g"
        sudo gpasswd -a "$USER" "$g" >/dev/null
        systemctl --user enable openrazer-daemon.service 2>/dev/null || true
    fi
    # Equibop: Caelestia writes a theme with your wallpaper's colours into its themes folder; turn it on
    # (settings.json also holds Equicord's cloud login, so it isn't kept in the dotfiles)
    if installed equibop-bin; then
        local eq="$HOME/.config/equibop/settings/settings.json"
        mkdir -p "${eq%/*}"
        [[ -s $eq ]] || echo '{}' >"$eq"
        jq '.enabledThemes = ((.enabledThemes // []) + ["caelestia.theme.css"] | unique)' "$eq" >"$eq.tmp" && mv "$eq.tmp" "$eq" ||
            { rm -f "$eq.tmp"; echo "!! Equibop's settings.json can't be read; its theme not turned on"; }
    fi
    # Spotify: a user Flatpak (not system-wide like the others), so spicetify can change it without root. Spicetify:
    # Caelestia's theme (Caelestia writes its color.ini with your colours) and the marketplace. ~/.local/bin/spotify-tray
    # applies it when Spotify starts (Spotify must have run once), and again after Spotify updates
    flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo ||
        echo "!! Flathub couldn't be added for you (offline?): no Spotify"
    flatpak install --user -y --noninteractive flathub com.spotify.Client || echo "!! Spotify (Flatpak) failed"
    if command -v spicetify >/dev/null; then
        spicetify -q config >/dev/null 2>&1 || true # makes its config file
        mkdir -p "$HOME/.config/spicetify/Themes"
        cp -rn "$HOME/.local/state/caelestia/dots/spicetify/Themes/caelestia" "$HOME/.config/spicetify/Themes/" 2>/dev/null || true
        spicetify -q config spotify_path "$HOME/.local/share/flatpak/app/com.spotify.Client/current/active/files/extra/share/spotify" \
            prefs_path "$HOME/.var/app/com.spotify.Client/config/spotify/prefs" \
            current_theme caelestia color_scheme caelestia custom_apps marketplace || echo "!! Spicetify setup failed"
    fi
    # VMware: its modules loaded at every boot by the package (modules-load.d), now too; its networks and USB
    # passthrough started when a VM starts (its .path units, as its package suggests)
    if installed vmware-workstation; then
        sudo modprobe -a vmw_vmci vmmon 2>/dev/null || echo "!! VMware's kernel modules didn't load: restart before using it"
        sudo systemctl enable --now vmware-networks.path vmware-usbarbitrator.path || echo "!! VMware's services couldn't be turned on"
    fi
    # Printing: CUPS started when something prints or Print Settings opens
    if installed cups; then
        sudo systemctl enable --now cups.socket || echo "!! CUPS couldn't be turned on (printing)"
    fi
    # OpenTabletDriver runs as a user service (it replaces the kernel's wacom driver after a reboot)
    if installed opentabletdriver; then
        systemctl --user enable opentabletdriver.service 2>/dev/null || true
    fi
}
