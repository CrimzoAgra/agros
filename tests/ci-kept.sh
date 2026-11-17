#!/usr/bin/env bash
# ci/kept.sh: a file the release puts out again, as the site has it; empty when not published yet (a 404); anything
# else (an error page, Pages unreachable) fails, said, and leaves no file to publish. Only the current copy asked for,
# a ?t= query past the CDN's. curl is a stand-in, answering as $CODE and $RC say, the URL it was given in $t/url
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
mkdir -p "$t/bin"
# shellcheck disable=SC2016
printf '#!/bin/bash\necho "${*: -1}" >%s/url\nwhile (($#)); do [[ $1 == -o ]] && { echo "body $CODE" >"$2"; }; shift; done\nprintf %%s "$CODE"\nexit "${RC:-0}"\n' "$t" >"$t/bin/curl"
chmod +x "$t/bin/curl"
go() { CODE=$1 RC=${2:-0} PATH=$t/bin:$PATH "$here/ci/kept.sh" https://site/f "$t/f"; }
go 200 >/dev/null || fail "a published file not kept"
grep -Eqx 'https://site/f\?t=[0-9]+' "$t/url" || fail "not the current copy asked for (?t=): $(cat "$t/url")"
[[ $(cat "$t/f") == "body 200" ]] || fail "the published file not as the site has it: $(cat "$t/f")"
go 404 >/dev/null || fail "not published yet: a failure"
[[ -e $t/f && ! -s $t/f ]] || fail "not published yet: not empty"
for c in "500 0" "000 7" "200 28"; do
    # shellcheck disable=SC2086  # (code and exit status)
    out=$(go $c) && fail "$c: not a failure"
    [[ ! -e $t/f ]] || fail "$c: a file left to publish: $(cat "$t/f")"
    grep -q "^::error::https://site/f couldn't be read" <<<"$out" || fail "$c: not said: $out"
done
echo "ok ci-kept"
