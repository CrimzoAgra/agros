#!/usr/bin/env bash
# Sets up this rice on a fresh CachyOS (Hyprland edition, GRUB or Limine) install; also works on Arch.
# Run as your normal user (not with sudo); sudo is used only for the system parts. It asks before the steps that change
# the system (your files, desktop settings, the pacman hook and process rule are always set; replaced files are backed up).
#   ./setup.sh                    every step, in order
#   ./setup.sh --yes              answer yes to everything
#   ./setup.sh --user-only        only the steps in your home (your files, desktop settings): no packages, no sudo
#   ./setup.sh --only <step>...   only these steps (e.g. --only files desktop, or --only=files,desktop)
#   ./setup.sh --list             list the steps
#   ./setup.sh --no-capri         without Capri, the desktop companion (installed by default, also with --yes)
#   ./setup.sh --personal [dir]   at the end, your accounts back from your pen drive (found, or its folder named);
#                                 without it, each app opened for you to sign in
#   ./setup.sh --save-personal [dir]  only put this PC's accounts on your pen drive (encrypted with a passphrase)
# The steps are in setup/modules/ (NN-<step>.sh, run in that order); files it replaces are backed up first to
# ~/.dotfiles-backup/<date>/.
set -euo pipefail

repo=$(dirname "$(readlink -f "$0")")
yes=false user_only=false list=false only=() capri=true personal=false save_personal=false personal_dir=
usage() { sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; }
while (($#)); do
    case $1 in
        -y | --yes) yes=true ;;
        --no-capri) capri=false ;;
        --personal | --save-personal)
            [[ $1 == --personal ]] && personal=true || save_personal=true
            # its pen drive's folder, if named
            if [[ ${2:-} && $2 != -* ]]; then personal_dir=$2; shift; fi
            ;;
        --user-only) user_only=true ;;
        --list) list=true ;;
        --only)
            shift
            while (($#)) && [[ $1 != -* ]]; do only+=("$1"); shift; done
            # No step named: not "every step" (with --yes that would remove Noctalia too)
            ((${#only[@]})) || { echo "--only needs at least one step (see ./setup.sh --list)."; exit 1; }
            continue
            ;;
        # (--only=files, or --only=files,desktop: as --only files desktop)
        --only=*)
            IFS=, read -ra steps <<<"${1#--only=}"
            for s in "${steps[@]}"; do [[ -z $s ]] || only+=("$s"); done
            ((${#only[@]})) || { echo "--only needs at least one step (see ./setup.sh --list)."; exit 1; }
            ;;
        -h | --help) usage; exit 0 ;;
        *) echo "unknown option: $1"; echo; usage; exit 1 ;;
    esac
    shift
done
# shellcheck source=setup/lib.sh
source "$repo/setup/lib.sh"

# Each module: setup/modules/NN-<step>.sh, defining module_<step> and saying what it does ("# about:") and whether it
# touches the system or only your home ("# scope: system|user")
modules=()
for f in "$repo"/setup/modules/[0-9][0-9]-*.sh; do
    # shellcheck source=/dev/null
    source "$f"
    modules+=("$f")
done
step_name() { local n=${1##*/[0-9][0-9]-}; echo "${n%.sh}"; }
step_about() { sed -n 's/^# about: //p' "$1"; }
step_scope() { sed -n 's/^# scope: //p' "$1"; }

[[ " ${only[*]} " == *" personal "* ]] && personal=true  # --only personal: what it's for
if $save_personal; then
    [[ $EUID -ne 0 ]] || { echo "Run this as your normal user, not with sudo."; exit 1; }
    personal_save
    exit
fi
if $list; then
    for f in "${modules[@]}"; do printf '%-10s %-7s %s\n' "$(step_name "$f")" "$(step_scope "$f")" "$(step_about "$f")"; done
    exit 0
fi
for s in "${only[@]}"; do
    [[ -n $(for f in "${modules[@]}"; do [[ $(step_name "$f") == "$s" ]] && echo y; done) ]] ||
        { echo "No step called \"$s\" (see ./setup.sh --list)."; exit 1; }
done

[[ $EUID -ne 0 ]] || { echo "Run this as your normal user, not with sudo."; exit 1; }
if $user_only && ((${#only[@]})); then echo "--only and --user-only together: pick one."; exit 1; fi

say "Dotfiles from $repo"
# runs <module>: whether this run does that step
runs() {
    local s
    s=$(step_name "$1")
    if ((${#only[@]})); then [[ " ${only[*]} " == *" $s "* ]]; else ! $user_only || [[ $(step_scope "$1") == user ]]; fi
}
# A failed step stops the run (later steps may need it): say which (not "|| ...": that would turn off set -e inside it);
# sudo's refresher (sudo_keepalive) stopped with it
step='' keepalive=''
trap 'rc=$?; [[ -z ${keepalive:-} ]] || kill "$keepalive" 2>/dev/null
    ((rc)) && [[ -n $step ]] && echo "!! The $step step failed: fix it, then ./setup.sh --only $step (and the steps after it)."' EXIT
# A step that changes the system to come: your password asked for once now, and not again along the way
for f in "${modules[@]}"; do
    if runs "$f" && [[ $(step_scope "$f") == system ]]; then sudo_keepalive; break; fi
done
for f in "${modules[@]}"; do
    step=$(step_name "$f")
    runs "$f" || continue
    say "$(step_about "$f")"
    "module_${step//-/_}"
done
step=

if $user_only || ((${#only[@]})); then
    say "Done."
else
    say "Done. Reboot, then log in to \"Hyprland (uwsm-managed)\"."
    echo "This machine's own screens go in ~/.config/caelestia/user/hosts/$(uname -n).lua (see the README)."
fi
