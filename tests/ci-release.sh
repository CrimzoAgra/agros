#!/usr/bin/env bash
# CI's release (.github/workflows/ci.yml): it runs only once the tests passed or held something back (the test job fails
# on AgrOS's own break, and a release then never puts anything out), the hold applied whenever they didn't all pass,
# then signed (the sign job) and only then published; the versions the tests passed with approved (none on an Arch
# update that broke them, a gated package not in Arch's repos a failure, the version without its pkgrel), added to those
# published before (no line that isn't one, no repeat, the last 20 of each package); and the day Arch last passed
# today's only when it did. This run's approvals only versions the test job read before anything built was there (its
# gated step, a job output): the builds run as root in that job and could make its later list say anything, so that list
# only takes versions out (one Arch moved on during the tests), never adds one; no artifact carries them. The steps'
# scripts as the workflow has them, run here with pacman and curl as stand-ins
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
wf=$here/.github/workflows/ci.yml
# The jobs: the release after the tests, never when they failed (no always(), failure() or !cancelled() in its if);
# the hold step on any result but ok; the pages only from the release
python3 - "$wf" <<'PY' || fail "the release's place in the workflow: see above"
import sys, yaml
jobs = yaml.safe_load(open(sys.argv[1]))["jobs"]
bad = []
rel = jobs["release"]
needs = rel.get("needs", [])
needs = [needs] if isinstance(needs, str) else needs
if not {"repo", "test"} <= set(needs):
    bad.append(f"the release doesn't wait for the build and the tests: needs {needs}")
cond = str(rel.get("if", ""))
if any(w in cond for w in ("always()", "failure()", "cancelled()")):
    bad.append(f"the release can run when the tests failed: if {cond}")
held = [s for s in rel["steps"] if "--hold-new" in s.get("run", "")]
on_tests = [s for s in held if s.get("if", "").replace('"', "'") == "needs.test.outputs.result != 'ok'"]
if len(on_tests) != 1:
    bad.append("the release doesn't hold back new builds whenever the tests didn't all pass on them")
# (the install test's hold besides: only the packages it names, never every new build)
for s in held:
    if s not in on_tests and (s.get("if", "").replace('"', "'") != "needs.install.outputs.hold != ''"
                              or "needs.install.outputs.hold" not in str(s.get("env", {}).get("AGROS_HOLD_ONLY", ""))):
        bad.append(f"a hold step other than the tests' and the install test's named ones: {s.get('name')}")
# (agros-hyprbars, built for Arch's Hyprland, held with it when an Arch update broke the tests, and only then)
own = str(held[0].get("env", {}).get("AGROS_HOLD_OWN", "")) if held else ""
if "result == 'hold-upstream'" not in own or "agros-hyprbars" not in own:
    bad.append(f"agros-hyprbars not held with a Hyprland the tests hold back: AGROS_HOLD_OWN {own!r}")
listed = lambda n: [n] if isinstance(n, str) else n
if "sign" not in listed(jobs["publish"].get("needs", [])) or "release" not in listed(jobs.get("sign", {}).get("needs", [])):
    bad.append("the pages published without the release, or unsigned (publish needs sign, sign needs release)")
test = jobs["test"]
outs = test.get("outputs", {})
if "steps.gated.outputs.gated" not in str(outs.get("gated")) or "steps.approved.outputs.approved" not in str(outs.get("approved")):
    bad.append(f"the test job doesn't hand on the gated and approved versions as its outputs: {outs}")
ts = test["steps"]
gi = [i for i, s in enumerate(ts) if s.get("id") == "gated"]
built = [i for i, s in enumerate(ts) if any(w in s.get("run", "") + s.get("uses", "") for w in ("[agros]", "download-artifact", "test-passes", "tests/run.sh"))]
if len(gi) != 1 or not built or gi[0] > min(built):
    bad.append("the gated versions not read before anything built is in the test job")
if any(s.get("with", {}).get("name") == "approved" for j in jobs.values() for s in j.get("steps", [])):
    bad.append("the approved versions carried by an artifact (one the test job's builds could replace)")
env = next((s.get("env", {}) for s in rel["steps"] if s.get("name") == "Approved upstream versions"), {})
if "needs.test.outputs.gated" not in str(env.get("GATED")) or "needs.test.outputs.approved" not in str(env.get("APPROVED")):
    bad.append("the release's approvals not from the test job's outputs (GATED, APPROVED)")
