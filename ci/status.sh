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
here=$(cd "$(dirname "$0")/.." && pwd)
last_sizes() {
    gh issue list --label status --state all -L 1 --json body -q '.[0].body' 2>/dev/null |
        sed -n 's|.*<!-- agros-sizes:\([A-Za-z0-9+/=]*\) -->.*|\1|p' | base64 -d 2>/dev/null | gunzip 2>/dev/null
}
if [[ ${1:-} == --last-sizes ]]; then
    last_sizes
    exit 0
fi
problems=()
# last <repo> <workflow file>: its last run on main ("<conclusion> <date>"), its last good one's date, and its id. (Not
# the cancelled ones: a newer run waiting its turn cancels the one waiting before it, every busy day. Not a pull
# request's: one from a fork's own main branch is listed as main's, and its tests passing on the published repo hid a
# failed run of main's. Not a skipped one either: the mirror's after each pull request's CI run, which does nothing.
# None finished: "none -", not jq's "null null")
last() {
    gh run list -R "$1" -w "$2" -b main -L 50 --json conclusion,status,createdAt,databaseId,event \
        -q '[.[] | select(.status == "completed" and .conclusion != "cancelled" and .conclusion != "skipped" and .event != "pull_request")] |
            ((.[0] // {conclusion: "none", createdAt: "-"}) | "\(.conclusion) \(.createdAt[:10])"),
            (map(select(.conclusion == "success"))[0].createdAt[:10] // "none"), (.[0].databaseId // "")' 2>/dev/null |
        paste -sd' '
}
# quiet <date> <days>: its last run that many days ago or more. A daily one that stopped: GitHub turns a public repo's
# schedules off after 60 days without a commit, and nothing else says so
now=$(date -u -d "${AGROS_NOW:-now}" +%s)
quiet() { [[ $1 =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] && (((now - $(date -u -d "$1" +%s)) / 86400 >= $2)); }
read -r ci_last ci_day ci_good ci_id < <(last "$GITHUB_REPOSITORY" ci.yml) || true
read -r iso_last iso_day iso_good iso_id < <(last "$iso" iso.yml) || true
read -r sync_last sync_day sync_good sync_id < <(last "$iso" cachyos-sync.yml) || true
# why <repo> <run id>: a failed run's jobs that failed, and its page ("; <jobs> failed, <url>"): which part to look at
# (CI's iso job alone: everything went out, the ISO build not started; its report job: the held issue not brought up
# to date. One run's failure said without them sent the owner to dig through it)
why() {
    local j
    [[ -n ${2:-} ]] || return 0
    if j=$(gh api "repos/$1/actions/runs/$2/jobs" \
        -q '[.jobs[] | select(.conclusion != "success" and .conclusion != "skipped" and .conclusion != null) | .name] | join(", ")' 2>/dev/null); then
        printf '; %s failed' "${j:-no job}"
    else
        printf "; its jobs couldn't be read"
    fi
    printf ', %s' "${GITHUB_SERVER_URL:-https://github.com}/$1/actions/runs/$2"
}
if [[ ${ci_last:-} != success ]]; then
    w=$(why "$GITHUB_REPOSITORY" "${ci_id:-}")
    # (only the ISO's start failed: AGROS_ISO_TOKEN, a fine-grained token, expires; or Pages slow to serve the database)
    [[ $w != "; iso failed,"* ]] ||
        w+=": the packages went out, but agros-iso's ISO build wasn't started (the AGROS_ISO_TOKEN secret expired or lost its access? Its log says)"
    problems+=("AgrOS's CI: its last run ${ci_last:-none} (${ci_day:-}$w); last good ${ci_good:-none}")
fi
! quiet "${ci_day:-}" 3 || problems+=("AgrOS's CI hasn't run since ${ci_day}: its daily run turned off?")
# The ISO: a run the upstream gate held built nothing (its Upstream gate step ran, its publish job skipped), and GitHub
# shows that wait as a success. Usually gone with CI's next approval; one that stays (the ISO's Hyprland or a library, from
# CachyOS's repos, at a version AgrOS's CI never tested) leaves the published ISO the download for good
if [[ ${iso_last:-} == success && -n ${iso_id:-} ]]; then
    if ! w=$(gh api "repos/$iso/actions/runs/$iso_id/jobs" \
        -q '([.jobs[] | select(.name == "iso") | .steps[] | select(.name == "Upstream gate") | .conclusion][0] == "success") and ([.jobs[] | select(.name == "publish") | .conclusion][0] == "skipped")' 2>/dev/null); then
        problems+=("The ISO: whether its last build waits for AgrOS's check couldn't be read")
    elif [[ $w == true ]]; then
        iso_last=waiting
        problems+=("The ISO: its last build ($iso_day) waits for AgrOS's check of its Hyprland or a library: nothing built, the ISO published before stays the download")
    fi
fi
[[ ${iso_last:-} == success || ${iso_last:-} == waiting ]] ||
    problems+=("The ISO: its last build ${iso_last:-none} (${iso_day:-}$(why "$iso" "${iso_id:-}")); last good ${iso_good:-none}")
# The CachyOS sync: its own steps failing (fetching CachyOS's commits, the merge, the pull request) said here; its ISO
# check failing is the pull request's to say (below)
if [[ ${sync_last:-} != success ]]; then
    f=
    [[ -z ${sync_id:-} ]] || f=$(gh api "repos/$iso/actions/runs/$sync_id/jobs" \
        -q '[.jobs[] | select((.name == "prepare" or .name == "merge") and .conclusion != "success" and .conclusion != "skipped") | .name] | join(", ")' 2>/dev/null) ||
        f="its jobs couldn't be read"
    [[ -z $f && -n ${sync_id:-} ]] ||
        problems+=("The CachyOS sync: its last run ${sync_last:-none} (${sync_day:-}; ${f:-no run}); last good ${sync_good:-none}: CachyOS's changes not followed")
fi
! quiet "${sync_day:-}" 3 || problems+=("The CachyOS sync hasn't run since ${sync_day}: its daily run turned off?")
# The R2 mirror (mirror.yml, after each CI run on main) and each repo's keepalive (keepalive.yml, monthly): GitHub mails
# a failed run to whoever last changed its schedule, and nothing else said it. A mirror that fails leaves machines that
# fall back to it (Pages down) on older packages; a keepalive that fails lets GitHub turn the schedules off after 60
# days without a commit. (None run yet: nothing to say)
read -r mir_last mir_day mir_good mir_id < <(last "$GITHUB_REPOSITORY" mirror.yml) || true
[[ ${mir_last:-none} == success || ${mir_last:-none} == none ]] ||
    problems+=("The R2 mirror: its last run $mir_last (${mir_day:-}$(why "$GITHUB_REPOSITORY" "${mir_id:-}")); last good ${mir_good:-none}: machines that fall back to it (Pages down) get older packages")
keep_cell=
for r in "$GITHUB_REPOSITORY" "$iso"; do
    read -r k_last k_day _ k_id < <(last "$r" keepalive.yml) || true
    keep_cell+="${keep_cell:+, }${r#*/} ${k_last:-none} ${k_day:-}"
    [[ ${k_last:-none} == success || ${k_last:-none} == none ]] ||
        problems+=("The keepalive of ${r#*/}: its last run $k_last (${k_day:-}$(why "$r" "${k_id:-}")): GitHub turns its scheduled workflows off after 60 days without a commit")
done
# (each lookup that fails is said too, never read as nothing to say: the held issue, the CachyOS pull request, the
# approved list, Arch's Hyprland. Since when: what's waited longer than a few days needs a person)
if ! held=$(gh issue list --label held --state open --json title,url,createdAt -q '.[] | "\(.title) (\(.url), open since \(.createdAt[:10]))"' 2>/dev/null); then
    held="CI's held issue couldn't be read: whether anything is held not checked"
fi
# (one line each: two open ones were one item, the second's line under the first's without its own "- ")
while IFS= read -r l; do [[ -z $l ]] || problems+=("$l"); done <<<"$held"
if ! sync=$(gh pr list -R "$iso" --head cachyos --state open --json title,url,createdAt -q '.[] | "\(.title) (\(.url), open since \(.createdAt[:10]))"' 2>/dev/null); then
    sync="its pull request couldn't be read: not checked"
fi
[[ -z $sync ]] || problems+=("CachyOS ISO changes waiting for a merge: $sync")
# Hyprland: the newest AgrOS approved, and Arch's
if approved=$(curl -fsS --retry 3 "$site/agros-approved" 2>/dev/null); then
    approved=$(awk '$1 == "hyprland" { v = $2 } END { print v }' <<<"$approved")
    [[ -n $approved ]] || problems+=("AgrOS's approved list ($site/agros-approved) has no Hyprland: AgrOS's machines get none")
else
    approved=
    problems+=("AgrOS's approved list couldn't be read ($site/agros-approved): AgrOS's machines can't fetch it either")
fi
arch=$(curl -fsS --retry 3 https://archlinux.org/packages/extra/x86_64/hyprland/json/ 2>/dev/null | jq -r .pkgver 2>/dev/null)
[[ -n $arch && $arch != null ]] || { arch=; problems+=("Arch's Hyprland version couldn't be read: whether it's approved not checked"); }
if [[ -n $approved && -n $arch && $approved != "$arch" ]]; then
    problems+=("Hyprland $arch (Arch's) not approved yet: AgrOS's machines stay on $approved")
fi
# Last week's status: none made in the last 10 days (a week, and room for GitHub starting a run hours late) means a
# Friday went by with no issue: its run failed (GitHub mails that only to whoever last changed the schedule), or GitHub
# dropped the scheduled run, which nothing else says. (None ever: the first one, nothing to say)
if prev=$(gh issue list --label status --state all -L 1 --json createdAt -q '.[0].createdAt[:10] // ""' 2>/dev/null); then
    ! quiet "$prev" 10 ||
        problems+=("No status went out last week (the last one: $prev): status.yml's run failed or never started, ${GITHUB_SERVER_URL:-https://github.com}/$GITHUB_REPOSITORY/actions/workflows/status.yml")
else
    problems+=("Last week's status couldn't be looked up: whether it went out not checked")
fi
# Caelestia's dots: pinned by commit (agros-hyprland-settings' _dots), a new one taken on purpose; how far upstream has
# gone since, in the table (nothing else says it; a pin fails nothing, so not a problem)
dots=$(sed -n 's/^_dots=//p' "$here/packages/agros-hyprland-settings/PKGBUILD")
dots_cell="pinned ${dots:0:7}"
if [[ -n $dots ]] && d=$(gh api "repos/caelestia-dots/caelestia/compare/$dots...HEAD" \
    -q '"\(.ahead_by) \(.base_commit.commit.committer.date[:10])"' 2>/dev/null); then
    read -r n since <<<"$d"
    dots_cell+=" ($since), $n newer commit(s) upstream"
else
    dots_cell+=", upstream couldn't be read"
fi
# CachyOS's installer recipe: pinned too (ci/build-repo.sh's calamares_pkgbuild); a change of theirs since is a problem
# (a look needed: their recipe's own changes, a new name or branch, reach AgrOS's installer only once it's moved on)
cpin=$(sed -n 's/^ *calamares_pkgbuild=//p' "$here/ci/build-repo.sh")
if c=$(gh api "repos/CachyOS/CachyOS-PKGBUILDS/commits?path=cachyos-calamares&per_page=1" \
    -q '.[0] | "\(.sha) \(.commit.committer.date[:10])"' 2>/dev/null) && [[ -n $c ]]; then
    read -r newest when <<<"$c"
    [[ $newest == "$cpin" ]] ||
        problems+=("CachyOS changed its installer's recipe (cachyos-calamares, ${newest:0:8}, $when) since AgrOS's pin (${cpin:0:8}): look at it, then move calamares_pkgbuild on (ci/build-repo.sh)")
else
    problems+=("CachyOS's installer recipe couldn't be read: whether it changed since AgrOS's pin not checked")
fi
# ...and its code (calamares_src, on the recipe's branch, cachyos): new commits there since, how many (their staging
# branch, which their own ISO builds, is the cachyos branch plus what comes next: a move there shows up here in time)
csrc=$(sed -n 's/^ *calamares_src=//p' "$here/ci/build-repo.sh")
if c=$(gh api "repos/CachyOS/cachyos-calamares/compare/$csrc...cachyos" \
    -q '"\(.ahead_by) \(.base_commit.commit.committer.date[:10])"' 2>/dev/null) && [[ -n $c ]]; then
    read -r n since <<<"$c"
    ((n == 0)) ||
        problems+=("CachyOS's installer has $n new commit(s) on its cachyos branch since AgrOS's pin (${csrc:0:8}, $since): look at them, then move calamares_src on (ci/build-repo.sh)")
else
    problems+=("CachyOS's installer code couldn't be read: whether it changed since AgrOS's pin not checked")
fi
# The AUR packages [agros] carries (aur/packages.txt, and Quickshell): who can change their build files now, against who
# could when AgrOS last looked (aur/maintainers.txt). CI builds them unreviewed and AgrOS's key signs them for every
# machine, so a new maintainer (an orphan adopted, a co-maintainer added) is someone to look at before their next
# change goes out; the machines' own AUR builds hold such a package for review (auto-update-aur), [agros]'s nothing
# else would say. One the AUR no longer has: CI keeps its last build, never updated again
# (a name as ci/own-check.sh reads it: an "aur/" before it taken off)
mapfile -t aurs < <({
    sed -e 's/#.*//' -e 's/[[:space:]]//g' -e 's|^.*/||' "$here/aur/packages.txt" | grep .
    echo quickshell-git
} | LC_ALL=C sort -u)
aur_cell="${#aurs[@]} packages, their maintainers as recorded"
# (-g: the address's [] taken as they are, not as curl's ranges)
if a=$(curl -gfsS --retry 3 "https://aur.archlinux.org/rpc/v5/info?$(printf 'arg[]=%s&' "${aurs[@]}")" 2>/dev/null) &&
    [[ $(jq -r .type <<<"$a" 2>/dev/null) == multiinfo ]] &&
    now=$(jq -r '.results[] | "\(.Name) \(.PackageBase) \(.Maintainer // "-"):\(.CoMaintainers // [] | sort | join(","))"' <<<"$a"); then
    n=0
    for p in "${aurs[@]}"; do
        read -r _ base who < <(awk -v p="$p" '$1 == p' <<<"$now") || true
        if [[ -z ${base:-} ]]; then
            problems+=("$p is gone from the AUR (deleted, or renamed): CI keeps its last build in [agros], never updated again")
            n=$((n + 1))
            continue
        fi
        was=$(awk -v b="$base" '$1 == b { print $2 }' "$here/aur/maintainers.txt")
        if [[ $was != "$who" ]]; then
            problems+=("$base's AUR maintainers changed (${was:-none recorded} to $who): CI builds and signs it unreviewed for every machine; look at its build files' changes since (its AUR page's git log), then update aur/maintainers.txt")
            n=$((n + 1))
        fi
    done
    ((n == 0)) || aur_cell="${#aurs[@]} packages, $n to look at (above)"
else
    problems+=("The AUR couldn't be read: whether [agros]'s AUR packages changed maintainers not checked")
    aur_cell="${#aurs[@]} packages, the AUR couldn't be read"
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
        echo "| The CachyOS sync | last run ${sync_last:-none} ${sync_day:-}, last good ${sync_good:-none} |"
        echo "| The R2 mirror | last run ${mir_last:-none} ${mir_day:-}, last good ${mir_good:-none} |"
        echo "| Keepalive | last run $keep_cell |"
        echo "| Hyprland | approved ${approved:-?}, Arch's ${arch:-?} |"
        echo "| Caelestia's dots | $dots_cell |"
        echo "| [agros]'s AUR packages | $aur_cell |"
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
# The new one first, tried three times (GitHub's API drops a call now and then), and only then last week's closed: a
# create that failed after they were closed left no status open, and the run, ending on rm, passed with none sent. One
# that still fails fails the run (GitHub mails its failure to whoever last changed the schedule) and last week's stays
new=
for i in 1 2 3; do
    new=$(gh issue create --label status --title "AgrOS status $(TZ=Europe/Lisbon date +%Y-%m-%d)" --body-file "$body") && break
    new=
    ((i == 3)) || sleep "${AGROS_RETRY_WAIT:-60}"
done
rm -f "$body" "$baseline"
[[ -n $new ]] || { echo "::error::The status issue couldn't be made: none sent this week"; exit 1; }
echo "$new"
# (only older ones: two runs at once, a manual one beside Friday's, each closing the other's left none open)
new=${new##*/}
for n in $(gh issue list --label status --state open --json number -q '.[].number' 2>/dev/null); do
    [[ $n =~ ^[0-9]+$ && $new =~ ^[0-9]+$ ]] && ((n < new)) && gh issue close "$n" >/dev/null
done
exit 0
