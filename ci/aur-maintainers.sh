#!/usr/bin/env bash
# Who can change the build files of each AUR package [agros] carries (aur/packages.txt, and quickshell-git), and which
# of them CI holds for now (CI's agros job, before any build: no AUR build script has run there, and what it finds goes
# on as that job's outputs, which no other job can change):
#   ci/aur-maintainers.sh <site> <state> <held>
# CI builds these unreviewed and AgrOS's key signs them for every machine, so one whose AUR maintainers changed (an
# orphan adopted, a co-maintainer added: one can push its build files too) isn't built from theirs at once: its last
# build stays, as published, for AGROS_AUR_WAIT days (14) from the day CI first saw the change (time for the AUR's own
# people and the package's other users to catch a bad one), then the new maintainers are taken and it's built again,
# nobody asked. A further change starts the wait again; one undone ends it. One the AUR no longer has (deleted, or
# renamed: its name free for anyone to take) keeps its last build for good, and the weekly status (ci/status.sh) says
# it: that one needs a person. First seen (no line for it: the first run, a package just added to aur/packages.txt,
# which is its review): taken as they are.
# The state is CI's own, no list kept by hand: published beside the repo's database (agros-aur-maintainers, signed by
# the sign job as the approved list is) and read back from <site>, this repo's own, its signature checked against
# ci/agros.asc alone; only a 404 (none published yet) starts it afresh, anything else stops here (as ci/kept.sh), not a
# run that takes every package's maintainers as they are now. Its lines: "<name> <maintainers>", the maintainers as one
# word, "<maintainer>:<co-maintainers, sorted, a comma between two>" ("-" for none: auto-update-aur keeps the machines'
# own the same way); then " <new maintainers> <YYYY-MM-DD>" while a change waits (the day first seen), or
# " gone <YYYY-MM-DD>" for one the AUR no longer has; and "# checked <YYYY-MM-DD>", the last day the AUR answered (the
# status says when that's days ago). Writes <state> (the new one, which the release publishes) and <held> ("<name>
# <base> <why>" each one to hold: build-repo.sh's AGROS_AUR_HELD). The AUR not answering: the state as it was, those it
# held still held.
# (AGROS_NOW: another day than today; AGROS_PUBKEY: another key file, a test's)
set -uo pipefail
usage="usage: aur-maintainers.sh <site> <state> <held>"
site=${1:?$usage} state=${2:?$usage} heldf=${3:?$usage}
root=$(cd "$(dirname "$0")/.." && pwd)
days=${AGROS_AUR_WAIT:-14}
today=$(date -u -d "${AGROS_NOW:-now}" +%F)
h=$(mktemp -d)
trap 'rm -rf "$h"' EXIT
# (?t=: Pages' CDN keeps a copy up to 10 minutes after a deploy, as ci/kept.sh's fetch)
stamp=$(date +%s)
code=$(curl -sS --retry 8 --retry-delay 15 -o "$h/before" -w '%{http_code}' "$site/agros-aur-maintainers?t=$stamp") || code=000
case $code in
    404) : >"$h/before" ;;
    200)
        { curl -fsS --retry 8 --retry-delay 15 -o "$h/before.sig" "$site/agros-aur-maintainers.sig?t=$stamp" &&
            gpg --homedir "$h" --batch --quiet --dearmor -o "$h/key.gpg" <"${AGROS_PUBKEY:-$root/ci/agros.asc}" &&
            gpgv --keyring "$h/key.gpg" "$h/before.sig" "$h/before" >/dev/null 2>&1; } ||
            { echo "::error::$site/agros-aur-maintainers has no good signature by AgrOS's key: not taken"; exit 1; } ;;
    *) echo "::error::$site/agros-aur-maintainers couldn't be read (HTTP $code)"; exit 1 ;;
esac
# (a name as ci/own-check.sh reads it: an "aur/" before it taken off)
mapfile -t names < <({
    sed -e 's/#.*//' -e 's/[[:space:]]//g' -e 's|^.*/||' "$root/aur/packages.txt" | grep .
    echo quickshell-git
} | LC_ALL=C sort -u)
# who <maintainers>: as said ("alice", "alice, co-maintained by bob,carol"; an orphan's "-": "no one")
who() {
    local m=${1%%:*}
    [[ $m != - ]] || m="no one"
    if [[ $1 == *:?* ]]; then echo "$m, co-maintained by ${1#*:}"; else echo "$m"; fi
}
# why <name> <maintainers> <waiting> <since>: why it's held, as the held issue and the build's log say it
why() {
    if [[ $3 == gone ]]; then
        echo "gone from the AUR since $4 (deleted, or renamed): its last build kept, not built again"
    else
        echo "its AUR maintainers changed ($(who "$2") to $(who "$3")) on $4: its last build kept until $(date -u -d "$4 + $days days" +%F), then built from theirs"
    fi
}
: >"$heldf"
# (-g: the address's [] taken as they are, not as curl's ranges)
if ! a=$(curl -gfsS --retry 3 "https://aur.archlinux.org/rpc/v5/info?$(printf 'arg[]=%s&' "${names[@]}")" 2>/dev/null) ||
    [[ $(jq -r .type <<<"$a" 2>/dev/null) != multiinfo ]] ||
    ! now=$(jq -r '.results[] | "\(.Name) \(.PackageBase) \(.Maintainer // "-"):\(.CoMaintainers // [] | sort | join(","))"' <<<"$a"); then
    echo "!! The AUR couldn't be read: its packages' maintainers as CI last saw them, those held still held"
    cp "$h/before" "$state"
    while read -r n was waiting since; do
        [[ $n != '#' && -n $since ]] && echo "$n $n $(why "$n" "$was" "$waiting" "$since")"
    done <"$h/before" >>"$heldf"
    exit 0
fi
{
    echo "# checked $today"
    for n in "${names[@]}"; do
        read -r _ base is < <(awk -v n="$n" '$1 == n' <<<"$now") || true
        read -r _ was waiting since < <(awk -v n="$n" '$1 == n' "$h/before") || true
        if [[ -z ${base:-} ]]; then
            [[ ${waiting:-} == gone ]] || since=$today
            echo "$n ${was:--} gone $since"
            echo "$n $n $(why "$n" "${was:--}" gone "$since")" >>"$heldf"
        elif [[ -z ${was:-} || $was == "$is" ]]; then
            echo "$n $is"
        elif [[ ${waiting:-} == "$is" ]] && (($(date -u -d "$today" +%s) >= $(date -u -d "$since + $days days" +%s))); then
            echo "-- $n: its new AUR maintainers ($(who "$is")) taken, $days days after the change" >&2
            echo "$n $is"
        else
            [[ ${waiting:-} == "$is" ]] || since=$today
            echo "$n $was $is $since"
            echo "$n $base $(why "$n" "$was" "$is" "$since")" >>"$heldf"
        fi
        base='' was='' waiting='' since=''
    done
} >"$state"
cat "$heldf"
