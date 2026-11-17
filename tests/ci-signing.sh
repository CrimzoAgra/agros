#!/usr/bin/env bash
# AgrOS's signing key never where AUR build scripts, built packages, tests or pacman's repo-add run: ci/build-repo.sh
# refuses to start with a secret key at hand (the secret in its environment, an old caller's GPGKEY, a key in gpg's
# keyring), before it makes anything; and CI's workflow (.github/workflows/ci.yml) has the key in the sign job's signing
# step alone: a job of its own (a container of its own: nothing the release job's repo-add could have left running or
# changed is there), not privileged, that runs nothing before the key but the checkout and the release's files, never
# repo-add or anything that reads a package (repo-add runs a .PKGINFO line of the wrong kind as code), with gpg's agent
# stopped and the keyring removed when the step ends. AgrOS's own packages built in a job of their own (agros), no AUR
# build script there, and the release checks the repo's agros-* packages against that job's sums, and every package's
# .PKGINFO, (ci/own-check.sh) before anything there reads them; its database made by ci/repo-db.sh, after the hold
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
mkdir -m700 "$t/g" "$t/empty"
GNUPGHOME=$t/g gpg --batch --quiet --passphrase '' --quick-gen-key 'AgrOS test <test@agros.invalid>' default sign never >/dev/null 2>&1
build() { env -u AGROS_GPG_KEY -u GPGKEY "$@" "$here/ci/build-repo.sh" "$t/out" 2>&1; }
for how in "GNUPGHOME=$t/g" "GNUPGHOME=$t/empty AGROS_GPG_KEY=secret" "GNUPGHOME=$t/empty GPGKEY=ABCD"; do
    # shellcheck disable=SC2086  # (the variables, each a word)
    out=$(build $how) && fail "built with a secret key at hand ($how)"
    [[ $out == *"A secret signing key is at hand"* ]] || fail "a secret key at hand not said ($how): $out"
    [[ ! -e $t/out ]] || fail "something made before the secret key was found ($how)"
done
# (and without one, not refused: here, not root, it stops at that; as root it would build)
if ((EUID)); then
    out=$(build "GNUPGHOME=$t/empty") && fail "build-repo.sh ran as a normal user"
    [[ $out != *"secret signing key"* && $out == *"Run as root"* ]] || fail "refused with no secret key: $out"
else
    skipped "build-repo.sh without a key: not run as root (it would build)"
fi

# The workflow
python3 - "$here/.github/workflows/ci.yml" <<'PY' || fail "the workflow's signing: see above"
import json, sys, yaml
jobs = yaml.safe_load(open(sys.argv[1]))["jobs"]
bad = []
for name, job in jobs.items():
    if name != "sign" and "AGROS_GPG_KEY" in json.dumps(job):
        bad.append(f"the signing key in the {name} job")
for name in ("agros", "repo", "test", "release"):
    if "secrets." in json.dumps(jobs[name]):
        bad.append(f"a secret in the {name} job (it runs AUR build scripts, what was built, or repo-add)")
sg = jobs.get("sign")
if not sg:
    bad.append("no sign job")
    sg = {"steps": []}
needs = sg.get("needs", [])
if "release" not in ([needs] if isinstance(needs, str) else needs):
    bad.append("the sign job doesn't wait for the release job")
for name in ("release", "sign"):
    if "privileged" in json.dumps(jobs.get(name, {}).get("container", {})):
        bad.append(f"the {name} job's container privileged")
text = json.dumps(sg)
for w in ("repo-add", "build-repo.sh", "repo-db.sh", "own-check.sh", "makepkg", "paru", "tests/run.sh", "test-passes"):
    if w in text:
        bad.append(f"the sign job runs {w} (the key's job reads no package)")
steps = sg["steps"]
keyed = [i for i, s in enumerate(steps) if "AGROS_GPG_KEY" in json.dumps(s)]
if len(keyed) != 1:
    bad.append(f"the key in {len(keyed)} of the sign job's steps, not one")
else:
    k = keyed[0]
    run = steps[k].get("run", "")
    if "ci/sign-repo.sh" not in run:
        bad.append("the key's step doesn't run ci/sign-repo.sh")
    if not ("trap " in run and "gpgconf --kill all" in run and "rm -rf" in run and run.index("trap ") < run.index("--import")):
        bad.append("the key's step doesn't stop gpg's agent and remove the keyring when it ends (a trap before the import)")
    for i, s in enumerate(steps):
        uses = s.get("uses", "")
        if i < k and ("run" in s or not uses.startswith(("actions/checkout@", "actions/download-artifact@"))):
            bad.append(f"step {i}, before the key, runs something besides the checkout and the release's files: {s.get('name') or uses}")
        if i > k and "download-artifact" in uses:
            bad.append(f"step {i} reads files after they were signed: {s.get('name') or uses}")
    got = [s.get("with", {}).get("name") for s in steps[:k] if "download-artifact" in s.get("uses", "")]
    if got != ["unsigned"]:
        bad.append(f"the sign job signs other files than the release job's (unsigned): {got}")
if any(w in json.dumps(jobs["release"]) for w in ("makepkg", "paru", "tests/run.sh", "test-passes")):
    bad.append("the release job runs a build or the tests")
ag = jobs["agros"]
build = [s for s in ag["steps"] if "build-repo.sh" in s.get("run", "")]
if len(build) != 1 or str(build[0].get("env", {}).get("AGROS_SKIP_AUR")) != "1":
    bad.append("the agros job doesn't build AgrOS's own packages alone (AGROS_SKIP_AUR)")
if "privileged" in json.dumps(ag.get("container", {})) or \
        any(w in s.get("run", "") + json.dumps(s.get("env", {})) for s in ag["steps"] for w in ("paru", "AGROS_SKIP_OWN")):
    bad.append("the agros job privileged, or running AUR builds")
rb = [s for s in jobs["repo"]["steps"] if "build-repo.sh" in s.get("run", "")]
if len(rb) != 1 or str(rb[0].get("env", {}).get("AGROS_SKIP_OWN")) != "1":
    bad.append("the repo job builds AgrOS's own packages beside the AUR's (AGROS_SKIP_OWN)")
# The release: own-check.sh before any step that reads a package (the hold's build-repo.sh, repo-db.sh: repo-add), the
# database made by repo-db.sh after the hold, and that what the sign job gets
rs = jobs["release"]["steps"]
idx = lambda w: [i for i, s in enumerate(rs) if w in s.get("run", "")]
own, hold, db = idx("ci/own-check.sh"), idx("build-repo.sh"), idx("ci/repo-db.sh")
if len(own) != 1 or "needs.agros.outputs.sums" not in json.dumps(rs[own[0]].get("env", {})) or \
        "steps.sums.outputs.sums" not in json.dumps(ag.get("outputs", {})):
    bad.append("the release doesn't check AgrOS's own packages against the agros job's output (ci/own-check.sh)")
elif any(i < own[0] for i in hold + db + idx("repo-add") + idx("bsdtar")):
    bad.append("the release reads the packages before ci/own-check.sh checked them")
if len(db) != 1 or any(i > db[0] for i in hold):
    bad.append("the release's database not made by ci/repo-db.sh once, after the hold")
up = [s.get("with", {}) for s in rs if "upload-artifact" in s.get("uses", "")]
if not any(u.get("name") == "unsigned" and u.get("path") == "out" for u in up):
    bad.append("the release doesn't hand the sign job its repo (the unsigned artifact)")
for b in bad:
    print(b)
sys.exit(1 if bad else 0)
PY
echo "ok ci-signing"
