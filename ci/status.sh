#!/usr/bin/env bash
# The weekly status (status.yml, Fridays 17:00 Lisbon): one issue saying whether anything needs a look, and what each
# part of AgrOS's upkeep did, the previous week's closed. gh with GH_TOKEN (issues: write here; agros-iso's are public).
#   OWNER   who's told (mentioned: GitHub notifies them)
#   SIZES   the size watch's out dir (ci/sizes.sh, the step before): what it found goes in the issue, and its baseline
#           in the issue's body (a comment, unseen), next week's to compare with
#   ci/status.sh --last-sizes   prints the last issue's baseline (for ci/sizes.sh), nothing if none
#   (AGROS_ISO_REPO, AGROS_SITE: another ISO repo and published [agros] to look at)
set -uo pipefail
iso=${AGROS_ISO_REPO:-CrimzoAgra/agros-iso}
site=${AGROS_SITE:-https://crimzoagra.github.io/agros/x86_64}
last_sizes() {
    gh issue list --label status --state all -L 1 --json body -q '.[0].body' 2>/dev/null |
        sed -n 's|.*<!-- agros-sizes:\([A-Za-z0-9+/=]*\) -->.*|\1|p' | base64 -d 2>/dev/null | gunzip 2>/dev/null
}
if [[ ${1:-} == --last-sizes ]]; then
    last_sizes
    exit 0
fi
problems=()
# last <repo> <workflow file>: its last run on main ("<conclusion> <date>"), and its last good one's date. (Not the
# cancelled ones: a newer run waiting its turn cancels the one waiting before it, every busy day. None finished:
# "none -", not jq's "null null")
last() {
    gh run list -R "$1" -w "$2" -b main -L 50 --json conclusion,status,createdAt \
        -q '[.[] | select(.status == "completed" and .conclusion != "cancelled")] |
            ((.[0] // {conclusion: "none", createdAt: "-"}) | "\(.conclusion) \(.createdAt[:10])"),
            (map(select(.conclusion == "success"))[0].createdAt[:10] // "none")' 2>/dev/null |
        paste -sd' '
}
read -r ci_last ci_day ci_good < <(last "$GITHUB_REPOSITORY" ci.yml) || true
read -r iso_last iso_day iso_good < <(last "$iso" iso.yml) || true
[[ ${ci_last:-} == success ]] || problems+=("AgrOS's CI: its last run ${ci_last:-none} (${ci_day:-}); last good ${ci_good:-none}")
[[ ${iso_last:-} == success ]] || problems+=("The ISO: its last build ${iso_last:-none} (${iso_day:-}); last good ${iso_good:-none}")
held=$(gh issue list --label held --state open --json number,title,url -q '.[] | "\(.title) (\(.url))"' 2>/dev/null)
[[ -z $held ]] || problems+=("$held")
sync=$(gh pr list -R "$iso" --head cachyos --state open --json title,url -q '.[] | "\(.title) (\(.url))"' 2>/dev/null)
[[ -z $sync ]] || problems+=("CachyOS ISO changes waiting for a merge: $sync")
# Hyprland: the newest AgrOS approved, and Arch's
approved=$(curl -fsS --retry 3 "$site/agros-approved" 2>/dev/null | awk '$1 == "hyprland" { v = $2 } END { print v }')
arch=$(curl -fsS --retry 3 https://archlinux.org/packages/extra/x86_64/hyprland/json/ 2>/dev/null | jq -r .pkgver 2>/dev/null)
if [[ -n $approved && -n $arch && $approved != "$arch" ]]; then
    problems+=("Hyprland $arch (Arch's) not approved yet: AgrOS's machines stay on $approved")
fi
# The size watch: each thing it found needs a look; it not having run, too, with its log (or the next week's finds
# nothing to compare with: last week's baseline kept then). (Its table says it ran, not its baseline: a first week
# whose sets pacman couldn't work out has none, and what pacman said goes in the issue)
baseline=$(mktemp)
if [[ -n ${SIZES:-} && -s $SIZES/table ]]; then
    while IFS= read -r line; do problems+=("$line"); done <"$SIZES/report"
    cp "$SIZES/baseline" "$baseline"
else
    log=${GITHUB_RUN_ID:+, its log: ${GITHUB_SERVER_URL:-https://github.com}/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID}
    problems+=("The size watch didn't run (status.yml's Sizes step$log): sizes not compared this week")
    last_sizes >"$baseline"
fi
body=$(mktemp)
# The issue's body: write_body with (the baseline in it) or write_body "". (GitHub takes 65536 characters at most: a
# longer one fails, and no status goes out)
write_body() {
    {
        if ((${#problems[@]})); then
            echo "@${OWNER:?} **Needs a look:**"
            echo
            printf -- '- %s\n' "${problems[@]}"
        else
            echo "@${OWNER:?} **Nothing broke this week.** Everything built, passed its tests and went out."
        fi
        echo
        echo "| | |"
        echo "|---|---|"
        echo "| AgrOS's CI (packages) | last run ${ci_last:-none} ${ci_day:-}, last good ${ci_good:-none} |"
        echo "| The ISO | last build ${iso_last:-none} ${iso_day:-}, last good ${iso_good:-none} |"
        echo "| Hyprland | approved ${approved:-?}, Arch's ${arch:-?} |"
        held_cell=nothing sync_cell="up to date"
        [[ -z $held ]] || held_cell="see above"
        [[ -z $sync ]] || sync_cell="waiting for a merge"
        echo "| Held back | $held_cell |"
        echo "| CachyOS ISO changes | $sync_cell |"
        [[ -z ${SIZES:-} || ! -s $SIZES/table ]] || cat "$SIZES/table"
        [[ -z $1 || ! -s $baseline ]] || printf '\n<!-- agros-sizes:%s -->\n' "$(gzip -9c "$baseline" | base64 -w0)"
    } >"$body"
}
write_body with
if (($(wc -c <"$body") > 65536)); then
    problems+=("The size watch's baseline is too big for the issue: left out, so next week's sizes aren't compared")
    write_body ""
fi
gh label create status --color 0E8A16 --description "Weekly status" --force >/dev/null 2>&1 || true
for n in $(gh issue list --label status --state open --json number -q '.[].number' 2>/dev/null); do
    gh issue close "$n" >/dev/null
done
gh issue create --label status --title "AgrOS status $(TZ=Europe/Lisbon date +%Y-%m-%d)" --body-file "$body"
rm -f "$body" "$baseline"
