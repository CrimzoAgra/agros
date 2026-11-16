#!/usr/bin/env bash
# AgrOS's signing key never where AUR build scripts, built packages or tests run: ci/build-repo.sh refuses to start with
# a secret key at hand (the secret in its environment, an old caller's GPGKEY, a key in gpg's keyring), before it makes
# anything; and CI's workflow (.github/workflows/ci.yml) has the key in the release job's signing step alone, after
# every step that reads the build, with its agent stopped and keyring removed when it ends, in a container that isn't
# privileged and has run nothing but official Arch packages' scripts by then
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
    if name != "release" and "AGROS_GPG_KEY" in json.dumps(job):
        bad.append(f"the signing key in the {name} job")
for name in ("repo", "test"):
    if "secrets." in json.dumps(jobs[name]):
        bad.append(f"a secret in the {name} job (it runs AUR build scripts or what was built)")
rel = jobs["release"]
if "privileged" in json.dumps(rel.get("container", {})):
    bad.append("the release job's container privileged")
steps = rel["steps"]
keyed = [i for i, s in enumerate(steps) if "AGROS_GPG_KEY" in json.dumps(s)]
if len(keyed) != 1:
    bad.append(f"the key in {len(keyed)} of the release job's steps, not one")
else:
    k = keyed[0]
    run = steps[k].get("run", "")
    if "ci/sign-repo.sh" not in run:
        bad.append("the key's step doesn't run ci/sign-repo.sh")
    if not ("trap " in run and "gpgconf --kill all" in run and "rm -rf" in run and run.index("trap ") < run.index("--import")):
        bad.append("the key's step doesn't stop gpg's agent and remove the keyring when it ends (a trap before the import)")
    for i, s in enumerate(steps):
        text = json.dumps(s)
        if i > k and ("build-repo.sh" in text or "download-artifact" in text):
            bad.append(f"step {i} reads the build after it was signed: {s.get('name') or s.get('uses')}")
        if i < k and ("pacman -U" in text or "cachyos" in text.lower()):
            bad.append(f"step {i}, before the key, runs packages' scripts besides Arch's: {s.get('name')}")
for name, job in jobs.items():
    text = json.dumps(job)
    if name == "release" and any(w in text for w in ("makepkg", "paru", "tests/run.sh", "test-passes")):
        bad.append("the release job runs a build or the tests")
for b in bad:
    print(b)
sys.exit(1 if bad else 0)
PY
echo "ok ci-signing"
