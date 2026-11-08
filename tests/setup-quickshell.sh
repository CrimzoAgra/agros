#!/usr/bin/env bash
# setup's install_quickshell over CachyOS's noctalia-qs: Quickshell built first, noctalia-qs still installed meanwhile
# (an interruption there leaves the shell you had), then swapped in by pacman; the build failing: noctalia-qs left as
# it was; -U and -Rdd both refused: not taken for done. pacman (answering -Q for a name noctalia-qs only provides
# with noctalia-qs, as the real one does), makepkg, git and sudo stand-ins; what's installed in a file
set -euo pipefail
. "$(dirname "$0")/lib.sh"
mkdir -p "$t/bin"
# shellcheck source=/dev/null
source <(sed -n '/^installed() {/p' "$here/setup/lib.sh")
[[ $(type -t installed) == function ]] || fail "setup/lib.sh's installed not found"
aur_helper() { echo "$t/bin/paru"; }
# shellcheck source=/dev/null
source <(sed -n '/^install_quickshell() {$/,/^}$/p' "$here/setup/modules/20-packages.sh")
# shellcheck disable=SC2016  # (expanded by the stand-ins)
printf '#!/bin/sh\nexec "$@"\n' >"$t/bin/sudo"
# shellcheck disable=SC2016
printf '#!/bin/sh\nmkdir -p "$4"\n' >"$t/bin/git"
# makepkg: the build ($BUILD_FAILS: fails), noted with what's installed then; --packagelist its file
cat >"$t/bin/makepkg" <<EOF
#!/bin/sh
[ "\$1" = --packagelist ] && { echo "\$PWD/quickshell-git-1-x86_64.pkg.tar.zst"; echo "\$PWD/quickshell-git-debug-1-x86_64.pkg.tar.zst"; exit 0; }
echo "build (installed: \$(paste -sd' ' "$t/installed"))" >>"$t/calls"
[ -z "\$BUILD_FAILS" ] || exit 1
touch quickshell-git-1-x86_64.pkg.tar.zst
EOF
# pacman -Q, -Qq: the package, else an installed one providing the name (noctalia-qs: quickshell, quickshell-git);
# -U: the build in, the package it conflicts with out (with --ask=4; $U_FAILS: refused); -Rdd ($RDD_FAILS: refused),
# -S: out, in
cat >"$t/bin/pacman" <<EOF
#!/bin/sh
case \$1 in
    -Q|-Qq) if grep -qx "\$2" "$t/installed"; then p=\$2
        elif grep -qx noctalia-qs "$t/installed" && { [ "\$2" = quickshell ] || [ "\$2" = quickshell-git ]; }; then p=noctalia-qs
        else echo "error: package '\$2' was not found" >&2; exit 1; fi
        if [ "\$1" = -Qq ]; then echo "\$p"; else echo "\$p 1-1"; fi
        exit 0 ;;
esac
echo "pacman \$*" >>"$t/calls"
case \$1 in
    -U) [ -z "\$U_FAILS" ] || exit 1
        case " \$* " in *" --ask=4 "*) sed -i '/^noctalia-qs\$/d' "$t/installed" ;; esac
        grep -qx noctalia-qs "$t/installed" && exit 1; echo quickshell-git >>"$t/installed" ;;
    -Rdd) [ -z "\$RDD_FAILS" ] || exit 1; sed -i '/^noctalia-qs\$/d' "$t/installed" ;;
    -S) echo noctalia-qs >>"$t/installed" ;;
esac
EOF
chmod +x "$t/bin/"*
export PATH=$t/bin:$PATH

echo noctalia-qs >"$t/installed"; : >"$t/calls"
install_quickshell >/dev/null || fail "Quickshell over noctalia-qs failed: $(cat "$t/calls")"
{ grep -q "^build (installed: noctalia-qs)" "$t/calls" && [[ $(cat "$t/installed") == quickshell-git ]] &&
    grep -q "^pacman -U --noconfirm --ask=4 .*/quickshell-git-1-x86_64.pkg.tar.zst$" "$t/calls" &&
    ! grep -q -- "-Rdd" "$t/calls"; } ||
    fail "Quickshell not built with noctalia-qs still there, then swapped in one step: $(cat "$t/calls") / $(cat "$t/installed")"

echo noctalia-qs >"$t/installed"; : >"$t/calls"
if out=$(BUILD_FAILS=1 install_quickshell); then fail "a failed build reported success"; fi
{ [[ $(cat "$t/installed") == noctalia-qs && $out == *"the shell you had is back"* ]] && ! grep -q "^pacman -[RU]" "$t/calls"; } ||
    fail "a failed build touched noctalia-qs: $(cat "$t/calls") / $(cat "$t/installed") / $out"
# Both the swap and taking noctalia-qs out refused: a failure, said, noctalia-qs still there (not "done")
echo noctalia-qs >"$t/installed"; : >"$t/calls"
if out=$(U_FAILS=1 RDD_FAILS=1 install_quickshell); then fail "a refused swap reported success: $(cat "$t/calls")"; fi
[[ $(cat "$t/installed") == noctalia-qs && $out == *"the shell you had is back"* ]] ||
    fail "a refused swap not said, or noctalia-qs gone: $out / $(cat "$t/installed")"
# No noctalia-qs (Arch, or its own quickshell package): from the AUR, a conflicting package taken out (--ask=4); that
# failing, no noctalia-qs put in (not the shell you had), said
cat >"$t/bin/paru" <<EOF
#!/bin/sh
echo "paru \$*" >>"$t/calls"
[ -z "\$AUR_FAILS" ] || exit 1
EOF
chmod +x "$t/bin/paru"
echo quickshell >"$t/installed"; : >"$t/calls"
install_quickshell >/dev/null || fail "Quickshell from the AUR failed: $(cat "$t/calls")"
grep -qx "paru -S --noconfirm --ask=4 aur/quickshell-git" "$t/calls" || fail "the AUR install doesn't take a conflicting package out: $(cat "$t/calls")"
: >"$t/calls"
if out=$(AUR_FAILS=1 install_quickshell); then fail "a failed AUR install reported success"; fi
{ ! grep -q "^pacman -S" "$t/calls" && [[ $out == *"didn't build"* && $out != *"the shell you had is back"* ]]; } ||
    fail "a failed AUR install put noctalia-qs in, or said it was back: $(cat "$t/calls") / $out"
echo "ok setup-quickshell"
