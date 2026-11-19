#!/usr/bin/env bash
# ci/newer.sh (CI's release job): a re-run of an older run on main never puts its repo out over a newer commit's.
# newer=true only when the published agros-system's commit comes after this checkout's on main as it now is; this
# commit's own, an older one, one main no longer has (pushed over), none published yet, or none named: newer=false.
# A database it can't read, or whose signature isn't AgrOS's key's, fails it. A git history here (A, B, C on main), the
# published repo a stand-in curl serves from $t/site, signed with a key of the test's own
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
command -v gpg >/dev/null && command -v bsdtar >/dev/null || { skipped "no gpg or bsdtar"; echo "skip ci-newer (no gpg or bsdtar)"; exit 0; }
export GNUPGHOME=$t/gnupg
mkdir -m700 "$GNUPGHOME"
gpg --batch --quiet --passphrase '' --quick-gen-key 'AgrOS test <test@agros.invalid>' default sign never >/dev/null 2>&1
gpg --batch --quiet --armor --export >"$t/key.asc"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
git init -q -b main "$t/up"
mkdir "$t/up/ci" && cp "$here/ci/newer.sh" "$t/up/ci/"
for c in A B C; do echo "$c" >"$t/up/f" && git -C "$t/up" add -A && git -C "$t/up" commit -qm "$c"; done
git clone -q "$t/up" "$t/c"
A=$(git -C "$t/c" rev-parse HEAD~2) B=$(git -C "$t/c" rev-parse HEAD~1) C=$(git -C "$t/c" rev-parse HEAD)
# publish <agros-system's version>: the site's database lists it (signed)
mkdir -p "$t/site"
publish() {
    local s; s=$(mktemp -d)
    mkdir "$s/agros-system-$1" "$s/other-1-1"
    printf '%%FILENAME%%\nagros-system-%s-any.pkg.tar.zst\n\n%%NAME%%\nagros-system\n\n%%VERSION%%\n%s\n\n' "$1" "$1" >"$s/agros-system-$1/desc"
    printf '%%FILENAME%%\nother-1-1-any.pkg.tar.zst\n\n%%NAME%%\nother\n\n%%VERSION%%\n1-1\n\n' >"$s/other-1-1/desc"
    rm -f "$t/site/agros.db.sig" && (cd "$s" && tar -czf "$t/site/agros.db" .)
    gpg --batch --quiet --detach-sign -o "$t/site/agros.db.sig" "$t/site/agros.db"
    rm -rf "$s"
}
# (curl: -o's file from $t/site; with -w its HTTP code ($CODE when set), 404 when missing; without, a missing one
# fails, as -f. Only the current copy asked for, a ?t= query past the CDN's: without one, nothing served)
stub curl 'w=; while (($#)); do case $1 in -o) o=$2; shift ;; -w) w=1; shift ;; --retry|--retry-delay) shift ;; https://*) u=$1 ;; esac; shift; done
[[ $u == *"?t="[0-9]* ]] || { [[ -z $w ]] || printf 000; exit 7; }
[[ -z ${CODE:-} ]] || { printf %s "$CODE"; exit 0; }
u=${u%%\?*}
f='"$t"'/site/${u#https://site/}
if [[ -f $f ]]; then cp "$f" "$o"; [[ -z $w ]] || printf 200; elif [[ -n $w ]]; then printf 404; else exit 22; fi'
# at <commit>: newer.sh run with that commit checked out, as CI's checkout of it; its output, newer=... last
at() {
    git -C "$t/c" checkout -q --detach "$1"
    rm -f "$t/out"
    PATH=$t/bin:$PATH GITHUB_OUTPUT=$t/out AGROS_PUBKEY=$t/key.asc "$t/c/ci/newer.sh" https://site 2>&1 && cat "$t/out"
}
expect() { local o; o=$(at "$1") || fail "$3: failed: $o"; [[ ${o##*$'\n'} == "newer=$2" ]] || fail "$3: not newer=$2: $o"; }
publish "r3.${C::7}-1"
expect "$A" true "an older commit re-run, the newest published"
expect "$B" true "the one before the newest re-run, the newest published"
expect "$C" false "the newest commit, its own repo published"
publish "r1.${A::7}-1"
expect "$C" false "a newer commit, an older one published"
publish "r9.1234567-1"
expect "$A" false "the published commit unknown here"
publish "1.0-1"
expect "$A" false "the published agros-system names no commit"
# main pushed back to B (C dropped): C's repo, published, no longer main's; B is put out again
publish "r3.${C::7}-1"
git -C "$t/up" reset -q --hard "$B" && git -C "$t/c" fetch -q --prune origin
expect "$B" false "main pushed back over the published commit"
rm "$t/site/agros.db" "$t/site/agros.db.sig"
expect "$A" false "nothing published yet"
# Not readable, not AgrOS's: a failure, said, no answer written
publish "r3.${C::7}-1"
echo x >>"$t/site/agros.db.sig"
o=$(at "$A") && fail "a database whose signature doesn't check out read: $o"
[[ ! -s $t/out && $o == *"::error::"* ]] || fail "a bad signature not said, or an answer written: $o"
publish "r3.${C::7}-1"
o=$(CODE=503 at "$A") && fail "Pages answering 503 read as an answer: $o"
[[ ! -s $t/out && $o == *"(HTTP 503)"* ]] || fail "Pages' 503 not said: $o"

# The workflow: the release job asks it, with main's history (a full checkout), as its output; the sign job (and so
# Pages' deploy and the ISO after it) skipped when it says newer; the report job told
python3 - "$here/.github/workflows/ci.yml" <<'PY' || fail "the workflow's newer check: see above"
import json, sys, yaml
jobs = yaml.safe_load(open(sys.argv[1]))["jobs"]
bad = []
rel = jobs["release"]
st = [s for s in rel["steps"] if "ci/newer.sh" in s.get("run", "")]
if len(st) != 1 or rel.get("outputs", {}).get("newer") != "${{ steps.%s.outputs.newer }}" % st[0].get("id"):
    bad.append("the release job doesn't hand on ci/newer.sh's answer (outputs.newer)")
co = [s for s in rel["steps"] if s.get("uses", "").startswith("actions/checkout@")]
if not co or str(co[0].get("with", {}).get("fetch-depth")) != "0":
    bad.append("the release job's checkout without main's history (fetch-depth: 0)")
if "needs.release.outputs.newer != 'true'" not in str(jobs["sign"].get("if", "")):
    bad.append("the sign job not skipped when a newer commit is published")
need = lambda j: [j["needs"]] if isinstance(j["needs"], str) else j["needs"]
if "sign" not in need(jobs["publish"]) or "publish" not in need(jobs["iso"]):
    bad.append("Pages' deploy or the ISO not after the sign job")
if "needs.release.outputs.newer" not in json.dumps(jobs["report"]):
    bad.append("the report job not told (NEWER)")
for b in bad:
    print(b)
sys.exit(1 if bad else 0)
PY
echo "ok ci-newer"
