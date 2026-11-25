#!/usr/bin/env bash
# conflict-hold: an update pacman refused for a conflict (its real output: a package conflict, a file conflict) holds
# back only the packages in conflict, with what needs them or would break them (pacman's dry run: no partial upgrade),
# said with the command a person runs to settle it; nothing held for another failure; the whole update waits when it
# still can't be worked out
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
# pacman's dry run (-Sup, the stand-in): the update is a, d, f and libl ("<name> 2-1" each), less what pacman.conf
# holds; d needs a's new version, and libl's update breaks a's old one; $STUCK: it can't be worked out at all
# shellcheck disable=SC2016  # (expanded by the stand-in)
stub pacman '[[ $1 == -Sup ]] || exit 0
ign=" $(pacman-conf --config "$3" IgnorePkg | paste -sd" ") "
[[ -z ${STUCK:-} ]] || { echo "error: failed to prepare transaction (could not satisfy dependencies)"; echo ":: unable to satisfy dependency '"'"'x'"'"' required by"; exit 1; }
if [[ $ign == *" a "* && $ign != *" d "* ]]; then
    echo "error: failed to prepare transaction (could not satisfy dependencies)"
    echo ":: unable to satisfy dependency '"'"'a>=2'"'"' required by d"; exit 1
fi
if [[ $ign == *" a "* && $ign != *" libl "* ]]; then
    echo "error: failed to prepare transaction (could not satisfy dependencies)"
    echo ":: installing libl (2-1) breaks dependency '"'"'libl.so=1-64'"'"' required by a"; exit 1
fi
for p in a d f libl; do [[ $ign == *" $p "* ]] || echo "$p 2-1"; done
for p in a d f libl; do [[ $ign != *" $p "* ]] || echo "warning: $p: ignoring package upgrade (1-1 => 2-1)" >&2; done'
export PATH=$t/bin:$PATH
conf() { printf '%s\n' '[options]' 'Architecture = auto' '' '[core]' 'Server = file:///nowhere' >"$t/pacman.conf"; : >"$t/held"; }
hold() { "$here/.local/bin/conflict-hold" "$t/out" "$t/pacman.conf" "$t/held"; }
ignored() { pacman-conf --config "$t/pacman.conf" IgnorePkg | sort | paste -sd' '; }

# Another failure (no conflict in it): nothing held, said by its exit
conf
printf '%s\n' "error: failed to commit transaction (invalid or corrupted package)" >"$t/out"
rc=0; out=$(hold) || rc=$?
[[ $rc == 1 && -z $out && -z $(ignored) ]] || fail "a failure without a conflict held something: $rc $out / $(ignored)"

# A package conflict (pacman's own words, --noconfirm answering its question no): a held, and what a partial upgrade
# would break with it (d needs its new version; libl's update breaks its old one), f installed; said with the command
# a person runs, which asks to remove b
conf
cat >"$t/out" <<'O'
:: Starting full system upgrade...
resolving dependencies...
looking for conflicting packages...
:: a-2-1 and b-1-1 are in conflict. Remove b? [y/N] error: unresolvable package conflicts detected
error: failed to prepare transaction (conflicting dependencies)

:: a-2-1 and b-1-1 are in conflict
O
out=$(hold) || fail "a package conflict not held: $out"
[[ $(ignored) == "a b d libl" ]] || fail "not what conflicts and what needs it held: $(ignored)"
[[ $out == *"a conflicts with b (needs a person: sudo pacman -Syu, which asks whether to remove b)"* &&
    $out == *"held with them (a partial upgrade otherwise): d, libl"* ]] || fail "what waits, and why, not said: $out"
[[ $(sort "$t/held" | paste -sd,) == "a 2-1,d 2-1,libl 2-1" ]] || fail "what waits not written down: $(cat "$t/held")"

# A file conflict (a file another package owns, or none does): that package held, the files and the command named
conf
cat >"$t/out" <<'O'
checking for file conflicts...
error: failed to commit transaction (conflicting files)
f: /usr/share/f/x exists in filesystem (owned by b)
f: /usr/share/f/y exists in filesystem
Errors occurred, no packages were upgraded.
O
out=$(hold) || fail "a file conflict not held: $out"
[[ $(ignored) == f && $(cat "$t/held") == "f 2-1" ]] || fail "not the package with the file held: $(ignored) / $(cat "$t/held")"
[[ $out == "f: its files are on the system already (/usr/share/f/x,/usr/share/f/y, owned by b) (needs a person: once they're known to be safe to replace, sudo pacman -Syu --overwrite '/usr/share/f/x,/usr/share/f/y')" ]] ||
    fail "the file conflict not said with its command: $out"
# (two of the update's own packages with the same file: both held)
conf
echo "/usr/bin/z exists in both 'd' and 'f'" >"$t/out"
hold >/dev/null && [[ $(ignored) == "d f" ]] || fail "two packages with the same file not both held: $(ignored)"

# Still not worked out without them: the whole update waits (exit 2), what conflicts still said
conf
printf '%s\n' ":: a-2-1 and b-1-1 are in conflict" >"$t/out"
rc=0; out=$(STUCK=1 hold) || rc=$?
[[ $rc == 2 && $out == "a conflicts with b"* && ! -s $t/held ]] || fail "an update still not worked out not said so: $rc $out"
ok_line conflict-hold
