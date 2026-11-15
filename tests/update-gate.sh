#!/usr/bin/env bash
# update-gate (the upstream gate): the gated packages (agros-gate.conf) updated only to versions on AgrOS's approved
# list (fetched beside the [agros] repo, kept for when it can't be reached), a rebuild of the same version always;
# held, all of them together, and said otherwise; a library whose update would break one held, held with it
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
mkdir -p "$t/bin"
export AGROS_GATE=$t/agros-gate.conf AGROS_GATE_CACHE=$t/cache/approved
echo 'IgnorePkg = hyprland hyprutils notinstalled' >"$AGROS_GATE"
printf '%s\n' '[options]' 'Architecture = auto' "Include = $AGROS_GATE" '' '[agros]' 'Server = https://agros.invalid/x86_64' >"$t/pacman.conf"
# pacman: installed ($HAVE_<name>), the version it would update to ($NEW_<name>), the dry run (-Sup) failing on a
# library's update while hyprland is held ($BREAKS); curl: the approved list ($APPROVED; $OFFLINE: unreachable)
# shellcheck disable=SC2016  # (expanded by the stand-ins)
cat >"$t/bin/pacman" <<'P'
#!/bin/bash
args=" $* "
name=${*: -1}
echo "pacman $*" >>"$CALLS"
var() { local v="$1_${name//-/_}"; echo "${!v:-}"; }
case $1 in
    -Q) [[ -n $(var HAVE) ]] && echo "$name $(var HAVE)" ;;
    -Si) [[ -n $(var NEW) ]] && echo "Version         : $(var NEW)" ;;
    -Sup) conf=$(sed -n 's/.*--config \([^ ]*\) .*/\1/p' <<<"$args")
          # ($NEEDS: hyprlock rebuilt against the held hyprutils's new version, until it's held too)
          if [[ -n ${NEEDS:-} ]] && ! grep -q 'IgnorePkg = .*hyprlock' "$conf"; then
              echo "error: failed to prepare transaction (could not satisfy dependencies)"
              echo ":: unable to satisfy dependency 'libhyprutils.so=14-64' required by hyprlock"; exit 1
          fi
          [[ -z ${BREAKS:-} ]] && exit 0
          grep -q '^IgnorePkg = libfoo' "$conf" && exit 0
          pacman-conf --config "$conf" IgnorePkg | grep -qx hyprland || exit 0
          echo "error: failed to prepare transaction (could not satisfy dependencies)"
          echo ":: installing libfoo (2-1) breaks dependency 'libfoo.so=1-64' required by hyprland"; exit 1 ;;
esac
P
# shellcheck disable=SC2016
printf '#!/bin/sh\necho "curl $*" >>"$CALLS"\n[ -z "$OFFLINE" ] || exit 7\nwhile [ "$1" != -o ]; do shift; done\nprintf "%%s\\n" "$APPROVED" >"$2"\n' >"$t/bin/curl"
chmod +x "$t/bin/"*
export CALLS=$t/calls
gate() { PATH=$t/bin:$PATH "$here/.local/bin/update-gate" "$t/pacman.conf" "$t/out.conf" "$@"; }
open() { ! grep -q agros-gate "$t/out.conf"; }

