#!/usr/bin/env bash
# Builds the [agros] pacman repo: AgrOS's own packages (packages/*, by makepkg), the AUR packages AgrOS uses
# (aur/packages.txt, with the AUR packages they need, by paru into a local repo) and CachyOS's installer, rebuilt, all
# signed when a key is given.
# Run in an Arch container, as root (it makes a "builder" user for makepkg):
#   ci/build-repo.sh <out dir>           the repo in <out dir> (agros.db, agros.files, the packages)
#   ci/build-repo.sh <out dir> --hold-new   this run's new AUR builds there swapped for the published ones (below)
# Environment: AGROS_HELD (a file: the packages that didn't build, their published ones kept, "<name>: <why>" each),
# GPGKEY (a key id in root's keyring: packages and the database signed with it, its public key in
# agros-keyring), AGROS_SKIP_AUR=1 (only AgrOS's own packages: no AUR ones, no Calamares), AGROS_PUBLISHED (the
# published repo's URL: a package already there under the same version is kept as published, but for a compiled one
# built against other libraries (rebuilt and published); the build fails when the published copy can't be read or
# verified, or when one of AgrOS's own packages changed with its version not raised)
set -euo pipefail
shopt -s extglob  # (make_db's pattern, read as the function is)
root=$(cd "$(dirname "$0")/.." && pwd)
out=$(mkdir -p "${1:?usage: build-repo.sh <out dir>}" && cd "$1" && pwd)
key=${GPGKEY:-}

[[ $EUID -eq 0 ]] || { echo "Run as root (in a container)"; exit 1; }
id builder >/dev/null 2>&1 || useradd -m builder
echo 'builder ALL=(ALL) NOPASSWD: ALL' >/etc/sudoers.d/builder
chown -R builder: "$out"
work=$(mktemp -d)
cp -a "$root" "$work/agros"
chown -R builder: "$work"
asb() { sudo -u builder -H env ${GNUPGHOME:+GNUPGHOME=$GNUPGHOME} "$@"; }

# Signing: the key handed to the builder (makepkg --sign and repo-add --sign run as it)
sign=() rsign=()
if [[ -n $key ]]; then
    src_gpg=${GNUPGHOME:-$HOME/.gnupg}  # (where the key was imported: CI's container has its own HOME)
    export GNUPGHOME=/home/builder/.gnupg
    install -d -m700 -o builder -g builder "$GNUPGHOME"
    gpg --homedir "$src_gpg" --export-secret-keys "$key" | asb gpg --batch --import
    echo "allow-loopback-pinentry" | asb tee "$GNUPGHOME/gpg-agent.conf" >/dev/null
    sign=(--sign --key "$key") rsign=(--sign --key "$key")
    # agros-keyring: the public key and its fingerprint
    gpg --homedir "$src_gpg" --export "$key" >"$work/agros/packages/agros-keyring/agros.gpg"
    fpr=$(gpg --homedir "$src_gpg" --with-colons --fingerprint "$key" | awk -F: '$1 == "fpr" {print $10; exit}')
    echo "$fpr:4:" >"$work/agros/packages/agros-keyring/agros-trusted"
    chown builder: "$work/agros/packages/agros-keyring/"agros*
    # (pacman here trusts it too: the repo's signed database and packages are read below)
    pacman-key --add "$work/agros/packages/agros-keyring/agros.gpg" >/dev/null 2>&1
    pacman-key --lsign-key "$fpr" >/dev/null 2>&1
fi

