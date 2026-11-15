#!/usr/bin/env bash
# agros-system's auto-update-aur (the boot's AUR builds), its paths in a throwaway folder, pacman, the AUR (curl, git),
# agros-each-user, bwrap and makepkg stand-ins: what it builds (a newer AUR version; Quickshell for a new Qt, not a
# -bin, not one its repo rebuilt in the same download), as whom (the user through setpriv, never root, never PAM), where
# (every step that touches what the AUR sent in the sandbox; the network, its own through pasta, only to fetch and
# build), what it keeps (only the packages the plan names), and how it ends (those built: their repo and list for the
# shutdown's install; one failed: said, the others still built). Then the real sandbox (bwrap, unprivileged, where it
# can run): what it hides, the download's packages over /usr, and the build account's part refusing root; its network
# closed off to the host's addresses (in a user and network namespace of its own, where one can be made); with pasta
# there too, the host's loopback, abstract sockets, other addresses and gateway mapping out of its reach, the internet
# not
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
mkdir -p "$t/bin" "$t/au" "$t/cache"
me=$(id -un)
sed -e "s|/var/lib/auto-update|$t/au|g" -e "s|/usr/lib/agros/auto-update-aur|$t/auto-update-aur|g" \
    -e "s|/usr/lib/agros/bin/|$here/.local/bin/|g" "$here/packages/agros-system/auto-update-aur" >"$t/auto-update-aur"
chmod +x "$t/auto-update-aur"
# (AgrOS's fixes for AUR packages beside it, as installed: aur-agros-patch, aur-patches/)
cp -r "$here/packages/agros-system/aur-agros-patch" "$here/packages/agros-system/aur-patches" "$t/"
stub() { printf '#!/bin/bash\n%s\n' "$2" >"$t/bin/$1"; chmod +x "$t/bin/$1"; }
# agros-each-user: --as runs the command (noted); the build account: this user here (agros-aur on the system; the
# users agros-each-user lists aren't asked for)
# shellcheck disable=SC2016  # (expanded by the stand-ins)
stub agros-each-user 'case $1 in --list) echo "list" >>'"$t"'/calls; echo someone ;; --as) echo "as $2" >>'"$t"'/calls; shift 2; exec "$@" ;; esac'
export AGROS_EACH_USER=$t/bin/agros-each-user AGROS_AUR_USER=$me
# Through PAM (a logind session for the user, out of the service's cgroup): never
for c in runuser sudo su; do stub "$c" 'echo "PAM '"$c"'" >>'"$t"'/calls; exit 1'; done
# pacman, on the download's lists: what it brings ($PENDING), the foreign ones ($FOREIGN), Qt's dependents, what's in
# Python 3.13's folder, the installed versions; what the builds need and isn't installed ($NEED), and its download
# (noted, with whether the boot's "downloading" mark was there: update-apps waits on it)
# shellcheck disable=SC2016
stub pacman 'foreign=${FOREIGN:-equibop quickshell-git}
case "$1" in
    -Qu) printf "%s\n" "$PENDING" ;;
    -Qmq) printf "%s\n" $foreign ;;
    -Slq) true ;;
    -Qi) echo "Name            : qt6-base"; echo "Required By     : quickshell-git  darkly-bin  kconfig"; echo "Optional For    : None" ;;
    -Qoq) [ "${@: -1}" = /usr/lib/python3.13/ ] && printf "%s\n" python ${QOQ:-python-foo} python-repo ;;
    -Q) case " $foreign " in *" $2 "*) echo "$2 $( [ "$2" = quickshell-git ] && echo 0.3-1 || echo 1.0-1 )" ;; *) exit 1 ;; esac ;;
    -T) echo "pacman $*" >>'"$t"'/calls; [ -n "${NEED:-}" ] && echo "$NEED"; true ;;
    -Sw) echo "pacman $*" >>'"$t"'/calls; echo "download $( [ -e '"$t"'/au/downloading ] && echo marked || echo unmarked)" >>'"$t"'/calls ;;
    -Sp) if [ -n "${SP_UNSAT:-}" ] && [ "${@: -1}" = "$SP_UNSAT" ]; then
             [ -n "${SP_HELD:-}" ] || { echo "error: target not found: $SP_UNSAT" >&2; exit 1; }; echo "$SP_HELD"; exit 0; fi
         if [ -n "${SP_UNSAT:-}" ]; then echo "error: failed to prepare transaction (could not satisfy dependencies)" >&2
             echo ":: unable to satisfy dependency '"'"'$SP_UNSAT'"'"' required by ${@: -1}" >&2; exit 1; fi
         # ($SP_NOTFOUND: no such target at that version; by its name alone, there when $SP_BARE. $SP_OTHER: another error)
         if [ -n "${SP_OTHER:-}" ]; then echo "error: $SP_OTHER" >&2; exit 1; fi
         if [ -n "${SP_NOTFOUND:-}" ]; then
             case ${@: -1} in *[\<\>=]*) echo "error: target not found: ${@: -1}" >&2; exit 1 ;; esac
             [ -n "${SP_BARE:-}" ] || { echo "error: target not found: ${@: -1}" >&2; exit 1; }; echo "${@: -1}"; exit 0
         fi
         [ -z "${SP_GOT:-}" ] || printf "%s\n" $SP_GOT ;;
    -Sup) printf "%s\n" "$PENDING" | while read -r n _ _ v; do [ -n "$v" ] && echo "$n-$v-x86_64.pkg.tar.zst"; done
        [ -z "${SUP_EXTRA:-}" ] || echo "$SUP_EXTRA" ;;
