#!/usr/bin/env bash
# ci/sign-repo.sh (CI's release job, the only place AgrOS's secret key is): each package without a signature signed,
# one kept as published keeping its own, the database made again after (every package's signature in it) and signed
# under both its names, the upstream gate's list and Arch's last good day signed; a package with a .sig that isn't
# AgrOS's, a link, a secret key that isn't AgrOS's, or a subkey ci/agros.asc lacks: stopped, nothing signed over. With
# the primary key and with a subkey-only secret (as AGROS_GPG_KEY will be). Keys of the test's own; repo-add a stand-in
# (what it was given, and which packages had their .sig by then)
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
mkdir -p "$t/bin"
# shellcheck disable=SC2016  # (expanded by the stand-in)
cat >"$t/bin/repo-add" <<'S'
#!/bin/bash
[[ $1 == -q ]] && shift
db=$1; shift
for p; do [[ -e $p.sig ]] && echo "$p signed" || echo "$p unsigned"; done >"$db"
f=${db/.db./.files.}; cp "$db" "$f"
ln -sf "$db" "${db%.tar.gz}"; ln -sf "$f" "${f%.tar.gz}"
S
chmod +x "$t/bin/repo-add"
# key <home> <name>: a key of its own in <home>; its fingerprint
key() {
    mkdir -m700 -p "$1"
    GNUPGHOME=$1 gpg --batch --quiet --passphrase '' --quick-gen-key "$2 <test@agros.invalid>" ed25519 cert never >/dev/null 2>&1
    local f; f=$(GNUPGHOME=$1 gpg --batch --with-colons --list-secret-keys 2>/dev/null | awk -F: '$1 == "fpr" { print $10; exit }')
    GNUPGHOME=$1 gpg --batch --quiet --passphrase '' --quick-add-key "$f" ed25519 sign never >/dev/null 2>&1
    echo "$f"
}
fpr=$(key "$t/agros" AgrOS)
GNUPGHOME=$t/agros gpg --batch --armor --export "$fpr" >"$t/agros.asc" 2>/dev/null
GNUPGHOME=$t/agros gpg --batch --export "$fpr" >"$t/agros.gpg" 2>/dev/null
good() { gpgv --keyring "$t/agros.gpg" "$1.sig" "$1" >/dev/null 2>&1; }
# repo: new builds, one kept as published (its signature AgrOS's), the gate's files, an old database
repo() {
    rm -rf "$t/repo" && mkdir "$t/repo"
    local p
    for p in new-1-1-x86_64.pkg.tar.zst other-2-1-any.pkg.tar.xz kept-1-1-x86_64.pkg.tar.zst; do echo "$p" >"$t/repo/$p"; done
    GNUPGHOME=$t/agros gpg --batch --quiet --detach-sign "$t/repo/kept-1-1-x86_64.pkg.tar.zst" 2>/dev/null
    cp "$t/repo/kept-1-1-x86_64.pkg.tar.zst.sig" "$t/kept.sig"
    echo 'hyprland 0.58.0' >"$t/repo/agros-approved"
    echo 2026/11/16 >"$t/repo/agros-arch-ok"
    echo old >"$t/repo/agros.db" && echo old >"$t/repo/agros.db.sig"
}
sign() { GNUPGHOME=$1 AGROS_PUBKEY=${ASC:-$t/agros.asc} PATH=$t/bin:$PATH "$here/ci/sign-repo.sh" "$t/repo" 2>&1; }

# The primary key, then a subkey-only secret (the primary's secret not there: gpg signs with the subkey)
mkdir -m700 "$t/sub"
GNUPGHOME=$t/agros gpg --batch --export-secret-subkeys "$fpr" 2>/dev/null | GNUPGHOME=$t/sub gpg --batch --quiet --import 2>/dev/null
GNUPGHOME=$t/sub gpg --batch --with-colons --list-secret-keys 2>/dev/null | grep -q '^sec:.*:#:' ||
    fail "test setup: the subkey-only secret has its primary key's"
for home in agros sub; do
    repo
    out=$(sign "$t/$home") || fail "$home: not signed: $out"
    for f in new-1-1-x86_64.pkg.tar.zst other-2-1-any.pkg.tar.xz agros.db agros.db.tar.gz agros.files agros.files.tar.gz \
        agros-approved agros-arch-ok; do
        good "$t/repo/$f" || fail "$home: $f without a good signature by AgrOS's key"
    done
    cmp -s "$t/kept.sig" "$t/repo/kept-1-1-x86_64.pkg.tar.zst.sig" || fail "$home: a package kept as published signed over"
    [[ $out == *"2 packages signed, 1 kept"* ]] || fail "$home: not said what was signed: $out"
    # (made again after the signing, every package's signature in it; under its plain names as files, not links)
    [[ $(sort "$t/repo/agros.db") == $'./kept-1-1-x86_64.pkg.tar.zst signed\n./new-1-1-x86_64.pkg.tar.zst signed\n./other-2-1-any.pkg.tar.xz signed' ]] ||
        fail "$home: the database not made again from every package, signed first: $(cat "$t/repo/agros.db")"
    [[ ! -L $t/repo/agros.db && ! -L $t/repo/agros.files ]] || fail "$home: the database's names left as links"
done

# Refused, nothing signed over: a package with another key's .sig, or a bad one; a link
other=$(key "$t/other" Other)
for bad in other garbage link; do
    repo
    case $bad in
        other) GNUPGHOME=$t/other gpg --batch --quiet --detach-sign "$t/repo/new-1-1-x86_64.pkg.tar.zst" 2>/dev/null ;;
        garbage) echo x >"$t/repo/new-1-1-x86_64.pkg.tar.zst.sig" ;;
        link) ln -s /etc/hostname "$t/repo/link-1-1-any.pkg.tar.zst" ;;
    esac
    cp "$t/repo/new-1-1-x86_64.pkg.tar.zst.sig" "$t/before.sig" 2>/dev/null || rm -f "$t/before.sig"
    out=$(sign "$t/agros") && fail "$bad: signed all the same: $out"
    [[ $out == *refused* ]] || fail "$bad: not said: $out"
    [[ $(cat "$t/repo/agros.db") == old ]] || fail "$bad: the database made all the same"
    [[ ! -e $t/repo/other-2-1-any.pkg.tar.xz.sig ]] || fail "$bad: another package signed before it stopped"
    [[ ! -e $t/before.sig ]] || cmp -s "$t/before.sig" "$t/repo/new-1-1-x86_64.pkg.tar.zst.sig" || fail "$bad: its .sig signed over"
done
# A secret key that isn't AgrOS's
repo
out=$(sign "$t/other") && fail "signed with another key: $out"
[[ -e $t/repo/new-1-1-x86_64.pkg.tar.zst.sig ]] && fail "another key's signature left"
[[ $out == *"no secret key of $fpr"* ]] || fail "another key not said: $out"
# A new signing subkey ci/agros.asc doesn't have yet (clients couldn't check its signatures): stopped, said
newsub=$(GNUPGHOME=$t/agros gpg --batch --quiet --passphrase '' --quick-add-key "$fpr" ed25519 sign never 2>&1) ||
    fail "test setup: no new subkey: $newsub"
# (agros.asc as it was, before the new subkey)
repo
out=$(sign "$t/agros") && fail "signed with a subkey ci/agros.asc lacks: $out"
[[ $out == *"doesn't check against ci/agros.asc"* ]] || fail "a subkey agros.asc lacks not said: $out"
echo "ok ci-sign-repo"
