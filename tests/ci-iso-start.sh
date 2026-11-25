#!/usr/bin/env bash
# CI's iso job (.github/workflows/ci.yml): agros-iso's ISO build started once Pages serves the database with this
# commit's packages (agros-system r<commits>.<its commit>), not before; starting it tried three times (GitHub's API
# drops a call now and then), failing the job only when all three fail; a database that never lists this commit fails
# it, said; not started while an Arch update breaks the tests (hold-upstream). Its run: script as GitHub runs it
# (bash -e), curl, gh and sleep stand-ins
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
command -v bsdtar >/dev/null || command -v tar >/dev/null || { skipped "no tar"; echo "skip ci-iso-start (no tar)"; exit 0; }
python3 - "$here/.github/workflows/ci.yml" >"$t/step" <<'PY'
import sys, yaml
job = yaml.safe_load(open(sys.argv[1]))["jobs"]["iso"]
# (not while an Arch update breaks the tests: the ISO would take that Arch, its gate holding back only Hyprland)
assert "test" in job["needs"] and "needs.test.outputs.result != 'hold-upstream'" in job.get("if", ""), \
    "the ISO started while an Arch update breaks the tests"
steps = [s for s in job["steps"] if "gh workflow run" in s.get("run", "")]
assert len(steps) == 1, "not one step that starts the ISO build"
print(steps[0]["run"])
PY
sha=0123456789abcdef0123456789abcdef01234567
# db <agros-system version>: the database Pages serves
db() { local s; s=$(mktemp -d); mkdir "$s/agros-system-$1" && echo x >"$s/agros-system-$1/desc"; tar -czf "$t/agros.db" -C "$s" "agros-system-$1"; rm -rf "$s"; }
stub curl "cat '$t/agros.db'"
stub sleep "echo sleep >>'$t/calls'"
# (gh: fails while $t/ghfails has lines left, one taken a call)
stub gh "echo \"gh \$*\" >>'$t/calls'; [[ -s '$t/ghfails' ]] || exit 0; sed -i 1d '$t/ghfails'; exit 1"
run() { rm -f "$t/calls"; PATH=$t/bin:$PATH GH_TOKEN=x GITHUB_SHA=$sha bash -e "$t/step" 2>&1; }
starts() { grep -c '^gh workflow run iso.yml -R CrimzoAgra/agros-iso --ref main$' "$t/calls" || true; }
db "r10.${sha::7}-1"
: >"$t/ghfails"
o=$(run) || fail "the ISO build not started: $o"
[[ $(starts) == 1 ]] || fail "not started once: $(cat "$t/calls")"
printf '1\n2\n' >"$t/ghfails"
o=$(run) || fail "starting the ISO build failing twice, then not, failed the job: $o"
[[ $(starts) == 3 ]] || fail "starting the ISO build not tried again: $(cat "$t/calls")"
printf '1\n2\n3\n4\n' >"$t/ghfails"
o=$(run) && fail "starting the ISO build failing every time passed: $o"
[[ $(starts) == 3 ]] || fail "starting the ISO build not tried three times: $(cat "$t/calls")"
# (an older commit's database, the CDN's: waited for, then the job failed, said, nothing started)
: >"$t/ghfails"
db "r9.fedcba9-1"
o=$(run) && fail "started with the database not listing this commit: $o"
[[ $(starts) == 0 && $o == *"still doesn't list this commit's packages"* ]] || fail "an old database not said, or the build started: $o"
echo "ok ci-iso-start"
