#!/usr/bin/env bash
# agros-install (what the AgrOS installer runs for your user) with a stand-in setup.sh, as a throwaway user: every
# step but the deferred ones (desktop, personal) is run as that user, one failing doesn't stop the rest and is left for
# the boot, the temporary sudo rule is gone after, the first-login and boot units are put in place, and --resume runs
# only what was left (then takes the boot unit away). Needs root (it makes the user): skipped otherwise
set -uo pipefail
. "$(dirname "$0")/lib.sh"
[[ $EUID -eq 0 ]] && command -v useradd >/dev/null && command -v runuser >/dev/null ||
    { echo "ok agros-install (SKIPPED: needs root, useradd and runuser)"; exit 0; }
u=agrostest$$
useradd -m -d "$t/home" "$u" 2>/dev/null || { echo "ok agros-install (SKIPPED: couldn't make a user)"; exit 0; }
trap 'userdel "$u" 2>/dev/null; rm -rf "$t"' EXIT
chmod 755 "$t"
# The repo as the installer leaves it in the home, with a stand-in setup.sh: steps a..e, "c" failing while
# $t/home/fail-c is there; each run written down with who ran it and whether sudo needed no password
repo=$t/home/Projects/agros
mkdir -p "$repo/install"
cp "$here"/install/agros-* "$repo/install/"
cat >"$repo/setup.sh" <<'EOS'
#!/usr/bin/env bash
if [[ $1 == --list ]]; then printf '%s user x\n' keyboard packages files desktop c personal; exit; fi
s=$3
echo "$s $(id -un) yes=$1 sudo=$(sudo -n true 2>/dev/null && echo ok || echo no) home=$HOME" >>"$HOME/runs"
[[ $s == c && -e $HOME/fail-c ]] && exit 1
exit 0
EOS
chmod +x "$repo/setup.sh"
chown -R "$u:" "$t/home"
touch "$t/home/fail-c"
export AGROS_STATE=$t/state AGROS_LOG=$t/log AGROS_LIB=$t/lib AGROS_UNITS=$t/units AGROS_SUDOERS=/etc/sudoers.d/zz-agros-test$$
command -v sudo >/dev/null || { echo "ok agros-install (SKIPPED: no sudo)"; exit 0; }

"$repo/install/agros-install" "$u" >/dev/null 2>&1 || fail "the install failed for a step it leaves for the boot"
runs=$(cut -d' ' -f1 "$t/home/runs" | paste -sd' ')
[[ $runs == "keyboard packages files c" ]] || fail "steps run: $runs (not the deferred desktop and personal)"
grep -qv " $u " "$t/home/runs" && fail "a step not run as the user: $(cat "$t/home/runs")"
grep -q "keyboard $u yes=--yes sudo=ok home=$t/home" "$t/home/runs" || fail "not unattended with sudo: $(head -1 "$t/home/runs")"
[[ -e $AGROS_SUDOERS ]] && fail "the temporary sudo rule was left"
[[ $(cat "$t/state/pending") == c ]] || fail "the failed step wasn't left for the boot: $(cat "$t/state/pending" 2>&1)"
[[ -L $t/units/system/multi-user.target.wants/agros-firstboot.service ]] || fail "the boot unit isn't on with a step left"
[[ -L $t/units/user/graphical-session.target.wants/agros-session-init.service ]] || fail "the first-login unit isn't on"
[[ -x $t/lib/agros-session-init && -x $t/lib/agros-install ]] || fail "the session and boot scripts weren't installed"

# At the boot, with the network: only the step left; done, the boot unit off
rm "$t/home/fail-c" "$t/home/runs"
"$repo/install/agros-install" --resume >/dev/null 2>&1 || fail "the resume failed"
[[ $(cut -d' ' -f1 "$t/home/runs") == c ]] || fail "resume ran: $(cat "$t/home/runs")"
[[ -e $t/state/pending ]] && fail "the step stayed pending once done"
[[ -e $t/units/system/multi-user.target.wants/agros-firstboot.service ]] && fail "the boot unit stayed on with nothing left"
"$repo/install/agros-install" --resume >/dev/null 2>&1 || fail "a resume with nothing left failed"
echo "ok agros-install"
