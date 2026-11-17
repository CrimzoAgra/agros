#!/usr/bin/env bash
# ci/sign-repo.sh (CI's sign job, the only place AgrOS's secret key is): each package without a signature signed,
# one kept as published keeping its own, the database as the release job made it (ci/repo-db.sh) signed under both its
# names, unchanged, the upstream gate's list and Arch's last good day signed; repo-add never run (it runs a package's
# .PKGINFO line of the wrong kind as code: never beside the key). A package with a .sig that isn't AgrOS's, a link, a
# database file missing or a link, a secret key that isn't AgrOS's, or a subkey ci/agros.asc lacks: stopped, nothing
# signed over. With the primary key and with a subkey-only secret (as AGROS_GPG_KEY will be). Keys of the test's own
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
# (a repo-add that says it ran)
stub repo-add "touch $t/repo-add-ran"
# key <home> <name>: a key of its own in <home>; its fingerprint
key() {
    mkdir -m700 "$1"
    GNUPGHOME=$1 gpg --batch --quiet --passphrase '' --quick-gen-key "$2 <test@agros.invalid>" ed25519 cert never >/dev/null 2>&1
    local f; f=$(GNUPGHOME=$1 gpg --batch --with-colons --list-secret-keys 2>/dev/null | awk -F: '$1 == "fpr" { print $10; exit }')
    GNUPGHOME=$1 gpg --batch --quiet --passphrase '' --quick-add-key "$f" ed25519 sign never >/dev/null 2>&1
    echo "$f"
}
fpr=$(key "$t/agros" AgrOS)
GNUPGHOME=$t/agros gpg --batch --armor --export "$fpr" >"$t/agros.asc" 2>/dev/null
GNUPGHOME=$t/agros gpg --batch --export "$fpr" >"$t/agros.gpg" 2>/dev/null
# (its first signing subkey: the published files' signer, whichever subkey is newer later)
sub1=$(GNUPGHOME=$t/agros gpg --batch --with-colons --list-secret-keys "$fpr" 2>/dev/null | awk -F: '$1 == "fpr" { f = $10 } END { print f }')
good() { gpgv --keyring "$t/agros.gpg" "$1.sig" "$1" >/dev/null 2>&1; }
# repo: new builds, one kept as published (its signature AgrOS's), the gate's files, the database ci/repo-db.sh made
# (an old signature beside it)
repo() {
    rm -rf "$t/repo" && mkdir "$t/repo"
    local p
    for p in new-1-1-x86_64.pkg.tar.zst other-2-1-any.pkg.tar.xz kept-1-1-x86_64.pkg.tar.zst; do echo "$p" >"$t/repo/$p"; done
    GNUPGHOME=${KEPT_HOME:-$t/agros} gpg --batch --quiet --local-user "${KEPT_KEY:-$sub1!}" --detach-sign "$t/repo/kept-1-1-x86_64.pkg.tar.zst" 2>/dev/null
    cp "$t/repo/kept-1-1-x86_64.pkg.tar.zst.sig" "$t/kept.sig"
    echo 'hyprland 0.58.0' >"$t/repo/agros-approved"
    echo 2026/11/16 >"$t/repo/agros-arch-ok"
    local f
    for f in agros.db agros.db.tar.gz agros.files agros.files.tar.gz; do echo "the $f" >"$t/repo/$f"; done
    echo old >"$t/repo/agros.db.sig"
}
sign() { GNUPGHOME=$1 AGROS_PUBKEY=${ASC:-$t/agros.asc} PATH=$t/bin:$PATH "$here/ci/sign-repo.sh" "$t/repo" 2>&1; }

# The whole key, then a subkey-only secret (the primary's secret not there: gpg signs with the subkey)
mkdir -m700 "$t/sub"
GNUPGHOME=$t/agros gpg --batch --export-secret-subkeys "$fpr" 2>/dev/null | GNUPGHOME=$t/sub gpg --batch --quiet --import 2>/dev/null
grep -q '^sec:.*:#:' <<<"$(GNUPGHOME=$t/sub gpg --batch --with-colons --list-secret-keys 2>/dev/null)" ||
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
    # (the database as given, not made again: repo-add never run here)
    [[ $(cat "$t/repo/agros.db") == "the agros.db" && $(cat "$t/repo/agros.files.tar.gz") == "the agros.files.tar.gz" ]] ||
        fail "$home: the database changed: $(cat "$t/repo/agros.db")"
    [[ ! -e $t/repo-add-ran ]] || fail "$home: repo-add run beside the key"
