#!/usr/bin/env bash
# ci/aur-maintainers.sh: CI's own record of who can change each AUR package [agros] carries, and what it holds. First
# seen (none published yet): taken as they are, nothing held. A package whose AUR maintainers (or co-maintainers)
# changed: held from the day first seen, 14 days, then the new ones taken and nothing held, with no one asked; a
# further change starts the wait again, a change undone ends it. One the AUR no longer has: held for good (back with
# the same maintainers: taken again; with others: a change). The AUR not answering: the record as it was, those held
# still held. The record read back only with a good signature by AgrOS's key; Pages failing (not a 404) stops it.
# And CI wired so: the agros job (no AUR code) works it out as its outputs, the repo job holds those, the release
# publishes the record from the agros job's output. curl a stand-in: the site in $t/site, the AUR's answer from $t/aur
# ("<name> <base> <maintainers>" each, as CI writes them)
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
command -v jq >/dev/null || { skipped "no jq"; echo "skip ci-aur-maintainers (no jq)"; exit 0; }
export GNUPGHOME=$t/gnupg
mkdir -m700 "$GNUPGHOME" "$t/site"
for k in agros other; do
    gpg --batch --quiet --passphrase '' --quick-gen-key "$k <$k@agros.invalid>" ed25519 sign never >/dev/null 2>&1