for b in bad:
    print(b)
sys.exit(1 if bad else 0)
PY
# step <job> <step name> <file>: that step's script, its /tmp paths in $t
step() {
    python3 - "$wf" "$1" "$2" >"$3" <<'PY' || true
import sys, yaml
steps = yaml.safe_load(open(sys.argv[1]))["jobs"][sys.argv[2]]["steps"]
print(next((s["run"] for s in steps if s.get("name") == sys.argv[3]), ""), end="")
PY
    sed -i "s|/tmp/|$t/|g" "$3"
    [[ -s $3 ]] || fail "no step \"$2\" in the $1 job"
}
# (pacman -Q: installed at $V, but $MISSING; -S: installed, but $MISSING not in the repos)
# shellcheck disable=SC2016  # (expanded by the stand-in)
stub pacman 'case $1 in
-S) echo "$*" >>'"$t"'/installed; [[ " $* " != *" ${MISSING:-none} "* ]] ;;
-Q) [[ $2 != "${MISSING:-}" ]] || exit 1; echo "$2 ${V:-0.58.0-2}" ;;
*) exit 1 ;;
esac'
read -ra gated < <(sed -n 's/^[[:space:]]*IgnorePkg[[:space:]]*=[[:space:]]*//p' "$here/packages/agros-system/agros-gate.conf" | paste -sd' ')
((${#gated[@]} > 1)) || fail "test setup: no gated packages in agros-gate.conf"

# The test job's gated versions, before anything built: each gated package installed from Arch's repos, read, a job
# output ("gated<<EOF" lines)
step test "Gated versions (before anything built is here)" "$t/gated"
gate() { : >"$t/gh" && (cd "$here" && GITHUB_OUTPUT=$t/gh PATH=$t/bin:$PATH bash -eo pipefail "$t/gated" 2>&1); }
out=$(gate) || fail "the gated versions not read: $out"
[[ $(cat "$t/gh") == "$(echo 'gated<<EOF'; printf '%s 0.58.0\n' "${gated[@]}"; echo EOF)" ]] ||
    fail "not every gated package at its version, without its pkgrel, as the job's output: $(paste -sd, "$t/gh")"
[[ $(tail -n1 "$t/installed") == *" ${gated[*]}" ]] || fail "the gated packages not installed first: $(tail -n1 "$t/installed")"
out=$(MISSING=${gated[1]} gate) && fail "a gated package Arch doesn't have passed: $(paste -sd, "$t/gh")"

# The test job's approved versions, after the tests
step test "Approved upstream versions" "$t/approve"
approve() { : >"$t/gh-approved" && (cd "$here" && GITHUB_OUTPUT=$t/gh-approved PATH=$t/bin:$PATH bash -eo pipefail "$t/approve" 2>&1); }
out=$(RESULT=ok approve) || fail "the approved versions not made: $out"
[[ $(cat "$t/approved") == "$(printf '%s 0.58.0\n' "${gated[@]}")" ]] ||
    fail "not every gated package approved at its version, without its pkgrel: $(paste -sd, "$t/approved")"
[[ $(cat "$t/gh-approved") == "$(echo 'approved<<EOF'; cat "$t/approved"; echo EOF)" ]] ||
    fail "the approved versions not the job's output, which the release reads: $(paste -sd, "$t/gh-approved")"
out=$(RESULT=hold-agros V=1:2.0-1.1 approve) && grep -qx "${gated[0]} 1:2.0" "$t/approved" ||
    fail "a hold of AgrOS's builds (today's Arch passed) approved nothing, or an epoch lost: $out / $(paste -sd, "$t/approved")"
out=$(RESULT=hold-upstream approve) && [[ -e $t/approved && ! -s $t/approved ]] ||
    fail "an Arch update that broke the tests approved: $(paste -sd, "$t/approved")"
out=$(RESULT=ok MISSING=${gated[1]} approve) && fail "a gated package not installed passed: $(paste -sd, "$t/approved")"
[[ $out == *"::error::${gated[1]} isn't installed"* ]] || fail "a gated package not installed not said: $out"

# The release's approved list: the earlier ones (as the site has them, ci/kept.sh) and this run's, merged
step release "Approved upstream versions" "$t/merge"
mkdir -p "$t/rel/ci" "$t/rel/out/x86_64"
cp "$here/ci/kept.sh" "$t/rel/ci/"
# (the site's list: $BEFORE, or the answer $CODE)
# shellcheck disable=SC2016
printf '#!/bin/bash\necho "$*" >>%s/urls\nwhile [[ $1 != -o ]]; do shift; done\nprintf "%%s\n" "$BEFORE" >"$2"\nprintf %%s "${CODE:-200}"\n' "$t" >"$t/bin/curl"
chmod +x "$t/bin/curl"
# (this run's: $GATED, the test job's gated step's, and $APPROVED, its approved step's; both these unless given)
now=$(printf '%s\n' 'hyprland 0.24.0' 'hyprland 0.25.0' 'aquamarine 0.10.0')
merge() {
    (cd "$t/rel" && OWNER=Owner GITHUB_REPOSITORY=Owner/agros RESULT=${RESULT-ok} GATED=${GATED-$now} APPROVED=${APPROVED-$now} \
        PATH=$t/bin:$PATH bash -eo pipefail "$t/merge" >/dev/null 2>&1)
}
before=$(for i in $(seq 1 24); do echo "hyprland 0.$i.0"; done; echo "aquamarine 0.9.0"; echo '<html>not found</html>')
BEFORE=$before merge || fail "the approved list not merged"
grep -Eqx 'https://Owner\.github\.io/agros/x86_64/agros-approved\?t=[0-9]+' <<<"$(sed 's/.* //' "$t/urls")" ||
    fail "the earlier list not read from this repo's site, its current copy (?t=): $(cat "$t/urls")"
want=$(for i in $(seq 6 25); do echo "hyprland 0.$i.0"; done)
got=$(cat "$t/rel/out/x86_64/agros-approved")
[[ $(grep '^hyprland ' <<<"$got") == "$want" ]] ||
    fail "not the last 20 Hyprlands, each once, in order: $(grep '^hyprland ' <<<"$got" | paste -sd,)"
[[ $(grep -v '^hyprland ' <<<"$got") == $'aquamarine 0.9.0\naquamarine 0.10.0' ]] ||
    fail "another package's approvals, or a line that isn't one: $(grep -v '^hyprland ' <<<"$got")"
CODE=404 BEFORE='' merge && [[ $(cat "$t/rel/out/x86_64/agros-approved") == "$now" ]] ||
    fail "not published yet: this run's approvals not the list"
CODE=503 BEFORE='' merge && fail "the earlier list unreadable: published without them"
# This run's only those read before anything built (GATED) that the tests passed with (APPROVED): one the build made up
# (in APPROVED alone), one Arch moved on from during the tests (another version in each), none on a result but ok or
# hold-agros
approved() { CODE=404 BEFORE='' merge && cat "$t/rel/out/x86_64/agros-approved"; }
[[ $(APPROVED=$now$'\nhyprland 9.9.9\nsudo 1.0' approved) == "$now" ]] || fail "a version the test job's builds could have made up approved"
[[ $(GATED=$'hyprland 0.24.0\naquamarine 0.10.0' APPROVED=$'hyprland 0.25.0\naquamarine 0.10.0' approved) == 'aquamarine 0.10.0' ]] ||
    fail "a version read before the tests, not the one they passed with, approved"
[[ $(RESULT=hold-agros approved) == "$now" ]] || fail "a hold of AgrOS's builds (today's Arch passed) approved nothing"
for r in hold-upstream fail ''; do
    [[ -z $(RESULT=$r approved) ]] || fail "the tests' result ${r:-none}: approved all the same"
done

# The day Arch last passed: today's when it did (all passed, or only this run's AUR builds broke them), else the site's
step release "The day Arch last passed" "$t/day"
day() { (cd "$t/rel" && PATH=$t/bin:$PATH sh -e "$t/day" >/dev/null 2>&1) && cat "$t/rel/out/x86_64/agros-arch-ok"; }
today=$(date -u +%Y/%m/%d)
for r in ok hold-agros; do
    [[ $(RESULT=$r BEFORE=2026/01/01 day) == "$today" ]] || fail "$r: not today's day"
done
for r in hold-upstream fail; do
    [[ $(RESULT=$r BEFORE=2026/01/01 day) == 2026/01/01 ]] || fail "$r: the day Arch last passed moved on"
done
echo "ok ci-release"
