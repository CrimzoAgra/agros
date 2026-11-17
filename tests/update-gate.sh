#!/usr/bin/env bash
# update-gate (the upstream gate): the gated packages (agros-gate.conf) updated only to versions on AgrOS's approved
# list (fetched beside the [agros] repo, kept for when it can't be reached), a rebuild of the same version always;
# held, all of them together, and said otherwise; a library whose update would break one held, held with it. The list
# taken only with a good signature by AgrOS's key (agros-approved.sig): none (not published yet, a client updated before
# CI signed it), a bad one or another key's, and it's as an unreachable list: the kept one, said
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
mkdir -p "$t/bin"
export AGROS_GATE=$t/agros-gate.conf AGROS_GATE_CACHE=$t/cache/approved
echo 'IgnorePkg = hyprland hyprutils notinstalled' >"$AGROS_GATE"
printf '%s\n' '[options]' 'Architecture = auto' "Include = $AGROS_GATE" '' '[agros]' 'Server = https://agros.invalid/x86_64' >"$t/pacman.conf"
# AgrOS's key: a key of the test's own (its public key where update-gate reads AgrOS's, AGROS_GATE_KEYRING); another
export GNUPGHOME=$t/gnupg
mkdir -m700 "$GNUPGHOME"
for k in agros other; do
    gpg --batch --quiet --passphrase '' --quick-gen-key "$k <$k@agros.invalid>" ed25519 sign never >/dev/null 2>&1
done
gpg --batch --export agros@agros.invalid >"$AGROS_GATE_KEYRING" 2>/dev/null
# pacman: installed ($HAVE_<name>), the version it would update to ($NEW_<name>), the dry run (-Sup) failing on a
# library's update while hyprland is held ($BREAKS); curl: the approved list ($APPROVED; $OFFLINE: unreachable) and its
# signature, by AgrOS's key ($SIG: none, a 404; bad, of another list; other, by another key)
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
          # ($HB: an approved Hyprland's update breaking the published agros-hyprbars, built for the old series, while
          # hyprland isn't held)
          if [[ -n ${HB:-} ]] && ! pacman-conf --config "$conf" IgnorePkg | grep -qx hyprland; then
              echo "error: failed to prepare transaction (could not satisfy dependencies)"
              echo ":: installing hyprland (0.58.0-1) breaks dependency 'hyprland<0.58' required by agros-hyprbars"; exit 1
          fi
          [[ -z ${BREAKS:-} ]] && exit 0
          grep -q '^IgnorePkg = libfoo' "$conf" && exit 0
          pacman-conf --config "$conf" IgnorePkg | grep -qx hyprland || exit 0
          echo "error: failed to prepare transaction (could not satisfy dependencies)"
          echo ":: installing libfoo (2-1) breaks dependency 'libfoo.so=1-64' required by hyprland"; exit 1 ;;
