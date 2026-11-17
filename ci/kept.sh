#!/usr/bin/env bash
# kept.sh <url> <file>: a file the release puts out again, as the site has it now (CI's release job: the upstream gate's
# approved list, the day Arch last passed the tests). Only "not published yet", a 404, leaves <file> empty; anything
# else (Pages down, a timeout) fails, said, rather than the release putting out the site without it: without the
# earlier approvals, machines a build behind were held; without the day, the next Arch update that broke the tests read
# as AgrOS's own code (ci/test-passes.sh), and nothing went out
set -uo pipefail
usage="usage: kept.sh <url> <file>"
url=${1:?$usage} file=${2:?$usage}
# (?t=: Pages' CDN keeps a copy up to 10 minutes after a deploy, and an older list put out again lost that run's
# approvals; the query asks for the current one, as mirror.sh's fetch)
code=$(curl -sS --retry 3 -o "$file" -w '%{http_code}' "$url?t=$(date +%s)") || code=000
case $code in
    200) ;;
    404) : >"$file" ;;
    *) rm -f "$file"; echo "::error::$url couldn't be read (HTTP $code): not put out again without it"; exit 1 ;;
esac