esac'
stub pacman-conf '[ "$1" = CacheDir ] && echo '"$t/cache/"'; true'
# The AUR: its versions (equibop newer; darkly-bin and kconfig are no concern of it)
# (name=version, or name/base=version for one of a split base)
aur_has() { stub curl "echo '{\"results\":[$(for x; do n=${x%=*}; printf '{"Name":"%s","PackageBase":"%s","Version":"%s"},' "${n%/*}" "${n#*/}" "${x#*=}"; done | sed 's/,$//')]}'"; }
aur_has equibop=1.1-1 quickshell-git=0.1-1 caelestia-shell=1.1-1 python-foo=1.0-1
# The host's addresses and routes (ip -j): its LAN (eth0, the address pasta gives the sandbox), docker0 (IPv4 and IPv6),
# a VPN's tunnel route, loopback and link-local ones; the routes the sandbox's network is closed off with noted (the
# LAN's is pasta's own there already: kept). $IP_FAIL: none can be added
export IP_ADDR='[{"ifname":"lo","addr_info":[{"local":"127.0.0.1","prefixlen":8,"scope":"host"},{"local":"::1","prefixlen":128,"scope":"host"}]},
 {"ifname":"eth0","addr_info":[{"local":"192.168.1.50","prefixlen":24,"scope":"global"},{"local":"fe80::1","prefixlen":64,"scope":"link"}]},
 {"ifname":"docker0","addr_info":[{"local":"172.17.0.1","prefixlen":16,"scope":"global"},{"local":"fd00:1::5","prefixlen":64,"scope":"global"}]}]'
export IP_R4='[{"dst":"default","gateway":"192.168.1.1","dev":"eth0"},{"dst":"192.168.1.0/24","dev":"eth0"},{"dst":"172.17.0.0/16","dev":"docker0"},
 {"dst":"169.254.0.0/16","dev":"eth0"},{"dst":"10.8.0.1","dev":"tun0"}]'
export IP_R6='[{"dst":"fd00:1::/64","dev":"docker0"},{"dst":"fe80::/64","dev":"eth0"},{"dst":"default","gateway":"fe80::1","dev":"eth0"}]'
# shellcheck disable=SC2016
stub ip 'case "$*" in
    "-j addr show") echo "$IP_ADDR" ;; "-j -4 route show table main") echo "$IP_R4" ;; "-j -6 route show table main") echo "$IP_R6" ;;
    *" add prohibit "*) echo "ip $*" >>'"$t"'/calls; [ -z "${IP_FAIL:-}" ] && [ "${@: -1}" != 192.168.1.0/24 ] ;;
    *" show exact 192.168.1.0/24") [ -n "${IP_FAIL:-}" ] || echo "192.168.1.0/24 dev eth0" ;;
    *" show exact "*) true ;;
    *) exit 1 ;;
esac'
# pasta (the sandbox's own network): noted, then its command
# shellcheck disable=SC2016
stub pasta 'echo "pasta $*" >>'"$t"'/calls; while [ "$1" != -- ]; do shift; done; shift; exec "$@"'
# The sandbox: noted, then the command as is ($SANDBOXED for it, the environment bwrap's env -i sets left out: the
# stand-ins are on PATH)
# shellcheck disable=SC2016
stub bwrap 'echo "bwrap $*" >>'"$t"'/calls; while [ "$1" != -- ]; do shift; done; shift
[ "$1" = env ] && { shift; while [[ $1 == -i || $1 == *=* ]]; do shift; done; }; SANDBOXED=1 exec "$@"'
# (Caelestia needs Quickshell, which quickshell-git provides)
# shellcheck disable=SC2016
stub git 'echo "git $* ${SANDBOXED:+(sandboxed)}" >>'"$t"'/calls; d=${@: -1}; mkdir -p "$d"
printf "pkgbase = %s\n\tmakedepends = ${MAKEDEP:-cmake}\n" "${d##*/}" >"$d/.SRCINFO"
printf "pkgname=%s\npkgrel=1\n" "${d##*/}" >"$d/PKGBUILD"
case ${d##*/} in
    caelestia-shell) printf "\tdepends = quickshell>=0.2\npkgname = caelestia-shell\n" >>"$d/.SRCINFO" ;;
    quickshell-git) printf "pkgname = quickshell-git\n\tprovides = quickshell=0.3\n" >>"$d/.SRCINFO" ;;
esac'
stub gpg 'true'
# makepkg: its sources checked (--verifysource, noted; with $FIFO, the PKGBUILD it sources leaves a FIFO for its
# .SRCINFO, which would block its read); a package (its .PKGINFO), or a failure for $FAIL_BASE; with $SNEAK, a sudo
# package beside it too, and a link to a file of the user's
# shellcheck disable=SC2016
stub makepkg 'b=${PWD##*/}
case " $* " in *" --verifysource "*) echo "verify $b $SRCDEST $(grep "^pkgrel=" PKGBUILD) ${SANDBOXED:+(sandboxed)}" >>'"$t"'/calls
    [ -z "${FIFO:-}" ] || { rm .SRCINFO; mkfifo .SRCINFO; }; exit 0 ;; esac