esac
P
# shellcheck disable=SC2016
cat >"$t/bin/curl" <<'C'
#!/bin/bash
echo "curl $*" >>"$CALLS"
[[ -z $OFFLINE ]] || exit 7
url=${*: -1}
# ($DOWN: that server unreachable; $SIG_AT: $SIG for that server's list alone, the others' signed well)
[[ -z ${DOWN:-} || $url != "$DOWN"/* ]] || exit 7
sig=${SIG:-}
[[ -z ${SIG_AT:-} || $url == "$SIG_AT"/* ]] || sig=
while [[ $1 != -o ]]; do shift; done
if [[ $url != *.sig ]]; then printf '%s\n' "$APPROVED" >"$2"; exit 0; fi
case $sig in
    none) exit 22 ;;
    bad) printf '%s\n' "$APPROVED" "hyprland 9.9.9" | gpg --batch --yes -u agros@agros.invalid --detach-sign -o "$2" 2>/dev/null ;;
    other) printf '%s\n' "$APPROVED" | gpg --batch --yes -u other@agros.invalid --detach-sign -o "$2" 2>/dev/null ;;
    *) printf '%s\n' "$APPROVED" | gpg --batch --yes -u agros@agros.invalid --detach-sign -o "$2" 2>/dev/null ;;
esac
C
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
# The list without a good signature by AgrOS's key: not taken, said, the kept one stays (it doesn't approve 0.59.0)
for sig in none bad other; do
    out=$(HAVE_hyprland=0.57.2-1 NEW_hyprland=0.59.0-1 APPROVED=$'hyprland 0.58.0\nhyprland 0.59.0' SIG=$sig gate 2>"$t/err")
    [[ $out == "hyprland 0.57.2-1 -> 0.59.0-1" ]] && ! open && [[ $(cat "$AGROS_GATE_CACHE") != *0.59.0* ]] ||
        fail "a list with no good signature ($sig) taken: $out / $(cat "$AGROS_GATE_CACHE")"
    grep -q "no good signature by AgrOS's key (https://agros.invalid/x86_64/agros-approved.sig)" "$t/err" ||
        fail "a list with no good signature ($sig) not said: $(cat "$t/err")"
done
# ...nor with none kept (a client updated before CI signed the list): nothing new let through
rm -f "$AGROS_GATE_CACHE"
out=$(HAVE_hyprland=0.57.2-1 NEW_hyprland=0.58.0-1 APPROVED='hyprland 0.58.0' SIG=none gate 2>/dev/null)
[[ -n $out ]] && ! open && [[ ! -e $AGROS_GATE_CACHE ]] || fail "an unsigned list taken with none kept: $out"
# (its signature's file not left beside the kept list)
[[ -z $(find "$t/cache" -name '*.sig') ]] || fail "a signature's file left: $(ls "$t/cache")"
out=$(HAVE_hyprland=0.57.2-1 NEW_hyprland=0.58.0-1 APPROVED='hyprland 0.58.0' gate)
[[ -z $out ]] && open || fail "the signed list not taken after: $out"
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
# An approved Hyprland whose update breaks one not held (agros-hyprbars, built for the old series, its rebuild not
# published yet): the set waits for that rebuild (the gate's Include kept), said, not the whole update failing on it
out=$(HAVE_hyprland=0.57.2-1 NEW_hyprland=0.58.0-1 APPROVED='hyprland 0.58.0' HB=1 gate 2>"$t/err")
[[ $out == *"hyprland (waits for agros-hyprbars's rebuild: its update would break it)"* ]] && ! open &&
    ! grep -q "dry run failed" "$t/err" || fail "an approved Hyprland breaking agros-hyprbars not held: $out / $(cat "$t/err")"
# The list fetched from beside [agros]'s database; a --dbpath (the boot's own copy of the lists) passed to every pacman
: >"$CALLS"
HAVE_hyprland=0.57.2-1 NEW_hyprland=0.57.2-1 APPROVED='hyprland 0.57.2' gate --dbpath "$t/db" >/dev/null
grep -q "^curl .*https://agros.invalid/x86_64/agros-approved$" "$CALLS" && [[ -z $(grep "^pacman" "$CALLS" | grep -v -- "--dbpath $t/db") ]] ||
    fail "not the list beside [agros], or a pacman run without the --dbpath: $(cat "$CALLS")"
# --offline (the shutdown's install): the kept list only, nothing fetched (and no list file of its own to remove: not a
# .sig in the folder it runs from)
: >"$CALLS"; mkdir "$t/cwd"; : >"$t/cwd/.sig"
out=$(cd "$t/cwd" && HAVE_hyprland=0.57.2-1 NEW_hyprland=0.59.0-1 APPROVED='hyprland 0.59.0' gate --offline)
[[ -n $out ]] && ! grep -q '^curl' "$CALLS" || fail "--offline fetched the list, or let through what the kept one doesn't: $out"
[[ -e $t/cwd/.sig ]] || fail "--offline removed a .sig file from the folder it ran in"
# Older in the repo than installed (rolled back): no wait (pacman -Su keeps the newer one), the rest not held for it
out=$(HAVE_hyprland=0.58.1-1 NEW_hyprland=0.58.0-1 OFFLINE=1 gate)
[[ -z $out ]] && open || fail "a rollback in the repo held the set: $out"
# Held with a pacman.conf that lost the gate's Include (a merged .pacnew): held all the same, by the Include added
grep -v agros-gate "$t/pacman.conf" >"$t/bare.conf"
out=$(PATH=$t/bin:$PATH HAVE_hyprland=0.57.2-1 NEW_hyprland=0.60.0-1 OFFLINE=1 "$here/.local/bin/update-gate" "$t/bare.conf" "$t/out.conf")
[[ -n $out ]] && [[ $(sed -n '/^\[options\]/{n;p}' "$t/out.conf") == "Include = $AGROS_GATE" ]] ||
    fail "held, but not by the gate, with pacman.conf's Include gone: $out / $(cat "$t/out.conf")"
# [agros] with a second server (the R2 mirror): its first (GitHub Pages) unreachable, or its list without a good
# signature, and the list comes from the next, not every Hyprland update held while Pages is down
printf '%s\n' 'Server = https://mirror.invalid/repo/x86_64' >>"$t/pacman.conf"
for case in DOWN SIG_AT; do
    rm -f "$AGROS_GATE_CACHE"
    # (in the command substitution's own shell: gate is a function)
    out=$(export "$case=https://agros.invalid/x86_64" HAVE_hyprland=0.57.2-1 NEW_hyprland=0.58.0-1 APPROVED='hyprland 0.58.0'
        [[ $case == DOWN ]] || export SIG=bad
        gate 2>/dev/null)
    [[ -z $out ]] && open && grep -qx 'hyprland 0.58.0' "$AGROS_GATE_CACHE" ||
        fail "the approved list not taken from [agros]'s next server with the first's $case: $out"
done
echo "ok update-gate"