# make_db [--held]: the database of the packages here (after a hold: each one as it is, none checked against the
# published ones again)
make_db() {
    local pkgs f
    # Every package here, whatever its compression or none (an AUR PKGBUILD may set its own PKGEXT: one left out of the database
    # was built for nothing), not their .sig files
    shopt -s nullglob
    pkgs=(*.pkg.tar?(.zst|.xz|.gz|.bz2|.lz4|.lzo|.lrz|.Z))
    shopt -u nullglob
    if [[ -n ${AGROS_PUBLISHED:-} && -n $key && ${1:-} != --held ]]; then
        for f in "${pkgs[@]}"; do
            [[ $f == agros-*-any.pkg.tar.zst ]] || keep_published "$f"  # (those checked after their build, above)
        done
    fi
    # The database made again from the packages here (paru's local repo already holds the AUR ones: added over it, each
    # warned that its entry already existed)
    rm -f agros.db agros.db.tar.gz agros.files agros.files.tar.gz agros.db*.sig agros.files*.sig
    asb repo-add "${rsign[@]}" agros.db.tar.gz "${pkgs[@]/#/./}"
    # GitHub Pages serves no symlinks: the database's names as real files
    for f in agros.db agros.files; do
        [[ -L $f ]] && cp --remove-destination "$(readlink -f "$f")" "$f"
        if [[ -L $f.sig ]]; then cp --remove-destination "$(readlink -f "$f.sig")" "$f.sig"; fi
    done
}
held=()
# shellcheck source=published.sh
. "$root/ci/published.sh"
# --hold-new (CI, when the tests found this run's new AUR builds broke them): each package here that is neither AgrOS's
# own nor the published file swapped for the published one (one never published: left out), the database made again;
# nothing built. AGROS_HOLD_WHY: why, said for each one in $AGROS_HELD
if [[ ${2:-} == --hold-new ]]; then
    cd "$out"
    hold_new "${AGROS_HOLD_WHY:-its new build held back}"
    make_db --held
    if ((${#held[@]})); then printf '%s\n' "${held[@]}"; fi >>"${AGROS_HELD:-/dev/null}"
    exit 0
fi

# The repo, empty to start with, known to pacman (the AUR packages' own AUR dependencies are installed from it)
# (unsigned while it's built: paru adds to it without signing; the last repo-add below signs it)
# (an empty archive: repo-add with no packages warns, twice, that it made an empty database)
if [[ ! -e $out/agros.db.tar.gz ]]; then
    for db in db files; do
        asb bsdtar -czf "$out/agros.$db.tar.gz" --files-from /dev/null && asb ln -sf "agros.$db.tar.gz" "$out/agros.$db"
    done
fi
grep -q '^\[agros\]' /etc/pacman.conf ||
    printf '\n[agros]\nSigLevel = Never\nServer = file://%s\n' "$out" >>/etc/pacman.conf
pacman -Sy --noconfirm >/dev/null

# No separate debug packages (Arch's makepkg makes them by default)
sed -i 's/^\(OPTIONS=(.*\) debug/\1 !debug/' /etc/makepkg.conf
# 1. AgrOS's own packages, first: one changed with its version not raised fails the build (below) before the long
# builds of the AUR's and Calamares. No dependencies installed to build them: they're files and settings, but for
# agros-vmware's shim, built against libdrm, and agros-thunar-usage, a Thunar plugin. Keyring first
pacman -T libdrm thunar >/dev/null || pacman -S --needed --noconfirm libdrm thunar >/dev/null
for d in "$work/agros/packages/agros-keyring" "$work"/agros/packages/*/; do
    d=${d%/}; p=${d##*/}
    [[ $p == agros-keyring && -n ${keyring_done:-} ]] && continue
    [[ $p == agros-keyring ]] && keyring_done=1
    [[ -f $d/PKGBUILD ]] || continue
    if [[ $p == agros-keyring && ! -s $d/agros.gpg ]]; then
        echo "-- $p: skipped (no GPGKEY)"
        continue
    fi
    echo "-- $p"
    # (--nodeps on purpose: makepkg's warning that it skips them left out)
    (cd "$d" && asb env PKGDEST="$out" makepkg -f --nodeps --noconfirm "${sign[@]}" 2>&1 |
        sed -u '/WARNING: Skipping dependency checks/d')
done
cd "$out"
# A package whose version hasn't changed keeps the file already published, when its signature checks out: a rebuild
# is a different file under the same name, and a copy of the old one in pacman's cache then reads as corrupted. But not
# a compiled one whose rebuild needs other libraries (a new Boost: the installer didn't start) or another Qt (its
# private API: Quickshell): the rebuild goes out instead, so new installs and the ISO get one that runs
# What a package was built against: the libraries its programs need, and Qt's version (its exit status means nothing:
# only for comparing, in [[ ]])
built_against() {
    local d=$work/unpacked
    rm -rf "$d" && mkdir "$d" && bsdtar -xf "$1" -C "$d" 2>/dev/null || return 0
    local libs
    libs=$(find "$d" -type f \( -name '*.so*' -o -perm -u+x \) -print0 2>/dev/null | xargs -0r readelf -d 2>/dev/null |
        sed -n 's/.*(NEEDED).*\[\(.*\)\]/\1/p' | sort -u)
    echo "$libs"
    # Python's version, for Python modules (no library of its own to need: they'd sit in an old python3.N)
    bsdtar -tf "$1" 2>/dev/null | grep -o '^usr/lib/python3\.[0-9]*' | sort -u
    # Qt's version (not Arch's rebuild number), for what uses Qt: the others had it in the container too
    grep -q '^libQt6' <<<"$libs" &&
        sed -n 's/^installed = qt6-base-\(.*\)-[^-]*-[^-]*$/qt \1/p' "$d/.BUILDINFO"
}
# What it holds, not when or how it was built: its name, version and relations, and its files' paths, types, modes,
# link targets and checksums (only these: a change in makepkg's or bsdtar's other fields doesn't read as a change). A
# package of AgrOS's own changed with its version not raised
contents() {
    bsdtar -xOf "$1" .PKGINFO 2>/dev/null |
        grep -E '^(pkgname|pkgver|depend|optdepend|provides|conflict|replaces|backup) = ' | sort
    # (mtree's /set lines give the fields a file's line leaves out)
    bsdtar -xOf "$1" .MTREE 2>/dev/null | zcat | awk '
        function kv(i) { k = $i; v = $i; sub(/=.*/, "", k); sub(/^[^=]*=/, "", v) }
        $1 == "/set" { for (i = 2; i <= NF; i++) { kv(i); set[k] = v }; next }
        $1 == "/unset" { for (i = 2; i <= NF; i++) delete set[$i]; next }
        $1 ~ /^\.\// && $1 !~ /^\.\/\.(PKGINFO|BUILDINFO)$/ {
            split("", a); for (k in set) a[k] = set[k]
            for (i = 2; i <= NF; i++) { kv(i); a[k] = v }
            print $1, "type=" a["type"], "mode=" a["mode"], "link=" a["link"], "sha256=" a["sha256digest"]
        }' | sort
}
# The published file kept for <file>, when its version is already published (a 404: not yet, a new version)
keep_published() {
    local f=$1 code
    # Not published yet (404): a new version. Anything else (Pages down, a timeout): stopped here, not a rebuild
    # published under a name users already have
    # (--retry: a timeout or a 5xx from Pages tried again; a 404 isn't)
    code=$(curl -sSL --retry 3 --max-time 300 -o "$work/pub" -w '%{http_code}' "$AGROS_PUBLISHED/$f" 2>/dev/null) ||
        code=000
    [[ $code == 404 ]] && return 0
    [[ $code == 200 ]] || { echo "!! $f: the published copy couldn't be read (HTTP $code)"; exit 1; }
    curl -fsSL --retry 3 --max-time 60 -o "$work/pub.sig" "$AGROS_PUBLISHED/$f.sig" ||
        { echo "!! $f: the published copy's signature couldn't be read"; exit 1; }
    asb gpg --batch --verify "$work/pub.sig" "$work/pub" 2>/dev/null ||
        { echo "!! $f: the published copy's signature doesn't check out"; exit 1; }
    if [[ $f != agros-*-any.pkg.tar.zst && $(built_against "$work/pub") != "$(built_against "$f")" ]]; then
        echo "-- $f: the rebuild published (built against other libraries, Qt or Python than the published one)"
        return 0
    fi
    # (the fixed versions: agros-desktop, agros-welcome, agros-keyring, agros-nvidia; not compiled ones, whose build
    # differs with each compiler: agros-vmware's and agros-thunar-usage's versions count the commits that touch them)
    # One versioned by the commits (a pkgver()) differs only if built differently from the same commit: a build that
    # isn't reproducible (it read something besides the repo), stopped here too rather than published over or hidden
    if [[ $f == agros-*-any.pkg.tar.zst && $(contents "$work/pub") != "$(contents "$f")" ]]; then
        local name
        name=$(bsdtar -xOf "$f" .PKGINFO 2>/dev/null | sed -n 's/^pkgname = //p')
        if grep -q '^pkgver()' "$root/packages/$name/PKGBUILD" 2>/dev/null; then
            echo "!! $f: built from the same commit as the published one, but its contents differ: packages/$name doesn't build reproducibly"
        else
            echo "!! $f changed but its version didn't: raise pkgver in packages/$name/PKGBUILD"
        fi
        diff <(contents "$work/pub") <(contents "$f") | head -20 || true  # (diff cut off by head: not the failure)
        exit 1
    fi
    mv -f "$work/pub" "$f" && mv -f "$work/pub.sig" "$f.sig" && chown builder: "$f" "$f.sig"
    echo "-- $f: the published file kept"
}
if [[ -n ${AGROS_PUBLISHED:-} && -n $key ]]; then
    for f in agros-*-any.pkg.tar.zst; do keep_published "$f"; done
fi

# A package that doesn't build (an AUR change, AgrOS's patch or Calamares changes no longer fitting, a download that
# failed) holds back: the published one is kept (its signature checked), with the packages of this repo it needs, and
# the rest goes out as usual, not the whole repo held up. Said in $AGROS_HELD ("<name>: <why>" each, for CI's issue).
# None published to keep (its first build): the build fails
# The AUR packages and CachyOS's installer built without compiler warnings: theirs (quickshell's hundreds), not
# AgrOS's to fix, and they buried the log. AgrOS's own packages (1.) built before, with them
cp /etc/makepkg.conf "$work/makepkg.conf"
printf '\nCFLAGS+=" -w"\nCXXFLAGS+=" -w"\n' >>/etc/makepkg.conf

# 2. The AUR packages, with paru (it builds the AUR dependencies too, in order, and adds them all to the repo)
if [[ -z ${AGROS_SKIP_AUR:-} ]]; then
    command -v paru >/dev/null || pacman -S --needed --noconfirm paru 2>/dev/null || {
        asb git clone -q https://aur.archlinux.org/paru-bin.git "$work/paru-bin"
        (cd "$work/paru-bin" && asb makepkg -si --noconfirm)
    }
    mapfile -t aur < <(grep -v '^\s*\(#\|$\)' "$root/aur/packages.txt")
    # PipeWire's JACK for what needs a "jack" (never jack2, which AgrOS doesn't install either)
    pacman -S --needed --noconfirm pipewire-jack >/dev/null
    # (spicetify-cli's build runs node, which its AUR package doesn't list. Arch's: CachyOS's, first in pacman.conf,
    # can lag an Arch library's new version, and node then doesn't start (libsimdjson.so.34, November 2026))
    pacman -S --needed --noconfirm extra/nodejs >/dev/null
    # The keys AUR sources are signed with (papirus-folders' author, 1BA35B1B...: its PKGBUILD's validpgpkeys), kept in
    # the repo: the keyserver timed out (16 minutes, then the build failed)
    asb gpg --batch --import <"$root/ci/papirus-folders.asc" ||  # (read here: the builder may not read the checkout)
        echo "!! papirus-folders' signing key not imported: it won't build"
    asb mkdir -p /home/builder/.config/paru
    printf '[options]\nLocalRepo = agros\nSkipReview\nNoCheck\n[bin]\nMFlags = %s\n' "${sign[*]:-}" |
        asb tee /home/builder/.config/paru/paru.conf >/dev/null
    # ninja's status lines for steps with no description (blank) left out
    # (and makepkg's note that it builds in the sources it unpacked: paru unpacks, then builds, always)
    aur_build() {
        asb paru -S --noconfirm --needed --localrepo=agros "${aur[@]}" 2>&1 |
            sed -u -e '/^\[[0-9]*\/[0-9]*\] *$/d' -e '/WARNING: Using existing \$srcdir\/ tree/d'
    }
    # Quickshell first, with AgrOS's fix (aur-agros-patch: the boot's rebuild on a new Qt adds it the same way), into
    # the repo: caelestia-shell's quickshell-git taken from it, by its name (CachyOS's noctalia-qs only claims it), not
    # built from the AUR without the fix. Its build files or the patch no longer fitting: the published one held
    { asb git clone -q https://aur.archlinux.org/quickshell-git.git "$work/quickshell-git" &&
        asb "$work/agros/packages/agros-system/aur-agros-patch" "$work/quickshell-git" quickshell-git &&
        (cd "$work/quickshell-git" && asb env PKGDEST="$out" makepkg -s --noconfirm "${sign[@]}"); } ||
        hold quickshell-git "AgrOS's fix (packages/agros-system/aur-patches) didn't build: has Quickshell fixed it itself?"
    asb repo-add -q "$out/agros.db.tar.gz" "$out"/quickshell-git-*.pkg.tar.zst
    pacman -Sy --noconfirm >/dev/null
    # (twice: a download that drops, GitHub's now and then, fails only its package; the second pass builds what's left)
    # One that still didn't build: the published one held, with what it needs
    aur_build || aur_build || true
    for p in "${aur[@]}"; do
        out_has "${p#*/}" || hold "${p#*/}" "it didn't build from the AUR (the build's log above)"
    done
fi

# 3. CachyOS's installer, rebuilt against the libraries of today (CachyOS's own copy can lag behind an Arch update:
# built for Boost 1.91, it didn't start once Arch moved to 1.92). Its version a ".5" above CachyOS's (calamares_rel
# below); the live ISO has it from [agros] (packages_desktop.x86_64). The partition names drawn in the theme's text
# colours, not black and grey (unreadable on AgrOS's dark installer); the package list's highlight gone on a click on
# no row (Qt's single selection keeps it, its extended one clears it); the language list's English names in the
# highlight's text colour on the highlighted row (drawn in the list's own, they were lost in the highlight); GRUB only,
# the bootloader page's choice gone
# Plain text swaps, each checked after (the build fails when one no longer fits)
# Any change to the swaps raises calamares_rel, with a line for it below holding their new checksum: an unchanged
# version would keep the old installer published, so the build fails when the swaps' checksum isn't the one recorded
# for this calamares_rel (each rel's line kept as it is: a new checksum under an old rel fails just the same)
if [[ -z ${AGROS_SKIP_AUR:-} ]]; then
    calamares_rel=5
    case $calamares_rel in
        5) calamares_sum=2db12fafcbd8 ;;
    esac
    # (not fetched: its build below finds no folder, and the published one is held)
    { asb git clone -q --depth 1 --filter=blob:none --sparse https://github.com/CachyOS/CachyOS-PKGBUILDS.git "$work/cachyos-pkgbuilds" &&
        (cd "$work/cachyos-pkgbuilds" && asb git sparse-checkout set cachyos-calamares); } ||
        echo "!! CachyOS's PKGBUILDs couldn't be fetched"
    cat >"$work/calamares-labels" <<'SH'
    sed -i -e 's/painter->setPen( Qt::black );/painter->setPen( palette().windowText().color() );/' -e 's/painter->setPen( Qt::gray );/painter->setPen( palette().placeholderText().color() );/' src/modules/partition/gui/PartitionLabelsView.cpp
    sed -i 's/^\( *\)ui->groupswidget->setModel( c->model() );$/&\n\1ui->groupswidget->setSelectionMode( QAbstractItemView::ExtendedSelection );/' src/modules/netinstall/NetInstallPage.cpp
    sed -i 's/^\( *index.data( Calamares::Locale::TranslationsModel::EnglishLabelRole ).toString()\) );$/\1, option.state \& QStyle::State_Selected ? QPalette::HighlightedText : QPalette::NoRole );/' src/modules/welcome/WelcomePage.cpp
    # GRUB only: the bootloader page's choice (none: AgrOS's installer has no such page) read as GRUB where the compiled
    # modules read it: the ZFS pool's GRUB compatibility, the partition page's GRUB settings and its BIOS hint, the
    # boot partition made on erase-disk (agros-iso's agros-calamares-config does the same for the Python modules)
    sed -i 's/gs->value( "packagechooser_bootloader" ).toString()/QStringLiteral( "grub" )/' \
        src/modules/zfs/ZfsJob.cpp src/modules/partition/Config.cpp src/modules/partition/PartitionViewStep.cpp \
        src/modules/partition/core/PartitionActions.cpp
    # (each one checked: a CachyOS or Calamares change that moves a line fails the build, not a silent unchanged installer)
    grep -q 'palette().windowText().color()' src/modules/partition/gui/PartitionLabelsView.cpp &&
        grep -q 'palette().placeholderText().color()' src/modules/partition/gui/PartitionLabelsView.cpp &&
        grep -q 'setSelectionMode( QAbstractItemView::ExtendedSelection )' src/modules/netinstall/NetInstallPage.cpp &&
        grep -q 'QPalette::HighlightedText : QPalette::NoRole' src/modules/welcome/WelcomePage.cpp &&
        grep -q 'bootloader = QStringLiteral( "grub" )' src/modules/zfs/ZfsJob.cpp &&
        ! grep -rq 'packagechooser_bootloader' src/modules --include=*.cpp ||
        { echo "AgrOS's changes to Calamares no longer fit (ci/build-repo.sh)"; return 1; }
