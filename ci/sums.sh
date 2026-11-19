#!/usr/bin/env bash
# sums.sh <dir> [<sums>]: the release as CI's release job made it, file for file, in the sign job.
#   ci/sums.sh <dir>           every file under <dir>, a sha256sum line each (paths from <dir>, in C's order): the
#                              release job's output, which no other job can change
#   ci/sums.sh <dir> <sums>    <dir> exactly as <sums> says: the same plain files, none more, none less, each
#                              unchanged (a link in place of one is one less: gpg would sign whatever it points at);
#                              else 1, said
# The sign job signs every package in the release without a signature, and gets the release as an artifact, which a
# job before it could replace: the test job runs this run's builds as root, the repo job AUR build scripts, and either
# can read the runner's artifact token from a step's process and upload, or swap, an artifact of the run (a package
# planted, then signed with AgrOS's key for every machine). The release job's output can't be changed so: this checks
# the artifact against it before the key comes in (ci.yml's sign job; tests/ci-signing.sh checks it's so)
set -euo pipefail
dir=${1:?usage: sums.sh <dir> [<sums>]}
cd "$dir"
# (made: hidden files left out, as upload-artifact leaves them out of the artifact; checked: every one, so one added
# hidden is one too many)
sums() { find . -type f "$@" -print0 | LC_ALL=C sort -z | xargs -0r sha256sum; }
if (($# < 2)); then
    sums ! -path '*/.*'
    exit 0
fi
want=$2
[[ -n $want ]] || { echo "!! no sums from the release job: nothing signed"; exit 1; }
got=$(sums)
[[ $got == "$want" ]] || {
    echo "!! the release isn't as the release job made it: nothing signed"
    diff <(echo "$want") <(echo "$got") | head -20 || true  # (cut off by head: not the failure)
    exit 1
}
echo "-- the release as the release job made it: $(grep -c . <<<"$got") files"
