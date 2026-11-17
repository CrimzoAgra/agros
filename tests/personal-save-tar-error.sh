#!/usr/bin/env bash
# agros-personal --save: a file it can't read (tar fails on it) fails the save, keeping the drive's last good file.
# Only the last tar of the { tar; tar; tar; } group sets its status, so the first ones' errors are dropped: "Saved",
# the older full save replaced by one missing that file
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
export GNUPGHOME=$t/gnupg; mkdir -m 700 "$GNUPGHOME"; echo pass >"$t/pass"; export PERSONAL_PASSFILE=$t/pass
h=$t/home; mkdir -p "$h/.local/share/keyrings" "$h/.config/Proton/VPN" "$t/drive"
echo KEYRING >"$h/.local/share/keyrings/login.keyring"; echo VPN >"$h/.config/Proton/VPN/x"
echo OLD-GOOD-SAVE >"$t/drive/dotfiles-personal.tar.gpg"
chmod 000 "$h/.local/share/keyrings/login.keyring"
on_exit 'chmod -R u+rwX "$t"'
out=$(HOME=$h XDG_RUNTIME_DIR=$t R=$here D=$t/drive bash -c 'set -euo pipefail; source "$R/.local/bin/agros-personal"
    personal_dir=$D; personal_open() { :; }; personal_save' 2>&1) && rc=0 || rc=$?
grep -qx OLD-GOOD-SAVE "$t/drive/dotfiles-personal.tar.gpg" ||
    fail "a tar error (exit $rc) still replaced the last save: $out"
# Nor is anything it staged left in the runtime folder (in memory): not after a copy that failed either (Claude Code's
# files, set -e ending it), which left them there
[[ -z $(compgen -G "$t/personal.*") ]] || fail "a failed save left its staged files in the runtime folder"
chmod 644 "$h/.local/share/keyrings/login.keyring"
mkdir -p "$h/.claude"; echo SECRET >"$h/.claude/.credentials.json"; chmod 000 "$h/.claude/.credentials.json"
out=$(HOME=$h XDG_RUNTIME_DIR=$t R=$here D=$t/drive bash -c 'set -euo pipefail; source "$R/.local/bin/agros-personal"
    personal_dir=$D; personal_open() { :; }; personal_save' 2>&1) && rc=0 || rc=$?
((rc)) && grep -qx OLD-GOOD-SAVE "$t/drive/dotfiles-personal.tar.gpg" || fail "a copy that failed still saved (exit $rc): $out"
[[ -z $(compgen -G "$t/personal.*") ]] || fail "a copy that failed left its staged files in the runtime folder: $out"
echo "ok personal-save-tar-error"