done
gpg --batch --quiet --armor --export agros@agros.invalid >"$t/agros.asc" 2>/dev/null
cat >"$t/curl" <<'C'
#!/bin/bash
for a; do case $a in http*) url=$a ;; esac; done
o= w=
while (($#)); do case $1 in -o) o=$2; shift ;; -w) w=1 ;; esac; shift; done
if [[ $url == *aur.archlinux.org/rpc/* ]]; then
    [[ -z ${AUR_DOWN:-} ]] || exit 22
    grep -o 'arg\[\]=[^&]*' <<<"$url" | cut -d= -f2 | while read -r n; do
        read -r _ base who < <(awk -v n="$n" '$1 == n' "$T/aur") || continue
        jq -n --arg n "$n" --arg b "$base" --arg w "$who" '{Name: $n, PackageBase: $b,
            Maintainer: ($w | split(":")[0] | if . == "-" then null else . end),
            CoMaintainers: ($w | split(":")[1] | if . == "" then [] else split(",") end)}'
    done | jq -s '{type: "multiinfo", results: .}'
    exit 0
fi
[[ $url == *"?t="[0-9]* ]] || exit 22  # (only the current copy, past Pages' CDN's)
f=$T/site/${url%%\?*}; f=$T/site/${f##*/} code=${CODE:-}
[[ -n $code ]] || { [[ -e $f ]] && code=200 || code=404; }
[[ $code == 200 ]] && cp "$f" "$o"
if [[ -n $w ]]; then printf %s "$code"; else [[ $code == 200 ]] || exit 22; fi
C
mkdir "$t/bin" && mv "$t/curl" "$t/bin/" && chmod +x "$t/bin/curl"
# The AUR as CI would see it: each name aur/packages.txt lists, and Quickshell, with its maintainers
names=$({ sed -e 's/#.*//' -e 's/[[:space:]]//g' -e 's|^.*/||' "$here/aur/packages.txt" | grep .; echo quickshell-git; } | LC_ALL=C sort -u)
for n in $names; do echo "$n $n someone:"; done >"$t/aur"
grep -q '^libcava ' "$t/aur" && grep -q '^caelestia-shell ' "$t/aur" || fail "test setup: aur/packages.txt without libcava or caelestia-shell"
aur() { sed -i "s|^$1 .*|$1 ${3:-$1} $2|" "$t/aur"; }
# run <day>: a CI run that day, its record published (signed: by AgrOS's key, or $SIGNER's) as the release and the
# sign job would
run() {
    PATH=$t/bin:$PATH T=$t AGROS_NOW=$1 AGROS_PUBKEY=$t/agros.asc "$here/ci/aur-maintainers.sh" https://agros.invalid/x86_64 \
        "$t/state" "$t/held" >"$t/log" 2>&1 || return 1
    cp "$t/state" "$t/site/agros-aur-maintainers"
    gpg --batch --quiet --yes -u "${SIGNER:-agros}@agros.invalid" --detach-sign "$t/site/agros-aur-maintainers" 2>/dev/null
}
# (none published yet: all taken as they are, the day checked said)
run 2026-11-01 || fail "a first run failed: $(cat "$t/log")"
[[ ! -s $t/held ]] || fail "a first run held something: $(cat "$t/held")"
[[ $(head -n1 "$t/state") == "# checked 2026-11-01" ]] || fail "the day the AUR was read not recorded: $(head -n1 "$t/state")"
grep -qx 'libcava someone:' "$t/state" && [[ $(grep -vc '^#' "$t/state") == $(wc -w <<<"$names") ]] ||
    fail "not each name with its maintainers: $(cat "$t/state")"
# (the same: nothing held)
run 2026-11-02 && [[ ! -s $t/held ]] || fail "nothing changed, something held: $(cat "$t/held" "$t/log")"
# A co-maintainer added: held from the day first seen, said until when; base named for the fence
aur libcava someone:intruder cava-base
run 2026-11-03 || fail "$(cat "$t/log")"
[[ $(cat "$t/held") == "libcava cava-base its AUR maintainers changed (someone to someone, co-maintained by intruder) on 2026-11-03: its last build kept until 2026-11-17, then built from theirs" ]] ||
    fail "a co-maintainer added not held, or not said so: $(cat "$t/held")"
grep -qx 'libcava someone: someone:intruder 2026-11-03' "$t/state" || fail "the change waiting not recorded: $(grep libcava "$t/state")"
# (still within the 14 days: still held, from the day first seen)
run 2026-11-16 && grep -q '^libcava cava-base .* on 2026-11-03: .* until 2026-11-17,' "$t/held" ||
    fail "held less than 14 days: $(cat "$t/held")"
# (the AUR not answering: the record as it was, the day checked too, those held still held)
cp "$t/state" "$t/before"
AUR_DOWN=1 run 2026-11-17 || fail "the AUR down failed the run: $(cat "$t/log")"
cmp -s "$t/before" "$t/state" || fail "the AUR down changed the record: $(diff "$t/before" "$t/state")"
grep -q '^libcava libcava its AUR maintainers changed' "$t/held" || fail "the AUR down: the held one not held: $(cat "$t/held")"
# (14 days on: the new maintainers taken, nothing held)
run 2026-11-17 || fail "$(cat "$t/log")"
[[ ! -s $t/held ]] && grep -qx 'libcava someone:intruder' "$t/state" ||
    fail "the new maintainers not taken after 14 days: $(cat "$t/held"; grep libcava "$t/state")"
# A further change while one waits: the wait starts again; a change undone: nothing held
aur caelestia-shell other:
run 2026-11-18 && aur caelestia-shell third:
run 2026-11-25 && grep -q '^caelestia-shell .* (someone to third) on 2026-11-25: .* until 2026-12-09,' "$t/held" ||
    fail "a further change didn't start the wait again: $(cat "$t/held")"
aur caelestia-shell someone:
run 2026-11-26 && [[ ! -s $t/held ]] && grep -qx 'caelestia-shell someone:' "$t/state" ||
    fail "a change undone still held: $(cat "$t/held")"
# Gone from the AUR: held for good, the day first seen kept; back with the same maintainers: taken; with others: held
sed -i '/^libcava /d' "$t/aur"
run 2026-11-27 && run 2026-12-30 || fail "$(cat "$t/log")"
[[ $(cat "$t/held") == "libcava libcava gone from the AUR since 2026-11-27 (deleted, or renamed): its last build kept, not built again" ]] ||
    fail "one gone from the AUR not held, or not since it went: $(cat "$t/held")"
grep -qx 'libcava someone:intruder gone 2026-11-27' "$t/state" || fail "one gone not recorded: $(grep libcava "$t/state")"
echo 'libcava libcava someone:intruder' >>"$t/aur"
run 2026-12-31 && [[ ! -s $t/held ]] || fail "back with the same maintainers, still held: $(cat "$t/held")"
sed -i '/^libcava /d' "$t/aur" && run 2027-01-01 && echo 'libcava libcava squatter:' >>"$t/aur"
run 2027-01-02 && grep -q '^libcava libcava its AUR maintainers changed (someone, co-maintained by intruder to squatter) on 2027-01-02' "$t/held" ||
    fail "its name taken by another: not held: $(cat "$t/held")"
# The record read back only as AgrOS signed it: another key's signature, none, or Pages failing stop the run
SIGNER=other run 2027-01-03
run 2027-01-04 && fail "a record signed by another key taken"
grep -q "has no good signature by AgrOS's key" "$t/log" || fail "a bad signature not said: $(cat "$t/log")"
rm "$t/site/agros-aur-maintainers.sig"
run 2027-01-05 && fail "a record without its signature taken"
CODE=503 run 2027-01-05 && fail "Pages failing read as nothing published"
grep -q "couldn't be read (HTTP 503)" "$t/log" || fail "Pages failing not said: $(cat "$t/log")"

# CI's wiring: the agros job works it out (no AUR code there) as its outputs, from this repo's site; the repo job's
# build holds what it says; the release publishes its record, and the sign job signs it
python3 - "$here/.github/workflows/ci.yml" <<'PY' || fail "CI's wiring: see above"
import sys, yaml
jobs = yaml.safe_load(open(sys.argv[1]))["jobs"]
bad = []
steps = {s.get("id"): s for s in jobs["agros"]["steps"] if s.get("id")}
run = steps.get("aur", {}).get("run", "")
if "ci/aur-maintainers.sh" not in run or "github.io" not in run:
    bad.append("the agros job doesn't work out what to hold from this repo's site (step id aur)")
outs = jobs["agros"].get("outputs", {})
if "steps.aur.outputs.state" not in str(outs.get("aur_state")) or "steps.aur.outputs.held" not in str(outs.get("aur_held")):
    bad.append(f"the agros job doesn't hand them on as its outputs: {outs}")
build = [s for s in jobs["repo"]["steps"] if "ci/build-repo.sh" in s.get("run", "")]
if not build or "needs.agros.outputs.aur_held" not in str(build[0].get("env", {}).get("AGROS_AUR_HELD")):
    bad.append("the repo job's build not told what to hold (AGROS_AUR_HELD)")
rel = [s for s in jobs["release"]["steps"] if "agros-aur-maintainers" in s.get("run", "")]
if not rel or "needs.agros.outputs.aur_state" not in str(rel[0].get("env", {})):
    bad.append("the release doesn't publish the record from the agros job's output")
for b in bad:
    print(b)
sys.exit(1 if bad else 0)
PY
grep -q '^for f in .*agros-aur-maintainers' "$here/ci/sign-repo.sh" || fail "the record not signed (ci/sign-repo.sh)"
echo "ok ci-aur-maintainers"