SH
    sum=$(sha256sum <"$work/calamares-labels" | cut -c1-12)
    [[ $sum == "${calamares_sum:-}" ]] || {
        echo "!! The Calamares swaps changed: raise calamares_rel to $((calamares_rel + 1)) and add its line," \
            "$((calamares_rel + 1))) calamares_sum=$sum ;; (ci/build-repo.sh)"
        exit 1
    }
    # (CachyOS's own pkgrel with a dot already: not raised, and AgrOS's build would have CachyOS's version)
    # (it not building, AgrOS's changes no longer fitting: the published one held)
    (cd "$work/cachyos-pkgbuilds/cachyos-calamares" &&
        { grep -q '^pkgrel=[0-9]*$' PKGBUILD || { echo "!! cachyos-calamares: its pkgrel isn't a plain number"; false; }; } &&
        asb sed -i "s/^pkgrel=\([0-9]*\)$/pkgrel=\1.$calamares_rel/" PKGBUILD &&
        asb sed -i -e "/^prepare() {/{n;r $work/calamares-labels" -e '}' PKGBUILD &&
        asb env PKGDEST="$out" makepkg -s --noconfirm "${sign[@]}") ||
        hold cachyos-calamares-next "CachyOS's installer didn't build with AgrOS's changes (the build's log above)"
fi
cp "$work/makepkg.conf" /etc/makepkg.conf

make_db
# (what was held, for CI's issue)
if ((${#held[@]})); then printf '%s\n' "${held[@]}"; fi >"${AGROS_HELD:-/dev/null}"
rm -rf "$work"
ls -la "$out"
