#!/usr/bin/env bash
# The weekly status (status.yml, Fridays 17:00 Lisbon): one issue saying whether anything needs a look, and what each
# part of AgrOS's upkeep did, the previous week's closed. gh with GH_TOKEN (issues: write here; agros-iso's are public).
#   OWNER   who's told (mentioned: GitHub notifies them)
set -uo pipefail
iso=${AGROS_ISO_REPO:-CrimzoAgra/agros-iso}
site=${AGROS_SITE:-https://crimzoagra.github.io/agros/x86_64}
problems=()
# last <repo> <workflow file>: its last run on main ("<conclusion> <date>"), and its last good one's date
last() {
    gh run list -R "$1" -w "$2" -b main -L 20 --json conclusion,status,createdAt \
        -q '[.[] | select(.status == "completed")] | (.[0] | "\(.conclusion) \(.createdAt[:10])"), ([.[] | select(.conclusion == "success")][0].createdAt[:10] // "none")' 2>/dev/null |
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
body=$(mktemp)
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
} >"$body"
gh label create status --color 0E8A16 --description "Weekly status" --force >/dev/null 2>&1 || true
for n in $(gh issue list --label status --state open --json number -q '.[].number' 2>/dev/null); do
    gh issue close "$n" >/dev/null
done
gh issue create --label status --title "AgrOS status $(TZ=Europe/Lisbon date +%Y-%m-%d)" --body-file "$body"
rm -f "$body"