[ "$b" = "${FAIL_BASE:-}" ] && { echo "==> ERROR: build failed"; exit 1; }
case $b in equibop | caelestia-shell) v=1.1-1 ;; python-foo) v=1.0-1 ;; *) v=0.4-1 ;; esac
pk() { local d; d=$(mktemp -d); printf "pkgname = %s\npkgver = %s\narch = x86_64\n" "$1" "$2" >"$d/.PKGINFO"
    bsdtar -cf "$PKGDEST/$1-$2-x86_64.pkg.tar.zst" -C "$d" .PKGINFO; rm -rf "$d"; }
pk "$b" "$v"
[ -n "${SNEAK:-}" ] && { pk sudo 9.9-1; ln -s '"$t"'/secret "$PKGDEST/zz-1-1-x86_64.pkg.tar.zst"; }
echo "built $b ${SANDBOXED:+(sandboxed)}" >>'"$t"'/calls'
# shellcheck disable=SC2016
stub repo-add 'shift; : >"$1"; ln -sf "${1##*/}" "${1%.tar.gz}"'
export PATH=$t/bin:$PATH
aur=$t/au/aur
build=$t/au/aur-build

# A new Qt in the download: Quickshell rebuilt for it (not darkly-bin, prebuilt; not kconfig, a repo's), and equibop's
# newer version; as the user, in the sandbox, the download's packages unpacked under it (a new dependency the
# transaction brings too, not only what pacman -Qu lists)
: >"$t/cache/qt6-base-6.10.0-1-x86_64.pkg.tar.zst"; : >"$t/cache/libnew-1.0-1-x86_64.pkg.tar.zst"
export PENDING="qt6-base 6.9.0-1 -> 6.10.0-1"
echo "the user's secret" >"$t/secret"
SUP_EXTRA=libnew-1.0-1-x86_64.pkg.tar.zst SNEAK=1 "$t/auto-update-aur" "$t/db" >"$t/out" 2>&1 || fail "the builds failed: $(cat "$t/out")"
[[ $(cat "$aur/rebuild") == quickshell-git && $(cat "$aur/runtime-target") == "qt6-base 6.10.0-1 " ]] ||
    fail "Quickshell not the one to rebuild for the new Qt: $(cat "$aur/rebuild")"
[[ $(cat "$aur/plan") == $'equibop equibop\nquickshell-git quickshell-git' ]] || fail "the plan: $(cat "$aur/plan")"
grep -q "^PAM" "$t/calls" && fail "run through PAM (runuser, su, sudo: a logind session): $(grep '^PAM' "$t/calls")"
[[ $(grep -c "^as $me$" "$t/calls") -ge 5 ]] || fail "not run as the build account: $(cat "$t/calls")"
grep -qx list "$t/calls" && fail "the users looked for: the builds are no user's"
grep '^as ' "$t/calls" | grep -vx "as $me" && fail "run as another account than the build one"
# (every step on what the AUR sent in the sandbox: git's clone and the sources' download (the network), the builds
# (none))
grep -E '^(git|verify|built) ' "$t/calls" | grep -v '(sandboxed)$' && fail "a step on what the AUR sent ran outside the sandbox"
[[ $(grep -c '^built .*(sandboxed)$' "$t/calls") == 2 && $(grep -c '^git clone .*(sandboxed)$' "$t/calls") == 2 &&
    $(grep -c '^verify .*(sandboxed)$' "$t/calls") == 2 ]] || fail "not fetched, checked and built in the sandbox: $(cat "$t/calls")"
# (the network: only the fetch, each base on its own, and the builds; each through pasta, its namespace's own, no
# port of the host's forwarded either way nor its gateway mapped to the host's loopback)
pastas=$(grep '^pasta ' "$t/calls")
[[ $(grep -c -- "--fetch $build equibop$" <<<"$pastas") == 1 && $(grep -c -- "--fetch $build quickshell-git$" <<<"$pastas") == 1 &&
    $(grep -c -- '--build ' <<<"$pastas") == 2 && $(wc -l <<<"$pastas") == 4 ]] || fail "the network for other than the fetch and builds: $pastas"
grep -v -- ' -t none -u none -T none -U none --no-map-gw --map-guest-addr none ' <<<"$pastas" && fail "pasta forwards the host's ports or maps its loopback"
# (DNS: an address of each family; the host's addresses and networks closed off in the namespace before bwrap, not its
# loopback, link-local ones nor the default route; the LAN pasta gives it kept)
jail="--jail 10.8.0.1/32 172.17.0.0/16 172.17.0.1/32 192.168.1.0/24 192.168.1.50/32 fd00:1::/64 fd00:1::5/128 -- bwrap "
grep -vF -- "--dns-forward 169.254.0.53 --dns-forward fd53:a6e4:2c3a::53 -- $t/auto-update-aur $jail" <<<"$pastas" &&
    fail "the sandbox's network not closed off to the host's addresses, or DNS of one family: $pastas"
[[ $(grep -c '^ip route add prohibit 172.17.0.1/32$' "$t/calls") == 4 && $(grep -c '^ip -6 route add prohibit fd00:1::/64$' "$t/calls") == 4 ]] ||
    fail "the host's addresses not closed off in the namespace: $(grep '^ip' "$t/calls")"
