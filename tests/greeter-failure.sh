#!/usr/bin/env bash
# The login screen's failure text: greetd's raw PAM code ("pam_authenticate: AUTH_ERR") said in words ("Wrong
# password"), the other obvious ones too, anything else as it came. Its failureText function run by node (its type
# annotations taken off), and the file parsing (qmllint), where they're installed
set -euo pipefail
. "$(dirname "$0")/lib.sh"
qml=$here/.local/share/caelestia-greeter/shell.qml
grep -q 'root.message = root.pamMessage || root.failureText(message);' "$qml" || fail "onAuthFailure doesn't use failureText (PAM's own message first)"
lint=$(command -v /usr/lib/qt6/bin/qmllint qmllint6 2>/dev/null | head -1) || true
if [[ -n $lint ]]; then
    out=$("$lint" "$qml" 2>&1 | grep -A2 '\[syntax\]' || true)
    [[ -z $out ]] || fail "the login screen's shell.qml doesn't parse: $out"
fi
command -v node >/dev/null || { echo "ok greeter-failure (SKIPPED: no node to run failureText)"; exit 0; }
fn=$(sed -n '/^    function failureText(message: string): string {$/,/^    }$/p' "$qml" | sed 's/(message: string): string {/(message) {/')
[[ -n $fn ]] || fail "failureText not found in shell.qml"
out=$(node -e "$fn
for (const m of ['pam_authenticate: AUTH_ERR', '', 'pam_acct_mgmt: ACCT_EXPIRED', 'pam_authenticate: MAXTRIES', 'pam_acct_mgmt: NEW_AUTHTOK_REQD', 'pam_setcred: SOMETHING_ELSE', 'Something went wrong'])
    console.log(failureText(m));")
want=$(printf '%s\n' "Wrong password" "Wrong password" "This account has expired" "Too many tries: wait a little, then try again" \
    "The password has expired: change it in a text console (Ctrl+Alt+F2)" "pam_setcred: SOMETHING_ELSE" "Something went wrong")
[[ $out == "$want" ]] || fail "failureText said: $out"
echo "ok greeter-failure"
