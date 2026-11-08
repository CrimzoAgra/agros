# shellcheck shell=bash
# arch_pam <pam.d dir> <modules dir>: Arch's (pambase 2026) login stack as on a fresh CachyOS (greetd's own file,
# system-local-login, system-login, system-auth) and a stand-in for each module it names. Sourced by the tests
arch_pam() {
    mkdir -p "$1" "$2"
    printf '%s\n' '#%PAM-1.0' '' 'auth       required     pam_securetty.so' 'auth       requisite    pam_nologin.so' \
        'auth       include      system-local-login' 'account    include      system-local-login' \
        'session    include      system-local-login' >"$1/greetd"
    printf '%s\n' '#%PAM-1.0' '' 'auth      include   system-login' 'account   include   system-login' \
        'password  include   system-login' 'session   include   system-login' >"$1/system-local-login"
    printf '%s\n' '#%PAM-1.0' '' 'auth       required   pam_shells.so' 'auth       requisite  pam_nologin.so' \
        'auth       include    system-auth' '' 'account    required   pam_access.so' 'account    required   pam_nologin.so' \
        'account    include    system-auth' '' 'password   include    system-auth' '' \
        'session    optional   pam_loginuid.so' 'session    include    system-auth' '-session   optional   pam_systemd.so' \
        'session    required   pam_env.so' >"$1/system-login"
    printf '%s\n' '#%PAM-1.0' '' 'auth       required                    pam_faillock.so      preauth' \
        '# Optionally use requisite above if you do not want to prompt for the password' \
        '-auth      [success=2 default=ignore]  pam_systemd_home.so' \
        'auth       [success=1 default=bad]     pam_unix.so          try_first_pass nullok' \
        'auth       [default=die]               pam_faillock.so      authfail' \
        'auth       optional                    pam_permit.so' 'auth       required                    pam_env.so' \
        'auth       required                    pam_faillock.so      authsucc' '' \
        'account    required                    pam_unix.so' 'password   required                    pam_unix.so          try_first_pass nullok shadow' \
        'session    required                    pam_unix.so' >"$1/system-auth"
    local m
    for m in securetty nologin shells access loginuid systemd env faillock systemd_home unix permit gnome_keyring; do
        : >"$2/pam_$m.so"
    done
}