[[ $(grep '^bwrap' "$t/calls" | grep -c -- "--share-net --unshare-user --uid $(id -u) --gid $(id -g) --ro-bind .* $(readlink -f /etc/resolv.conf)") == 4 &&
    $(grep '^bwrap' "$t/calls" | grep -c -- '--share-net') == 4 ]] || fail "the sandbox's network not pasta's alone: $(grep '^bwrap.*--share-net' "$t/calls")"
# (each base's sources in a folder of its own: same-named sources don't collide)
grep -q "^verify equibop $build/src/equibop " "$t/calls" && grep -q "^verify quickshell-git $build/src/quickshell-git " "$t/calls" ||
    fail "the bases' sources share a folder: $(grep '^verify' "$t/calls")"
# (AgrOS's fix added to Quickshell's build files as fetched, as [agros]'s build has it (aur-agros-patch); none to equibop)
grep -q "^verify quickshell-git .* pkgrel=1.1 " "$t/calls" && grep -q "^verify equibop .* pkgrel=1 " "$t/calls" ||
    fail "Quickshell's rebuild without AgrOS's fix: $(grep '^verify' "$t/calls")"
builds=$(grep -- '--build ' "$t/calls" | grep '^bwrap')
[[ $(wc -l <<<"$builds") == 2 ]] && grep -q -- "--overlay-src /usr --overlay-src $build/stage/usr --ro-overlay /usr" <<<"$builds" ||
    fail "the build doesn't see the download's packages over /usr: $builds"
grep '^bwrap' "$t/calls" | grep -E -- '--(ro-)?bind / |--bind /home|--bind /run|--bind /var |--unshare-net' &&
    fail "the sandbox sees the whole system, or its own network option"
grep '^bwrap' "$t/calls" | grep -v -- '--unshare-all ' && fail "a sandbox not in namespaces of its own"
grep -qxF "$t/cache/qt6-base-6.10.0-1-x86_64.pkg.tar.zst" <<<"$(tr ' ' '\n' <"$t/calls")" ||
    fail "the download's Qt not unpacked for the build: $(grep unpack "$t/calls")"
grep -qxF "$t/cache/libnew-1.0-1-x86_64.pkg.tar.zst" <<<"$(tr ' ' '\n' <"$t/calls")" ||
    fail "a new dependency the download brings not unpacked for the build: $(grep unpack "$t/calls")"
[[ $(sort "$aur/built") == $'equibop 1.1-1\nquickshell-git 0.4-1' && -e $aur/repo/agros-aur.db && -e $aur/planned && ! -e $aur/failed ]] ||
    fail "the builds not collected for the shutdown: $(cat "$aur/built" 2>/dev/null) $(cat "$t/out")"
# (only the plan's: not the sudo a build left beside its own, nor a link to the user's file)
[[ -z $(find "$aur/repo" -name 'sudo-*' -o -name 'zz-*') ]] && ! grep -rq "secret" "$aur" ||
    fail "a package the plan doesn't name collected, or the user's file read: $(ls "$aur/repo")"
grep -q "made sudo-9.9-1-x86_64.pkg.tar.zst, which isn't one planned" "$t/out" || fail "the package left out not said: $(cat "$t/out")"
# (the build folder made anew and gone after; its logs root's own, not in it)
[[ ! -e $build && -e $aur/log/equibop.log && -s $aur/log/fetch.log ]] || fail "the build folder left, or the logs not root's: $(ls "$build" 2>&1) $(wc -c "$aur"/log/*)"

# One fails: said (by its base), the others still built and collected (each one on its own)
: >"$t/calls"
FAIL_BASE=quickshell-git "$t/auto-update-aur" "$t/db" >"$t/out" 2>&1 && fail "a failed build reported success"
[[ $(cat "$aur/failed") == "quickshell-git: its build failed"* && -e $aur/planned && ! -e $build ]] || fail "a failed build not written down: $(cat "$aur/failed" 2>/dev/null)"
grep -q "build failed" "$t/out" || fail "the build's own error not in the log: $(cat "$t/out")"
[[ $(cat "$aur/built") == "equibop 1.1-1" && -e $aur/repo/agros-aur.db && -z $(find "$aur/repo" -name 'quickshell-git-*') ]] ||
    fail "the others not built beside a failed one: $(cat "$aur/built" 2>/dev/null) $(ls "$aur/repo")"

# A .SRCINFO's dependency that would be an option to root's pacman: refused, never passed on
: >"$t/calls"
# (and never written down as it is: dotfiles-check shows it in a notification, which renders links and images)
MAKEDEP='--dbpath=/tmp/x ![i](https://e.vil/x.png)' "$t/auto-update-aur" "$t/db" >"$t/out" 2>&1 && fail "an option for a dependency reported success"
[[ $(cat "$aur/failed") == $'equibop: it needs something that isn\'t a package\'s name: --dbpath=tmpxihttpse.vilx.png\nquickshell-git: it needs something that isn\'t a package\'s name: --dbpath=tmpxihttpse.vilx.png' ]] &&
    ! grep -q '^pacman -T' "$t/calls" ||
    fail "an option for a dependency reached pacman: $(cat "$aur/failed") $(cat "$t/calls")"
# (an ordinary one: after --)
MAKEDEP='cmake>=3.20' "$t/auto-update-aur" "$t/db" >/dev/null 2>&1 || fail "the builds with a versioned dependency failed"
grep -q "^pacman -T --dbpath $t/db -- cmake>=3.20\( \|$\)" "$t/calls" || fail "the dependencies not after --: $(grep '^pacman -T' "$t/calls")"

