#!/usr/bin/env bash
# ci/install-test.sh: the release installed for real into an empty root (base and every agros-* package), the
# container's pacman.conf with its NoExtract lines dropped and [agros] last. A file conflict, a conflict, a dependency
# not met or an install script failing that names one of [agros]'s new builds: it held (hold=), the install tried
# again with it held; one whose published one fails too: not held, said (note=); nothing of [agros]'s named: said, none
# held; a download that kept failing: tried 3 times, said as not run, none held. pacman, mount, build-repo.sh and
# repo-db.sh are stand-ins (pacman's output as $CASE says, by what the repo it's given holds)
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
mkdir -p "$t/repo/ci" "$t/bin"
cp "$here/ci/install-test.sh" "$t/repo/ci/"
# mkdb <dir>: its database, from the packages there
mkdb() {
    local d f n
    d=$(mktemp -d "$t/db.XXXX")
    for f in "$1"/*.pkg.tar.zst; do
        f=${f##*/} n=${f%-*-*-*}
        mkdir "$d/$n"
        printf '%%FILENAME%%\n%s\n\n%%NAME%%\n%s\n\n' "$f" "$n" >"$d/$n/desc"
    done
    rm -f "$1/agros.db" && (cd "$d" && bsdtar -czf "$1/agros.db" -- *)
}
# (the hold: each new build named swapped for the published one, version 1, with its .sig; the names in $t/holds)
cat >"$t/repo/ci/build-repo.sh" <<S
#!/bin/bash
[[ \$2 == --hold-new ]] || exit 1
while IFS= read -r l; do
    n=\${l%%: *}; echo "\$n" >>$t/holds
    rm -f "\$1/\$n"-*; touch "\$1/\$n-1-1-x86_64.pkg.tar.zst" "\$1/\$n-1-1-x86_64.pkg.tar.zst.sig"
done <<<"\$AGROS_HOLD_ONLY"
S
printf '#!/bin/bash\n. %q\nmkdb "$1"\n' "$t/mkdb.sh" >"$t/repo/ci/repo-db.sh"
declare -f mkdb | sed "s|\$t/db|$t/db|" >"$t/mkdb.sh"
# (pacman: what's in the [agros] its config names; the config and the packages asked for kept, $t/conf, $t/asked)
cat >"$t/bin/pacman" <<'S'
#!/bin/bash
while [[ $1 != -Sy ]]; do [[ $1 != --config ]] || conf=$2; shift; done
shift
cp "$conf" "$T/conf"; echo "$*" >"$T/asked"; echo x >>"$T/tries"
repo=$(sed -n 's|^Server = file://||p' "$conf")
has() { [[ -e $(echo "$repo/$1"-*.pkg.tar.zst) ]]; }
for c in $CASE; do
    case $c in
        net) (($(wc -l <"$T/tries") > ${NETOK:-9})) || { echo "error: failed retrieving file 'x' from mirror : Could not resolve host: mirror"; exit 1; } ;;
        files) has caelestia-shell-2 && { printf '%s\n' 'error: failed to commit transaction (conflicting files)' \
            "caelestia-shell: /usr/bin/qs exists in both 'caelestia-shell' and 'quickshell'" 'Errors occurred, no packages were upgraded.'; exit 1; } ;;
        script) has agros-system-r9 && printf '%s\n' 'installing filesystem...' 'installing agros-system...' 'Setting up...' 'error: command failed to execute correctly'
            printf '%s\n' ':: Running post-transaction hooks...' '(1/2) Reloading system manager' 'error: command failed to execute correctly' ;;
        stuck) has agros-system-1 && { printf '%s\n' 'installing agros-system...' 'error: command failed to execute correctly'; } ;;
        arch) printf '%s\n' ':: foo and bar are in conflict. Remove bar? [y/N]' 'error: unresolvable package conflicts detected'; exit 1 ;;
        hookfail) printf '%s\n' 'installing foo...' ':: Running post-transaction hooks...' 'error: command failed to execute correctly' ;;
    esac
