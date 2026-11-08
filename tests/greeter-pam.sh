#!/usr/bin/env bash
# greetd-pam (the login screen's PAM service, /etc/pam.d/greetd, made from greetd.pam and the system's stack: here a
# stand-in Arch one): the system's auth lines as they are, nodelay on pam_unix and pam_faillock, the keyring's lines
# kept, greetd's own kept aside once, the same again when run again; a change to system-auth followed; a stack it can't
# follow (a substack, a module not there, no pam_unix) leaves the file as it was, said. Its pacman hook: on pambase and
# pam updates
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
fail() { echo "FAIL: $*"; exit 1; }
# shellcheck source=/dev/null  # (tests/fixtures/arch-pam.sh)
. "$here/tests/fixtures/arch-pam.sh"
i=$here/.local/share/caelestia-greeter
arch_pam "$t/pam.d" "$t/mod"
printf '%s\n' '-auth       optional     pam_gnome_keyring.so' '-session    optional     pam_gnome_keyring.so auto_start' >>"$t/pam.d/greetd"
cp "$t/pam.d/greetd" "$t/before"
gen() { PAM_DIR=$t/pam.d PAM_MODULES=$t/mod "$i/greetd-pam" "$@"; }
auth() { grep -E '^-?auth[[:space:]]' "$t/pam.d/greetd" | grep -v pam_gnome_keyring | sed -E 's/[[:space:]]+/ /g'; }

for _ in 1 2; do gen >/dev/null || fail "greetd-pam failed on Arch's stack"; done
want=$(printf '%s\n' 'auth required pam_securetty.so' 'auth requisite pam_nologin.so' 'auth required pam_shells.so' \
    'auth requisite pam_nologin.so' 'auth required pam_faillock.so preauth nodelay' \
    '-auth [success=2 default=ignore] pam_systemd_home.so' 'auth [success=1 default=bad] pam_unix.so try_first_pass nullok nodelay' \
    'auth [default=die] pam_faillock.so authfail nodelay' 'auth optional pam_permit.so' 'auth required pam_env.so' \
    'auth required pam_faillock.so authsucc nodelay')
[[ $(auth) == "$want" ]] || fail "not the system's auth lines with nodelay: $(auth)"
{ grep -qxE 'account +include +system-local-login' "$t/pam.d/greetd" && grep -qxE 'session +include +system-local-login' "$t/pam.d/greetd"; } ||
    fail "account or session not the system's: $(cat "$t/pam.d/greetd")"
[[ $(grep -c pam_gnome_keyring "$t/pam.d/greetd") == 2 && $(tail -2 "$t/pam.d/greetd") == "$(grep pam_gnome_keyring "$t/before")" ]] ||
    fail "the keyring's lines not kept after it (once): $(cat "$t/pam.d/greetd")"
cmp -s "$t/pam.d/greetd.orig" "$t/before" || fail "greetd's own file not kept aside (or overwritten the second time)"
[[ $(gen --print) == "$(grep -v pam_gnome_keyring "$t/pam.d/greetd")" ]] || fail "--print isn't what it writes"

# system-auth changed by an update (a new module, faillock's options): followed
sed -i 's/^\(auth .*pam_faillock.so *authfail\)$/\1 audit/' "$t/pam.d/system-auth"
sed -i '/pam_permit.so/i auth       required                    pam_new2fa.so' "$t/pam.d/system-auth"
: >"$t/mod/pam_new2fa.so"
gen >/dev/null || fail "greetd-pam failed on a changed system-auth"
{ auth | grep -qx 'auth required pam_new2fa.so' && auth | grep -qx 'auth \[default=die\] pam_faillock.so authfail audit nodelay'; } ||
    fail "system-auth's change not followed: $(auth)"

# As Linux-PAM reads it: a type in capitals (AUTH) taken, and a last line with no newline
cp "$t/pam.d/system-auth" "$t/system-auth.before-case"
printf '%s\n' 'AUTH       optional                    pam_upper.so' >>"$t/pam.d/system-auth"
printf '%s' 'auth       optional                    pam_last.so' >>"$t/pam.d/system-auth"
: >"$t/mod/pam_upper.so"; : >"$t/mod/pam_last.so"
gen >/dev/null || fail "greetd-pam failed on capitals or a last line with no newline"
{ grep -qE '^AUTH +optional +pam_upper\.so$' "$t/pam.d/greetd" && grep -qE '^auth +optional +pam_last\.so$' "$t/pam.d/greetd"; } ||
    fail "a type in capitals, or the last line with no newline, not taken: $(cat "$t/pam.d/greetd")"
cp "$t/system-auth.before-case" "$t/pam.d/system-auth"
gen >/dev/null
# What it can't follow: the file left as it is, said, exit 1
good=$(cat "$t/pam.d/greetd")
cp "$t/pam.d/system-auth" "$t/system-auth.ok"
for breakage in substack missing-module no-unix missing-include continued continued-space continued-tab continued-comment; do
    cp "$t/system-auth.ok" "$t/pam.d/system-auth"
    case $breakage in
        substack) echo 'auth       substack    system-2fa' >>"$t/pam.d/system-auth" ;;
        missing-module) echo 'auth       required    pam_gone.so' >>"$t/pam.d/system-auth" ;;
        no-unix) sed -i '/pam_unix.so/d' "$t/pam.d/system-auth" ;;
        missing-include) echo 'auth       include     system-gone' >>"$t/pam.d/system-auth" ;;
        continued) printf '%s\n' "auth       required    pam_env.so \\" '           readenv=1' >>"$t/pam.d/system-auth" ;;
        # (as Linux-PAM reads a continuation: after the spaces or tabs at the line's end, and before a comment)
        continued-space) printf '%s\n' "auth       required    pam_faillock.so \ " '           preauth' >>"$t/pam.d/system-auth" ;;
        continued-tab) printf '%s\n' "auth       required    pam_faillock.so \	" '           preauth' >>"$t/pam.d/system-auth" ;;
        continued-comment) printf '%s\n' "auth       required    pam_faillock.so \ # more below" '           preauth' >>"$t/pam.d/system-auth" ;;
    esac
    out=$(gen 2>&1) && fail "a stack with $breakage made into greetd: $out"
    [[ $out == *"left as it is"* && $(cat "$t/pam.d/greetd") == "$good" && ! -e $t/pam.d/greetd.new ]] ||
        fail "a stack with $breakage: the file not left as it was, or not said: $out"
done

# agros-greeter installs it and its template, and its pacman hook (pambase, pam) runs it
grep -q 'install -Dm755 "$src/greetd-pam" "$dst/greetd-pam"' "$here/packages/agros-greeter/PKGBUILD" || fail "agros-greeter doesn't install greetd-pam"
hook=$(cat "$here/packages/agros-greeter/agros-greeter-pam.hook")
{ grep -qx 'Target = pambase' <<<"$hook" && grep -qx 'Target = pam' <<<"$hook" &&
    grep -qx 'Exec = /etc/greetd/caelestia-greeter/greetd-pam' <<<"$hook"; } || fail "the PAM hook: $hook"
echo "ok greeter-pam"