# A .SRCINFO that's a FIFO (a build can leave one): not waited on for good, that one not built
: >"$t/calls"
FIFO=1 timeout 120 "$t/auto-update-aur" "$t/db" >"$t/out" 2>&1 && fail "a FIFO for a .SRCINFO reported success"
[[ $(sort "$aur/failed") == $'equibop: it has no .SRCINFO\nquickshell-git: it has no .SRCINFO' ]] || fail "a FIFO .SRCINFO not refused: $(cat "$aur/failed" 2>/dev/null) $(cat "$t/out")"
# The sandbox's network that can't be closed off: nothing fetched through it
: >"$t/calls"
IP_FAIL=1 "$t/auto-update-aur" "$t/db" >"$t/out" 2>&1 && fail "a network not closed off reported success"
grep -q '^git ' "$t/calls" && fail "fetched with the host's addresses open"
grep -q "couldn't be closed off in the sandbox's network" "$aur/log/fetch.log" || fail "the network not closed off not said: $(cat "$aur/log/fetch.log")"
# Quickshell rebuilt by its repo in the same download: not built here; no new Qt, nothing newer: nothing built
: >"$t/calls"
PENDING=$'qt6-base 6.9.0-1 -> 6.10.0-1\nquickshell-git 0.3-1 -> 0.3-2' "$t/auto-update-aur" "$t/db" >/dev/null
[[ ! -s $aur/rebuild ]] && ! grep -q "built quickshell" "$t/calls" || fail "Quickshell built though its repo rebuilt it"
aur_has equibop=1.0-1
: >"$t/calls"
PENDING="foo 1-1 -> 2-1" "$t/auto-update-aur" "$t/db" >/dev/null || fail "nothing to build failed"
[[ -e $aur/planned && ! -e $aur/plan && ! -e $aur/runtime-target ]] && ! grep -q built "$t/calls" || fail "built with nothing newer: $(cat "$t/calls")"

# Built in dependency order, not by name: Caelestia (needing quickshell) after quickshell-git (providing it)
aur_has quickshell-git=0.4-1 caelestia-shell=1.1-1
: >"$t/calls"
FOREIGN="caelestia-shell quickshell-git" PENDING="foo 1-1 -> 2-1" "$t/auto-update-aur" "$t/db" >"$t/out" 2>&1 || fail "the builds failed: $(cat "$t/out")"
[[ $(grep '^built' "$t/calls" | cut -d' ' -f1-2 | paste -sd' ') == "built quickshell-git built caelestia-shell" ]] ||
    fail "not built in dependency order: $(grep '^built' "$t/calls")"
# A build that comes out older than the AUR's version: not taken (a planned one missing fails its base)
aur_has quickshell-git=0.5-1
FOREIGN=quickshell-git PENDING="foo 1-1 -> 2-1" "$t/auto-update-aur" "$t/db" >"$t/out" 2>&1 && fail "a build older than planned reported success"
[[ $(cat "$aur/failed") == "quickshell-git: its build didn't make quickshell-git" && ! -s $aur/built ]] || fail "a build older than planned taken: $(cat "$aur/failed" 2>/dev/null)"
# A new Python (3.13 -> 3.14): the AUR's packages in its old folder (python-foo, the same version) rebuilt for it, not
# the repo's (python-repo); what the builds need downloaded under the boot's "downloading" mark (update-apps waits on
# it: never two writing pacman's cache), the mark gone for the builds after it
aur_has python-foo=1.0-1
: >"$t/calls"
FOREIGN=python-foo NEED=cmake PENDING="python 3.13.7-1 -> 3.14.0-1" "$t/auto-update-aur" "$t/db" >"$t/out" 2>&1 ||
    fail "the Python rebuild failed: $(cat "$t/out")"
[[ $(cat "$aur/rebuild") == python-foo && $(cat "$aur/runtime-target") == "python 3.14.0-1 " ]] && grep -q "^built python-foo" "$t/calls" ||
    fail "the AUR's Python package not rebuilt for the new Python: $(cat "$aur/rebuild" 2>/dev/null) $(cat "$t/calls")"
grep -qx "download marked" "$t/calls" && grep -q "^pacman -Sw .* -- cmake$" "$t/calls" && [[ ! -e $t/au/downloading ]] ||
    fail "the builds' download not under the boot's mark, or the mark left through the builds: $(cat "$t/calls")"
# The same, with pacman.conf holding it back (IgnorePkg): not built, and why that runtime waits said (not an empty reason),
# under its AUR base's name (one of a split base here), as every drop is
aur_has python-foo/foo-split=1.0-1
stub pacman-conf '[ "$1" = CacheDir ] && echo '"$t/cache/"'; case " $* " in *" IgnorePkg "*) echo "python-f*" ;; esac; true'
: >"$t/calls"
FOREIGN=python-foo PENDING="python 3.13.7-1 -> 3.14.0-1" "$t/auto-update-aur" "$t/db" >"$t/out" 2>&1 &&
    fail "a rebuild pacman.conf holds back reported success"
[[ $(cat "$aur/failed") == "foo-split: pacman.conf holds it back (IgnorePkg): it can't be rebuilt for the new python 3.14.0-1" ]] &&
    ! grep -q "^built " "$t/calls" || fail "a held-back rebuild built, or its reason not said: $(cat "$aur/failed" 2>/dev/null)"
