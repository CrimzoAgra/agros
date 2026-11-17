#!/usr/bin/env bash
# CI's release (.github/workflows/ci.yml): it runs only once the tests passed or held something back (the test job
# fails on AgrOS's own break, and a release then never puts anything out), the hold applied whenever they didn't all
# pass; the versions the tests passed with approved (none on an Arch update that broke them, a gated package not
# installed a failure, the version without its pkgrel), added to those published before (no line that isn't one, no
# repeat, the last 20 of each package); and the day Arch last passed today's only when it did. The steps' scripts as the
# workflow has them, run here with pacman and curl as stand-ins
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
if len(held) != 1 or held[0].get("if", "").replace('"', "'") != "needs.test.outputs.result != 'ok'":
    bad.append("the release doesn't hold back new builds whenever the tests didn't all pass on them")
pub = jobs["publish"].get("needs", [])
if "release" not in ([pub] if isinstance(pub, str) else pub):
    bad.append("the pages published without the release")
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
mkdir -p "$t/bin"
# (pacman -Q: installed at $V, but $MISSING)
# shellcheck disable=SC2016  # (expanded by the stand-in)
printf '#!/bin/bash\n[[ $1 == -Q && $2 != "${MISSING:-}" ]] || exit 1\necho "$2 ${V:-0.58.0-2}"\n' >"$t/bin/pacman"
chmod +x "$t/bin/pacman"

# The test job's approved versions
step test "Approved upstream versions" "$t/approve"
read -ra gated < <(sed -n 's/^[[:space:]]*IgnorePkg[[:space:]]*=[[:space:]]*//p' "$here/packages/agros-system/agros-gate.conf" | paste -sd' ')
((${#gated[@]} > 1)) || fail "test setup: no gated packages in agros-gate.conf"
approve() { (cd "$here" && PATH=$t/bin:$PATH bash -eo pipefail "$t/approve" 2>&1); }
out=$(RESULT=ok approve) || fail "the approved versions not made: $out"
[[ $(cat "$t/approved") == "$(printf '%s 0.58.0\n' "${gated[@]}")" ]] ||
    fail "not every gated package approved at its version, without its pkgrel: $(paste -sd, "$t/approved")"
out=$(RESULT=hold-agros V=1:2.0-1.1 approve) && grep -qx "${gated[0]} 1:2.0" "$t/approved" ||
    fail "a hold of AgrOS's builds (today's Arch passed) approved nothing, or an epoch lost: $out / $(paste -sd, "$t/approved")"
out=$(RESULT=hold-upstream approve) && [[ -e $t/approved && ! -s $t/approved ]] ||
    fail "an Arch update that broke the tests approved: $(paste -sd, "$t/approved")"
out=$(RESULT=ok MISSING=${gated[1]} approve) && fail "a gated package not installed passed: $(paste -sd, "$t/approved")"
[[ $out == *"::error::${gated[1]} isn't installed"* ]] || fail "a gated package not installed not said: $out"

# The release's approved list: the earlier ones (as the site has them, ci/kept.sh) and this run's, merged
step release "Approved upstream versions" "$t/merge"
mkdir -p "$t/rel/ci" "$t/rel/out/x86_64" "$t/approved-now"
cp "$here/ci/kept.sh" "$t/rel/ci/"
# (the site's list: $BEFORE, or the answer $CODE)
# shellcheck disable=SC2016
printf '#!/bin/bash\necho "$*" >>%s/urls\nwhile [[ $1 != -o ]]; do shift; done\nprintf "%%s\n" "$BEFORE" >"$2"\nprintf %%s "${CODE:-200}"\n' "$t" >"$t/bin/curl"
chmod +x "$t/bin/curl"
merge() { (cd "$t/rel" && OWNER=Owner GITHUB_REPOSITORY=Owner/agros PATH=$t/bin:$PATH bash -eo pipefail "$t/merge" >/dev/null 2>&1); }
before=$(for i in $(seq 1 24); do echo "hyprland 0.$i.0"; done; echo "aquamarine 0.9.0"; echo '<html>not found</html>')
printf '%s\n' 'hyprland 0.24.0' 'hyprland 0.25.0' 'aquamarine 0.10.0' >"$t/approved-now/approved"
BEFORE=$before merge || fail "the approved list not merged"
grep -qx 'https://Owner.github.io/agros/x86_64/agros-approved' <<<"$(sed 's/.* //' "$t/urls")" ||
    fail "the earlier list not read from this repo's site: $(cat "$t/urls")"
want=$(for i in $(seq 6 25); do echo "hyprland 0.$i.0"; done)
got=$(cat "$t/rel/out/x86_64/agros-approved")
[[ $(grep '^hyprland ' <<<"$got") == "$want" ]] ||
    fail "not the last 20 Hyprlands, each once, in order: $(grep '^hyprland ' <<<"$got" | paste -sd,)"
[[ $(grep -v '^hyprland ' <<<"$got") == $'aquamarine 0.9.0\naquamarine 0.10.0' ]] ||
    fail "another package's approvals, or a line that isn't one: $(grep -v '^hyprland ' <<<"$got")"
CODE=404 BEFORE='' merge && [[ $(cat "$t/rel/out/x86_64/agros-approved") == "$(cat "$t/approved-now/approved")" ]] ||
    fail "not published yet: this run's approvals not the list"
CODE=503 BEFORE='' merge && fail "the earlier list unreadable: published without them"

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
