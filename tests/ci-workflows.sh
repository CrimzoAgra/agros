#!/usr/bin/env bash
# Every workflow in .github/workflows: a permissions block of its own (the token read-only unless a job says otherwise),
# never pull_request_target (a fork's code run with the secrets and a token that writes), no ${{ }} in a run: script
# (a branch name or an issue's title pasted into bash: passed through env: instead, as each one does), each job a
# time limit (a hang stopped, not run on to GitHub's 6 hours), and each curl there tried again (--retry), as is
# each sync through CachyOS's mirror list, of the published [agros] from Pages, and each git fetch from GitHub. And
# ci.yml's per-package gating (below)
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
python3 - "$here"/.github/workflows/*.yml <<'PY' || fail "the workflows: see above"
import re, sys, yaml
bad = []
for path in sys.argv[1:]:
    name = path.rsplit("/", 1)[-1]
    w = yaml.safe_load(open(path))
    on = w.get(True, w.get("on"))  # (YAML reads a bare on: as true)
    events = on if isinstance(on, (list, str)) else list(on or {})
    if "pull_request_target" in events:
        bad.append(f"{name}: pull_request_target")
    if "permissions" not in w:
        bad.append(f"{name}: no permissions block (the token's default may write)")
    for jn, job in w["jobs"].items():
        if "timeout-minutes" not in job:
            bad.append(f"{name}: job {jn} has no timeout-minutes")
        for s in job.get("steps", []):
            if "${{" in s.get("run", ""):
                bad.append(f"{name}: job {jn}, step {s.get('name')}: ${{{{ }}}} in its run: (pass it through env:)")
            # (each download tried again: a server's hiccup failed the run, and opened the held issue for nothing)
            for line in s.get("run", "").splitlines():
                if not line.lstrip().startswith("#") and line.count("curl ") > line.count("--retry "):
                    bad.append(f"{name}: job {jn}, step {s.get('name')}: a curl without --retry: {line.strip()}")
            # (and each sync through CachyOS's mirror list: a mirror mid-sync fails it, see ci.yml)
            run = s.get("run", "").splitlines()
            for i, line in enumerate(run):
                retried = any("pacman -Syy" in l and "&& break" in l for l in run[i:i + 6])
                if "cachyos-mirrorlist|" in line and not retried:
                    bad.append(f"{name}: job {jn}, step {s.get('name')}: CachyOS's mirror list synced, not tried again")
        # (and each later sync in a job with CachyOS's mirror list, each sync of the published [agros] from Pages (a 503
        # for minutes now and then) and each git fetch or clone from GitHub: tried again too, in a loop, "&& break")
        cachy = False
        for s in job.get("steps", []):
            run = s.get("run", "")
            for line in run.splitlines():
                if line.lstrip().startswith("#"):
                    continue
                sync = re.search(r"pacman -S[a-z]*y", line) and (cachy or "github.io/agros" in run)
                fetch = re.search(r"git( -C \S+)? (fetch|clone)\b.*https://", line)
                if (sync or fetch) and "&& break" not in line:
                    bad.append(f"{name}: job {jn}, step {s.get('name')}: a download not tried again: {line.strip()}")
                if "cachyos-mirrorlist|" in line:
                    cachy = True
for b in bad:
    print(b)
sys.exit(1 if bad else 0)
PY
# CI's per-package gating (ci.yml): the test job hands on the new build that broke the tests (ci/test-passes.sh's hold=),
# held alone by the release (AGROS_HOLD_ONLY); the install job makes the release as the release job does (that hold,
# the database), with CachyOS's repo above Arch's, installs it for real (ci/install-test.sh), and the release holds
# what that fails with, after the tests' hold, before the database; the report says what couldn't be held
python3 - "$here"/.github/workflows/ci.yml <<'PY' || fail "ci.yml's gating: see above"
import json, sys, yaml
jobs = yaml.safe_load(open(sys.argv[1]))["jobs"]
bad = []
needs = lambda j: [jobs[j].get("needs")] if isinstance(jobs[j].get("needs"), str) else jobs[j].get("needs", [])
idx = lambda steps, w: [i for i, s in enumerate(steps) if w in s.get("run", "")]
if jobs["test"].get("outputs", {}).get("hold") != "${{ steps.tests.outputs.hold }}":
    bad.append("the test job doesn't hand on which new build broke the tests (hold)")
ins = jobs.get("install")
rs = jobs["release"]["steps"]
if not ins:
    bad.append("no install job")
else:
    st = ins["steps"]
    if "test" not in needs("install"):
        bad.append("the install job doesn't wait for the tests")
    hold, db, it = idx(st, "build-repo.sh out/x86_64 --hold-new"), idx(st, "ci/repo-db.sh out/x86_64"), idx(st, "ci/install-test.sh out/x86_64")
    cachy = idx(st, "cachyos-mirrorlist")
    if len(hold) != 1 or len(db) != 1 or len(it) != 1 or not hold[0] < db[0] < it[0]:
        bad.append("the install job doesn't install the release as the release job makes it (the hold, the database, then ci/install-test.sh)")
    else:
        same = [s for s in rs if s.get("name") == st[hold[0]].get("name")]
        if st[hold[0]].get("env", {}).get("AGROS_HOLD_ONLY") != "${{ needs.test.outputs.hold }}" or \
                not same or st[hold[0]].get("env") != same[0].get("env"):
            bad.append("the install job's hold not the release job's")
        if not cachy or cachy[0] > it[0]:
            bad.append("the install job doesn't set CachyOS's repo up above Arch's before the install")
        if st[it[0]].get("id") != "install" or \
                ins.get("outputs", {}) != {"hold": "${{ steps.install.outputs.hold }}", "note": "${{ steps.install.outputs.note }}"}:
            bad.append("the install job doesn't hand on what to hold and what to say (hold, note)")
    if "secrets." in json.dumps(ins):
        bad.append("a secret in the install job (it runs the packages' install scripts as root)")
if "install" not in needs("release"):
    bad.append("the release doesn't wait for the install test")
held = [i for i, s in enumerate(rs) if s.get("env", {}).get("AGROS_HOLD_ONLY") == "${{ needs.install.outputs.hold }}"]
th = [i for i, s in enumerate(rs) if s.get("env", {}).get("AGROS_HOLD_ONLY") == "${{ needs.test.outputs.hold }}"]
db = idx(rs, "ci/repo-db.sh")
if len(held) != 1 or "build-repo.sh out/x86_64 --hold-new" not in rs[held[0]].get("run", "") or \
        rs[held[0]].get("env", {}).get("AGROS_HELD") != "/tmp/held/held" or not th or not db or not th[0] < held[0] < db[0]:
    bad.append("the release doesn't hold what a new install fails with (after the tests' hold, before the database, said in the held list)")
rp = jobs["report"]
if "install" not in needs("report") or "needs.install.outputs.note" not in json.dumps(rp["steps"][-1].get("env", {})):
    bad.append("the report job doesn't say what a new install fails with")
for b in bad:
    print(b)
sys.exit(1 if bad else 0)
PY
echo "ok ci-workflows"