# A rebuild of the same version (a library's new soname): let through, approved or not
out=$(HAVE_hyprland=0.57.2-1 NEW_hyprland=0.57.2-2 APPROVED='' gate)
[[ -z $out ]] && open || fail "a rebuild of the same version held: $out"
# A new version not checked yet: held, said; the rest of pacman.conf as it was
out=$(HAVE_hyprland=0.57.2-1 NEW_hyprland=0.58.0-1 APPROVED='hyprland 0.57.2' gate)
[[ $out == "hyprland 0.57.2-1 -> 0.58.0-1" ]] && ! open && cmp -s "$t/pacman.conf" "$t/out.conf" || fail "an unchecked Hyprland not held: $out"
# Approved (the list from [agros]'s server, the version without its pkgrel): let through, the gate's Include alone gone
out=$(HAVE_hyprland=0.57.2-1 NEW_hyprland=0.58.0-1.1 APPROVED=$'hyprland 0.57.2\nhyprland 0.58.0' gate)
[[ -z $out ]] && open && grep -qx 'Server = https://agros.invalid/x86_64' "$t/out.conf" || fail "an approved Hyprland held: $out"
# One of the set not approved: all of them held (built against each other)
out=$(HAVE_hyprland=0.57.2-1 NEW_hyprland=0.58.0-1 HAVE_hyprutils=0.10-1 NEW_hyprutils=0.11-1 APPROVED='hyprland 0.58.0' gate)
[[ $out == "hyprutils 0.10-1 -> 0.11-1" ]] && ! open || fail "the set not held together: $out"
# The repo out of reach: the list kept from the last fetch (that approval still counts)
out=$(HAVE_hyprland=0.57.2-1 NEW_hyprland=0.58.0-1 OFFLINE=1 gate)
[[ -z $out ]] && open || fail "the kept list not used offline: $out"
# A list that isn't one (an error page): not taken, the kept one stays
out=$(HAVE_hyprland=0.57.2-1 NEW_hyprland=0.58.0-1 APPROVED='<html>404</html>' gate)
[[ -z $out ]] && open && grep -qx 'hyprland 0.58.0' "$AGROS_GATE_CACHE" || fail "an error page taken as the approved list: $out"
# Never fetched: nothing new let through
rm -f "$AGROS_GATE_CACHE"
out=$(HAVE_hyprland=0.57.2-1 NEW_hyprland=0.58.0-1 OFFLINE=1 gate)
[[ -n $out ]] && ! open || fail "a new Hyprland let through with no approved list: $out"
# Held, a library's update breaking it: that library held too, in the same pacman.conf
out=$(HAVE_hyprland=0.57.2-1 NEW_hyprland=0.58.0-1 OFFLINE=1 BREAKS=1 gate)
[[ $out == *"libfoo (held with hyprland: its update would break it)"* ]] &&
    [[ $(PATH=$t/bin:$PATH pacman-conf --config "$t/out.conf" IgnorePkg | sort | paste -sd' ') == "hyprland hyprutils libfoo notinstalled" ]] ||
    fail "a library breaking the held Hyprland not held with it: $out / $(cat "$t/out.conf")"
# ...and one outside the set rebuilt against a held library's new version (hyprlock): held too, not the
# whole update failing on it
out=$(HAVE_hyprland=0.57.2-1 NEW_hyprland=0.58.0-1 OFFLINE=1 NEEDS=1 gate)
[[ $out == *"hyprlock (held: its update needs something not to be had yet)"* ]] &&
    grep -qx 'IgnorePkg = hyprlock' "$t/out.conf" || fail "a package needing a held one's new version not held: $out / $(cat "$t/out.conf")"
# The list fetched from beside [agros]'s database; a --dbpath (the boot's own copy of the lists) passed to every pacman
: >"$CALLS"
HAVE_hyprland=0.57.2-1 NEW_hyprland=0.57.2-1 APPROVED='hyprland 0.57.2' gate --dbpath "$t/db" >/dev/null
grep -q "^curl .*https://agros.invalid/x86_64/agros-approved$" "$CALLS" && [[ -z $(grep "^pacman" "$CALLS" | grep -v -- "--dbpath $t/db") ]] ||
    fail "not the list beside [agros], or a pacman run without the --dbpath: $(cat "$CALLS")"
# --offline (the shutdown's install): the kept list only, nothing fetched
: >"$CALLS"
out=$(HAVE_hyprland=0.57.2-1 NEW_hyprland=0.59.0-1 APPROVED='hyprland 0.59.0' gate --offline)
[[ -n $out ]] && ! grep -q '^curl' "$CALLS" || fail "--offline fetched the list, or let through what the kept one doesn't: $out"
# Older in the repo than installed (rolled back): no wait (pacman -Su keeps the newer one), the rest not held for it
out=$(HAVE_hyprland=0.58.1-1 NEW_hyprland=0.58.0-1 OFFLINE=1 gate)
[[ -z $out ]] && open || fail "a rollback in the repo held the set: $out"
# Held with a pacman.conf that lost the gate's Include (a merged .pacnew): held all the same, by the Include added
grep -v agros-gate "$t/pacman.conf" >"$t/bare.conf"
out=$(PATH=$t/bin:$PATH HAVE_hyprland=0.57.2-1 NEW_hyprland=0.60.0-1 OFFLINE=1 "$here/.local/bin/update-gate" "$t/bare.conf" "$t/out.conf")
[[ -n $out ]] && [[ $(sed -n '/^\[options\]/{n;p}' "$t/out.conf") == "Include = $AGROS_GATE" ]] ||
    fail "held, but not by the gate, with pacman.conf's Include gone: $out / $(cat "$t/out.conf")"
echo "ok update-gate"