done
# A key whose primary key signs, with no signing subkey (AgrOS's key as it is now)
mkdir -m700 "$t/prim"
GNUPGHOME=$t/prim gpg --batch --quiet --passphrase '' --quick-gen-key 'Primary <test@agros.invalid>' ed25519 sign never >/dev/null 2>&1
pfpr=$(GNUPGHOME=$t/prim gpg --batch --with-colons --list-secret-keys 2>/dev/null | awk -F: '$1 == "fpr" { print $10; exit }')
GNUPGHOME=$t/prim gpg --batch --armor --export "$pfpr" >"$t/prim.asc" 2>/dev/null
GNUPGHOME=$t/prim gpg --batch --export "$pfpr" >"$t/prim.gpg" 2>/dev/null
KEPT_HOME=$t/prim KEPT_KEY=$pfpr repo
out=$(ASC=$t/prim.asc sign "$t/prim") || fail "not signed with a primary key: $out"
for f in new-1-1-x86_64.pkg.tar.zst agros.db agros-approved; do
    st=$(gpgv --keyring "$t/prim.gpg" --status-fd 1 "$t/repo/$f.sig" "$t/repo/$f" 2>/dev/null) &&
        grep -q "VALIDSIG $pfpr .* $pfpr\$" <<<"$st" || fail "$f not signed by the primary key: $st"
done

# Refused, nothing signed over: a package with another key's .sig, or a bad one; a link; the database missing, or a link
key "$t/other" Other >/dev/null
for bad in other garbage link nodb dblink; do
    repo
    case $bad in
        other) GNUPGHOME=$t/other gpg --batch --quiet --detach-sign "$t/repo/new-1-1-x86_64.pkg.tar.zst" 2>/dev/null ;;
        garbage) echo x >"$t/repo/new-1-1-x86_64.pkg.tar.zst.sig" ;;
        link) ln -s /etc/hostname "$t/repo/link-1-1-any.pkg.tar.zst" ;;
        nodb) rm "$t/repo/agros.files.tar.gz" ;;
        dblink) rm "$t/repo/agros.files" && ln -s agros.files.tar.gz "$t/repo/agros.files" ;;
    esac
    cp "$t/repo/new-1-1-x86_64.pkg.tar.zst.sig" "$t/before.sig" 2>/dev/null || rm -f "$t/before.sig"
    out=$(sign "$t/agros") && fail "$bad: signed all the same: $out"
    [[ $out == *refused* ]] || fail "$bad: not said: $out"
    [[ ! -e $t/repo/agros.db.sig || $(cat "$t/repo/agros.db.sig") == old ]] || fail "$bad: the database signed all the same"
    [[ ! -e $t/repo/other-2-1-any.pkg.tar.xz.sig ]] || fail "$bad: another package signed before it stopped"
    [[ ! -e $t/before.sig ]] || cmp -s "$t/before.sig" "$t/repo/new-1-1-x86_64.pkg.tar.zst.sig" || fail "$bad: its .sig signed over"
done
# A secret key that isn't AgrOS's
repo
out=$(sign "$t/other") && fail "signed with another key: $out"
[[ -e $t/repo/new-1-1-x86_64.pkg.tar.zst.sig ]] && fail "another key's signature left"
[[ $out == *"no secret key of $fpr"* ]] || fail "another key not said: $out"
# The key rotated: a new signing subkey, AGROS_GPG_KEY its subkey-only export. ci/agros.asc without it yet (clients
# couldn't check its signatures): stopped, said; with it: signed
newsub=$(GNUPGHOME=$t/agros gpg --batch --quiet --passphrase '' --quick-add-key "$fpr" ed25519 sign never 2>&1) ||
    fail "test setup: no new subkey: $newsub"
newsub=$(GNUPGHOME=$t/agros gpg --batch --with-colons --list-secret-keys "$fpr" 2>/dev/null | awk -F: '$1 == "fpr" { f = $10 } END { print f }')
mkdir -m700 "$t/new"
GNUPGHOME=$t/agros gpg --batch --export-secret-subkeys "$newsub!" 2>/dev/null | GNUPGHOME=$t/new gpg --batch --quiet --import 2>/dev/null
repo
out=$(sign "$t/new") && fail "signed with a subkey ci/agros.asc lacks: $out"
[[ $out == *"doesn't check against ci/agros.asc"* ]] || fail "a subkey agros.asc lacks not said: $out"
GNUPGHOME=$t/agros gpg --batch --armor --export "$fpr" >"$t/agros-new.asc" 2>/dev/null
repo
out=$(ASC=$t/agros-new.asc sign "$t/new") || fail "not signed with the new subkey, agros.asc having it: $out"
GNUPGHOME=$t/agros gpg --batch --export "$fpr" >"$t/agros-new.gpg" 2>/dev/null
st=$(gpgv --keyring "$t/agros-new.gpg" --status-fd 1 "$t/repo/agros.db.sig" "$t/repo/agros.db" 2>/dev/null) &&
    grep -q "VALIDSIG $newsub .* $fpr\$" <<<"$st" || fail "not signed by the new subkey: $st"
echo "ok ci-sign-repo"