# ...its base's other package, not held, not built either (the base is one build), and the base said once
aur_has python-foo/foo-split=1.0-1 python-bar/foo-split=1.0-1
: >"$t/calls"
FOREIGN="python-foo python-bar" QOQ="python-foo python-bar" PENDING="python 3.13.7-1 -> 3.14.0-1" "$t/auto-update-aur" "$t/db" >"$t/out" 2>&1 &&
    fail "a split base with one package held back reported success"
[[ $(cat "$aur/failed") == "foo-split: pacman.conf holds it back (IgnorePkg): it can't be rebuilt for the new python 3.14.0-1" ]] &&
    ! grep -q "^built " "$t/calls" || fail "a split base with one package held back built, or not said once: $(cat "$aur/failed" 2>/dev/null) / $(grep '^built' "$t/calls")"
# ...and the one held not a rebuild itself (only its sibling is): the base not built either, said
stub pacman-conf '[ "$1" = CacheDir ] && echo '"$t/cache/"'; case " $* " in *" IgnorePkg "*) echo "python-bar" ;; esac; true'
: >"$t/calls"
FOREIGN="python-foo python-bar" PENDING="python 3.13.7-1 -> 3.14.0-1" "$t/auto-update-aur" "$t/db" >"$t/out" 2>&1 &&
    fail "a split base with a package held (not a rebuild) reported success"
[[ $(cat "$aur/failed") == "foo-split: python-bar, of the same build, is held back by pacman.conf (IgnorePkg): not built" ]] &&
    ! grep -q "^built " "$t/calls" || fail "a split base built beside its held package: $(cat "$aur/failed" 2>/dev/null) / $(grep '^built' "$t/calls")"
aur_has python-foo=1.0-1
# ...and one needing what pacman.conf holds back (the upstream gate's Hyprland libraries: pacman takes it when asked by
# name): not built against it, said
stub pacman-conf '[ "$1" = CacheDir ] && echo '"$t/cache/"'; case " $* " in *" IgnorePkg "*) echo "hyprutils" ;; esac; true'
: >"$t/calls"
FOREIGN=python-foo NEED="hyprutils>=0.15" SP_GOT="hyprutils" PENDING="python 3.13.7-1 -> 3.14.0-1" "$t/auto-update-aur" "$t/db" >"$t/out" 2>&1 &&
    fail "a build needing a held-back package reported success"
[[ $(cat "$aur/failed") == "python-foo: hyprutils, which it needs, is held back by pacman.conf (IgnorePkg: hyprutils)" ]] &&
    ! grep -q "^built python-foo" "$t/calls" && ! grep -q "^pacman -Sw" "$t/calls" ||
    fail "built against a held-back package, or why not said: $(cat "$aur/failed" 2>/dev/null) / $(cat "$t/calls")"
# ...or what needs a held one's newer version (pacman can't satisfy it), not as missing from the repos; and the same
# words for one the repos don't have at all, not blamed on the gate; and one the repos have only older
reason() {
    : >"$t/calls"
    FOREIGN=python-foo NEED=$1 PENDING="python 3.13.7-1 -> 3.14.0-1" "$t/auto-update-aur" "$t/db" >"$t/out" 2>&1 &&
        fail "a build whose dependency can't be had reported success ($1)"
    grep -q "^built python-foo" "$t/calls" && fail "built with a dependency that can't be had ($1)"
    cat "$aur/failed"
}
[[ $(SP_UNSAT="hyprutils>=0.15" SP_HELD=hyprutils reason "hyprtoolkit>=0.5") == "python-foo: hyprtoolkit, which it needs, needs a newer hyprutils, which pacman.conf holds back (IgnorePkg)" ]] ||
    fail "a dependency needing a held package's newer version not said so: $(cat "$aur/failed")"
[[ $(SP_UNSAT=aurpkg reason "needsaur") == "python-foo: needsaur, which it needs, needs aurpkg, which isn't in the repos (at that version)" ]] ||
    fail "a dependency needing what no repo has blamed on the gate: $(cat "$aur/failed")"
[[ $(SP_NOTFOUND=1 SP_BARE=1 reason "libfoo.so=2-64") == "python-foo: libfoo.so, which it needs, is in the repos only at an older version than it needs" ]] ||
    fail "a library the repos have only at an older soname said as missing: $(cat "$aur/failed")"
[[ $(SP_OTHER="failed to prepare transaction (conflicting dependencies)" reason "foo") == "python-foo: foo, which it needs, couldn't be worked out: error: failed to prepare transaction (conflicting dependencies)" ]] ||
    fail "another failure of pacman's said as something else: $(cat "$aur/failed")"
[[ $(SP_NOTFOUND=1 reason "aur-only-thing") == "python-foo: aur-only-thing, which it needs, isn't in the repos (only the AUR: Updates builds it)" ]] ||
    fail "a dependency only the AUR has not said so: $(cat "$aur/failed")"
[[ $(SP_NOTFOUND=1 SP_BARE=1 reason "hyprtoolkit>=9") == "python-foo: hyprtoolkit, which it needs, is in the repos only at an older version than it needs" ]] ||
    fail "a dependency the repos have only older said as missing: $(cat "$aur/failed")"
