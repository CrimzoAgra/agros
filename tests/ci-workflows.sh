#!/usr/bin/env bash
# Every workflow in .github/workflows: a permissions block of its own (the token read-only unless a job says otherwise),
# never pull_request_target (a fork's code run with the secrets and a token that writes), no ${{ }} in a run: script
# (a branch name or an issue's title pasted into bash: passed through env: instead, as each one does), each job a
# time limit (a hang stopped, not run on to GitHub's 6 hours), and each curl there tried again (--retry)
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
python3 - "$here"/.github/workflows/*.yml <<'PY' || fail "the workflows: see above"
import sys, yaml
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
for b in bad:
    print(b)
sys.exit(1 if bad else 0)
PY
echo "ok ci-workflows"
