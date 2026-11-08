#!/usr/bin/env bash
# Builds the [agros] pacman repo: the AUR packages AgrOS uses (aur/packages.txt, with the AUR packages they need, by
# paru into a local repo) and AgrOS's own packages (packages/*, by makepkg), all signed when a key is given.
# Run in an Arch container, as root (it makes a "builder" user for makepkg):
#   ci/build-repo.sh <out dir>           the repo in <out dir> (agros.db, agros.files, the packages)
# Environment: GPGKEY (a key id in root's keyring: packages and the database signed with it, its public key in
# agros-keyring), AGROS_SKIP_AUR=1 (only AgrOS's own packages)
set -euo pipefail
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

# The repo, empty to start with, known to pacman (the AUR packages' own AUR dependencies are installed from it)
# (unsigned while it's built: paru adds to it without signing; the last repo-add below signs it)
[[ -e $out/agros.db.tar.gz ]] || asb repo-add "$out/agros.db.tar.gz"
grep -q '^\[agros\]' /etc/pacman.conf ||
    printf '\n[agros]\nSigLevel = Never\nServer = file://%s\n' "$out" >>/etc/pacman.conf
pacman -Sy --noconfirm >/dev/null

# No separate debug packages (Arch's makepkg makes them by default)
sed -i 's/^\(OPTIONS=(.*\) debug/\1 !debug/' /etc/makepkg.conf

# 1. The AUR packages, with paru (it builds the AUR dependencies too, in order, and adds them all to the repo)
if [[ -z ${AGROS_SKIP_AUR:-} ]]; then
    command -v paru >/dev/null || pacman -S --needed --noconfirm paru 2>/dev/null || {
        asb git clone -q https://aur.archlinux.org/paru-bin.git "$work/paru-bin"
        (cd "$work/paru-bin" && asb makepkg -si --noconfirm)
    }
    mapfile -t aur < <(grep -v '^\s*\(#\|$\)' "$root/aur/packages.txt")
    # PipeWire's JACK for what needs a "jack" (never jack2, which AgrOS doesn't install either)
    pacman -S --needed --noconfirm pipewire-jack >/dev/null
    asb mkdir -p /home/builder/.config/paru
    printf '[options]\nLocalRepo = agros\nSkipReview\nNoCheck\n[bin]\nMFlags = %s\n' "${sign[*]:-}" |
        asb tee /home/builder/.config/paru/paru.conf >/dev/null
    asb paru -S --noconfirm --needed --localrepo=agros "${aur[@]}"
fi

# 2. AgrOS's own packages (no dependencies installed to build them: they're files and settings), keyring first
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
    (cd "$d" && asb env PKGDEST="$out" makepkg -f --nodeps --noconfirm "${sign[@]}")
done
cd "$out"
asb repo-add -R "${rsign[@]}" agros.db.tar.gz ./*.pkg.tar.zst
# GitHub Pages serves no symlinks: the database's names as real files
for f in agros.db agros.files; do
    [[ -L $f ]] && cp --remove-destination "$(readlink -f "$f")" "$f"
    [[ -L $f.sig ]] && cp --remove-destination "$(readlink -f "$f.sig")" "$f.sig"
done
rm -rf "$work"
ls -la "$out"