stub pacman-conf '[ "$1" = CacheDir ] && echo '"$t/cache/"'; true'
# The AUR out of reach: said
stub curl 'exit 7'
PENDING="foo 1-1 -> 2-1" "$t/auto-update-aur" "$t/db" >/dev/null && fail "the AUR out of reach reported success"
[[ $(cat "$aur/failed") == "the AUR couldn't be reached" ]] || fail "the AUR out of reach not said"
# The new runtimes (update-kinds' one list) from a stdin list ("qt6-base <new> "), nothing for a rebuild of the same
# version; Python: only its minor version counts (a new 3.14.x needs nothing rebuilt)
kinds=$here/.local/bin/update-kinds
[[ $("$kinds" --runtime-target <<<"qt6-base 6.9.0-1 -> 6.9.0-2") == "" ]] || fail "a Qt rebuild taken for a new Qt"
[[ $("$kinds" --runtime-target <<<$'python 3.13.7-1 -> 3.14.0-1\nfoo 1-1 -> 2-1') == "python 3.14.0-1 " &&
    $("$kinds" --runtime-target <<<"python 3.14.0-1 -> 3.14.1-1") == "" ]] || fail "Python's new minor version not told from a bugfix one"

# The network's closing off, for real where a user can make a user and network namespace (as pasta's): the host's
# addresses and networks unreachable (prohibit: refused at once), a route the namespace has already (the LAN pasta
# gives it) kept, and one that can't be added stopping it before its command
sys_path=/usr/bin:/bin
if PATH=$sys_path unshare -rn true 2>/dev/null; then
    # shellcheck disable=SC2016  # (the namespace's shell's)
    out=$(PATH=$sys_path unshare -rn bash -c 'ip link set lo up && ip route add 10.98.0.0/16 dev lo &&
        exec "$0" --jail 10.98.0.0/16 192.0.2.7/32 2001:db8::/32 -- bash -c "ip route; ip -6 route; exec 3<>/dev/tcp/192.0.2.7/80"' \
        "$t/auto-update-aur" 2>&1) || true
    [[ $out == *"prohibit 192.0.2.7"* && $out == *"prohibit 2001:db8::/32"* && $out == *"10.98.0.0/16 dev lo"* &&
        $out == *"Permission denied"* ]] || fail "the host's addresses not closed off in a real namespace: $out"
    out=$(PATH=$sys_path unshare -rn "$t/auto-update-aur" --jail 10.0.0.5/8 -- echo ran 2>&1) && fail "a network not closed off ran its command: $out"
    [[ $out != *ran* ]] || fail "a network not closed off ran its command: $out"
else
    skipped "no user and network namespace here: the sandbox's network closing off not run for real"
fi

# The real sandbox, where this machine lets a user make one (an unprivileged bwrap)
real=$(command -v -p bwrap || true)
if [[ -n $real ]] && "$real" --unshare-all --ro-bind / / true 2>/dev/null; then
    rm "$t/bin/bwrap"
    # (pasta: the real one where it's installed and can make its namespace here (/dev/net/tun, user namespaces); else
    # the stand-in, its command run as it is, for what's hidden)
    pasta=$(command -v -p pasta || true)
    if [[ -n $pasta ]] && ! why=$("$pasta" --config-net --quiet -t none -u none -T none -U none -- true 2>&1); then
        skipped "pasta can't make its namespace here ($(tail -n 2 <<<"$why" | paste -sd' '); ptrace_scope $(cat /proc/sys/kernel/yama/ptrace_scope 2>/dev/null), AppArmor $(cat /sys/module/apparmor/parameters/enabled 2>/dev/null)): its stand-in used"
        pasta=
    fi
    [[ -z $pasta ]] || rm "$t/bin/pasta" "$t/bin/ip"
    sb=$t/sb
    mkdir -p "$sb/stage/usr/share" "$sb/stage/usr/lib"
    echo staged >"$sb/stage/usr/share/agros-staged"
    # (one over a file /usr has: the download's version above the system's)
    echo "staged os-release" >"$sb/stage/usr/lib/os-release"
    # shellcheck disable=SC2016  # (the sandbox's shell's)
    probe='for p in /home /root /run/dbus /run/media /run/user /mnt /media /srv /var/lib/auto-update /var/cache; do [ -e $p ] && echo "sees $p"; done
        [ -z "$(ls -A /var/tmp)$(ls -A /tmp/home)" ] || echo "sees /var/tmp or a home with something in it"
        echo "$HOME" >"$HOME/w" || echo "its home not writable"
        [ "$(id -u)" = '"$(id -u)"' ] || echo "not as the user: $(id -u)"
        echo "net $(grep -c : /proc/net/dev)"; cat /usr/share/agros-staged 2>/dev/null; touch /usr/x 2>/dev/null && echo "/usr writable"
        grep -qx "staged os-release" /usr/lib/os-release && echo "staged over"; true'
    out=$("$t/auto-update-aur" --sandbox run "$sb" -- sh -c "$probe" 2>&1) || fail "the real sandbox didn't run: $out"
    [[ $out == "net 1" ]] || fail "the sandbox sees too much, or has a network: $out"
    out=$("$t/auto-update-aur" --sandbox build "$sb" -- sh -c "$probe" 2>&1) || fail "the real build sandbox didn't run: $out"
    [[ $out == "net "*$'\nstaged' || $out == "net "*$'\nstaged\nstaged over' ]] && [[ $out != *sees* && $out != *"not "* && $out != *writable* ]] ||
        fail "the build's sandbox sees too much, or misses the download's packages: $out"
    [[ ! -f /usr/lib/os-release || $out == *"staged over" ]] || fail "the build's sandbox has the system's file over the download's: $out"
    out=$("$t/auto-update-aur" --sandbox fetch "$sb" -- sh -c "$probe" 2>&1) || fail "the real fetch sandbox didn't run: $out"
    [[ $out == "net "* && $out != *sees* && $out != *staged* && $out != *"not "* ]] || fail "the fetch's sandbox sees too much: $out"
    # With pasta: the network its own. A port listened on on the host's loopback (IPv4 and IPv6), one on every address
    # (the host's others: a second card, docker0, a VM's vmnet, a VPN's), and an abstract socket (Capri's bridge, CUPS,
    # an editor's): out of reach from it, and the gateway's address not the host's (--no-map-gw); the internet (HTTPS)
    # in reach, where the host has it
    if [[ -n $pasta ]]; then
        python3 -I -c '
import socket, sys, time
t = socket.socket(); t.bind(("127.0.0.1", 0)); t.listen()
w = socket.socket(); w.bind(("0.0.0.0", 0)); w.listen()
try:
    t6 = socket.socket(socket.AF_INET6); t6.bind(("::1", t.getsockname()[1])); t6.listen()
    w6 = socket.socket(socket.AF_INET6); w6.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 1)
    w6.bind(("::", w.getsockname()[1])); w6.listen()
