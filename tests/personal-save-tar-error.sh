#!/usr/bin/env bash
# agros-personal --save: a file it can't read (tar fails on it) fails the save, keeping the drive's last good file.
# Only the last tar of the { tar; tar; tar; } group sets its status, so the first ones' errors are dropped: "Saved",
# the older full save replaced by one missing that file
set -euo pipefail
. "$(dirname "$0")/lib.sh"
export GNUPGHOME=$t/gnupg; mkdir -m 700 "$GNUPGHOME"; echo pass >"$t/pass"; export PERSONAL_PASSFILE=$t/pass
h=$t/home; mkdir -p "$h/.local/share/keyrings" "$h/.config/Proton/VPN" "$t/drive"
echo KEYRING >"$h/.local/share/keyrings/login.keyring"; echo VPN >"$h/.config/Proton/VPN/x"
echo OLD-GOOD-SAVE >"$t/drive/dotfiles-personal.tar.gpg"
chmod 000 "$h/.local/share/keyrings/login.keyring"
trap 'chmod -R u+rwX "$t"; rm -rf "$t"' EXIT
out=$(HOME=$h XDG_RUNTIME_DIR=$t R=$here D=$t/drive bash -c 'set -euo pipefail; source "$R/.local/bin/agros-personal"
    personal_dir=$D; personal_open() { :; }; personal_save' 2>&1) && rc=0 || rc=$?
grep -qx OLD-GOOD-SAVE "$t/drive/dotfiles-personal.tar.gpg" ||
    fail "a tar error (exit $rc) still replaced the last save: $out"
echo "ok personal-save-tar-error"