done
echo 'installing agros-desktop...'
S
printf '#!/bin/sh\necho "$*" >>%s/mounts\n' "$t" >"$t/bin/mount"
printf '#!/bin/sh\n' >"$t/bin/umount"
chmod +x "$t/bin/"* "$t/repo/ci/"*.sh
printf '[options]\nNoExtract = usr/share/man/*\n[cachyos]\nServer = x\n[core]\nInclude = y\n' >"$t/pacman.conf"
# go <CASE>: the hold= and note= lines, "|" between, after the repo made again (caelestia-shell, agros-system and
# agros-desktop new, quickshell kept as published)
go() {
    rm -rf "$t/r" "$t/out" "$t/holds" "$t/tries" && mkdir "$t/r"
    touch "$t/r/"{caelestia-shell-2-1,agros-system-r9-1,agros-desktop-5-1,quickshell-1-1}-x86_64.pkg.tar.zst \
        "$t/r/quickshell-1-1-x86_64.pkg.tar.zst.sig"
    mkdb "$t/r"
    CASE=$1 T=$t TMPDIR=$t PATH=$t/bin:$PATH PACMAN_CONF=$t/pacman.conf GITHUB_OUTPUT=$t/out AGROS_RETRY_WAIT=0 \
        "$t/repo/ci/install-test.sh" "$t/r" >"$t/log" 2>&1 || fail "install-test.sh failed ($1): $(cat "$t/log")"
    sed -e '/<<EOF$/d' -e '/^EOF$/d' "$t/out" | paste -sd'|'
}
[[ -z $(go "") ]] || fail "a release that installs: something held or said: $(go "")"
grep -qx -- '--noconfirm --noprogressbar base agros-desktop agros-system' "$t/asked" || fail "not base and every agros-* package asked for: $(cat "$t/asked")"
grep -q NoExtract "$t/conf" && fail "the container's NoExtract lines kept (files left out: their conflicts never seen)"
[[ $(sed -n '/^\[/p' "$t/conf" | paste -sd' ') == "[options] [cachyos] [core] [agros]" ]] || fail "not [agros] last, after the system's repos: $(cat "$t/conf")"
grep -qx "Server = file://$t/r" "$t/conf" || fail "not the release's [agros]: $(cat "$t/conf")"
grep -q "^proc $t/.*/root/proc -t proc" "$t/mounts" || fail "the root's /proc not mounted: $(cat "$t/mounts")"
# (a file conflict with a new build: it held, tried again with the published one, which installs)
[[ $(go files) == "caelestia-shell: a new install fails with its new build: caelestia-shell: /usr/bin/qs exists in both 'caelestia-shell' and 'quickshell'" ]] ||
    fail "a file conflict's new build not held: $(go files)"
[[ $(cat "$t/holds") == caelestia-shell && $(wc -l <"$t/tries") == 2 ]] || fail "not tried again with it held: $(cat "$t/holds" "$t/log")"
# (an install script of [agros]'s failing, pacman going on: held; a hook's failing: not judged)
[[ $(go script) == "agros-system: a new install fails with its new build: its install script failed" ]] ||
    fail "an install script failing not held: $(go script)"
[[ -z $(go hookfail) ]] || fail "a hook's failure, or another repo's package's script, held or said: $(go hookfail)"
# (its published one fails too: not held, no help, said)
[[ $(go "script stuck") == "agros-system: a new install fails with it, as published too (not held: no help): its install script failed" ]] ||
    fail "one whose published one fails too held, or not said: $(go "script stuck")"
# (two of Arch's packages in conflict: nothing of [agros]'s to hold, said)
[[ $(go arch) == "a new install fails, nothing of [agros]'s to hold: :: foo and bar are in conflict. Remove bar? [y/N] error: unresolvable package conflicts detected" ]] ||
    fail "a failure naming no [agros] package not said: $(go arch)"
# (a download failing: tried again, then passing; failing 3 times: said as not run, nothing held)
[[ -z $(NETOK=2 go net) && $(wc -l <"$t/tries") == 3 ]] || fail "a download failing twice not tried again: $(cat "$t/log")"
[[ $(go "net files") == "the install test couldn't run (a download kept failing, or no room: not known whether it installs): error: failed retrieving file 'x' from mirror : Could not resolve host: mirror" ]] &&
    [[ $(wc -l <"$t/tries") == 3 ]] || fail "a download that kept failing not said as not run: $(go "net files")"
echo "ok ci-install-test"