except OSError: pass
a = socket.socket(socket.AF_UNIX); a.bind(sys.argv[1].encode().replace(b"@", b"\0", 1)); a.listen()
print(t.getsockname()[1], w.getsockname()[1], flush=True)
time.sleep(60)' "@agros-test-$$" >"$t/port" &
        listener=$!
        for _ in $(seq 50); do [[ -s $t/port ]] && break; sleep 0.1; done
        read -r port wport <"$t/port"
        # (the host's own addresses but loopback and link-local ones, and its gateways)
        addrs=$(ip -j addr show | jq -r '.[].addr_info[] | select(.scope != "host" and .scope != "link") | .local' | paste -sd' ')
        gws=$({ ip -j -4 route show default; ip -j -6 route show default 2>/dev/null || echo '[]'; } | jq -r '.[].gateway // empty' | grep -v '^fe80' | paste -sd' ')
        # shellcheck disable=SC2016  # (the sandbox's shell's)
        reach='for a in 127.0.0.1 ::1; do timeout 5 bash -c "exec 3<>/dev/tcp/$a/'"$port"'" 2>/dev/null && echo "reaches the host on $a"; done
            for a in '"$addrs"'; do timeout 5 bash -c "exec 3<>/dev/tcp/$a/'"$wport"'" 2>/dev/null && echo "reaches the host at $a"; done
            for a in '"$gws"'; do for p in '"$port $wport"'; do timeout 5 bash -c "exec 3<>/dev/tcp/$a/$p" 2>/dev/null && echo "reaches the host through the gateway $a:$p"; done; done
            python3 -I -c "import socket; s = socket.socket(socket.AF_UNIX); s.connect(b\"\\0agros-test-'"$$"'\"); print(\"reaches the abstract socket\")" 2>/dev/null
            ip route 2>/dev/null | grep -q "^prohibit " && echo "closed off"
            curl -fsS -o /dev/null -m 20 https://aur.archlinux.org && echo online; true'
        # (the probe itself sound: from outside, each reached)
        out=$(bash -c "$reach")
        [[ $out == *"reaches the host on 127.0.0.1"* && $out == *"reaches the abstract socket"* ]] || fail "test setup: the listeners not reached from the host: $out"
        for a in $addrs; do [[ $out == *"reaches the host at $a"* ]] || fail "test setup: the host not reached at $a from itself: $out"; done
        [[ $addrs == *" "* ]] || echo "(the host has one address alone, the sandbox's own: its others' closing off checked only by its routes)"
        online=false; [[ $out == *online* ]] && online=true
        for m in fetch build; do
            out=$("$t/auto-update-aur" --sandbox "$m" "$sb" -- bash -c "$reach" 2>&1) || fail "the $m sandbox with pasta didn't run: $out"
            [[ $out != *reaches* ]] || fail "the $m sandbox reaches the host's own services: $out"
            [[ $out == *"closed off"* ]] || fail "the $m sandbox's network not closed off to the host's addresses: $out"
            ! $online || [[ $out == *online* ]] || fail "the $m sandbox has no internet through pasta: $out"
        done
        kill "$listener" 2>/dev/null
    else
        skipped "no pasta here: the sandbox's network, the host's loopback and other addresses out of its reach, not checked"
    fi
    # The user's part refuses root (a user namespace's root: EUID 0)
    if unshare -r true 2>/dev/null; then
        for m in "--sandbox run $sb -- true" "--build $sb x" "--fetch $sb x" "--unpack $sb/stage"; do
            # shellcheck disable=SC2086  # (each mode's words)
            out=$(unshare -r "$t/auto-update-aur" $m 2>&1) && fail "$m ran as root"
            [[ $out == "auto-update-aur: AUR packages are never built as root" ]] || fail "$m as root: $out"
        done
    else
        skipped "no user namespace to be root in: the refusal of root not run"
    fi
else
    skipped "no unprivileged bwrap here: the real sandbox not checked"
fi
if command -v shellcheck >/dev/null; then
    out=$(shellcheck -S warning "$t/auto-update-aur") || fail "shellcheck: $out"
fi
echo "ok auto-update-aur"
