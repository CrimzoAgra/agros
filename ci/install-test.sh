#!/usr/bin/env bash
# install-test.sh <repo dir>: the release's [agros] (unsigned, before the sign job) installed for real, as a new install
# gets it (CI's install job, root in a privileged container): base and every agros-* package (agros-desktop and what it
# pulls in) into an empty root, pacstrap's mounts there, with the container's pacman.conf, [cachyos] above Arch's as
# machines have it (the job sets it up), [agros] last, nothing left out (its NoExtract lines dropped).
# What stops machines' updates stops this: a file two packages ship (an Arch or CachyOS package that starts shipping one
# of AgrOS's), two packages in conflict, a dependency not met, an [agros] package's install script failing (pacman goes
# on, saying "error: command failed to execute correctly"). The [agros] package it names, when it's this run's new build
# (no .sig: one kept as published keeps its signature), is held, as a package that doesn't build (ci/published.sh's
# hold_new: the published one kept), and the install tried again with it held, AGROS_INSTALL_ROUNDS times at most; one
# whose published one fails too isn't held (no help), said. Nothing of [agros]'s to hold (Arch's packages at odds with
# each other), or a download that kept failing (tried 3 times: not run, not broken): said, and the release goes out as
# it is, as it did before this test. Hooks aren't judged (a root no system has booted).
# Writes hold=<"<name>: <why>" lines> (AGROS_HOLD_ONLY: the release job holds them) and note=<lines for CI's held issue>
# to $GITHUB_OUTPUT
set -uo pipefail
export LC_ALL=C
here=$(cd "$(dirname "$0")/.." && pwd)
dir=$(cd "${1:?usage: install-test.sh <repo dir>}" && pwd)
out=${GITHUB_OUTPUT:-/dev/stdout}
copy=$dir.held
w=$(mktemp -d)
root=$w/root
umnt() { local m; for m in run dev sys proc; do umount -R "$root/$m" 2>/dev/null; done; }
# (--one-file-system: a mount left, /dev's, never emptied through)
trap 'umnt; rm -rf --one-file-system "$w" "$copy"' EXIT
# A download that failed, or no room: the install not run, not broken
netfail='failed retrieving file|failed to retrieve some files|failed to synchronize all databases|invalid or corrupted database|not enough free disk space|Could not resolve host'
declare -A hold=() stuck=()
notes=()
passed=
for ((round = 1; round <= ${AGROS_INSTALL_ROUNDS:-3}; round++)); do
    repo=$dir
    if ((${#hold[@]})); then
        repo=$copy
        rm -rf "$copy" && cp -a "$dir" "$copy" &&
            AGROS_HOLD_ONLY=$(for n in "${!hold[@]}"; do echo "$n: ${hold[$n]}"; done) AGROS_HELD=/dev/null \
                "$here/ci/build-repo.sh" "$copy" --hold-new && "$here/ci/repo-db.sh" "$copy" ||
            { notes+=("the install couldn't be tried again with ${!hold[*]} held (the published ones not fetched)"); break; }
    fi
    # [agros]'s packages, and which are new builds
    declare -A ours=() new=()
    while read -r n f; do
        ours[$n]=1
        [[ -e $repo/$f.sig ]] || new[$n]=1
    done < <(bsdtar -xOf "$repo/agros.db" '*/desc' 2>/dev/null |
        awk '/^%[A-Z0-9]+%$/ { k = $0; next } NF && k == "%FILENAME%" { f = $0 } NF && k == "%NAME%" { print $0, f }')
    mapfile -t pkgs < <(printf '%s\n' "${!ours[@]}" | grep '^agros-' | sort)
    ((${#pkgs[@]})) || { notes+=("the install test found no agros-* package in the release"); break; }
    # An empty root, mounted as pacstrap does
    umnt
    rm -rf --one-file-system "$root"
    mkdir -p "$root"/{var/cache/pacman/pkg,var/lib/pacman,var/log,dev,run,etc,tmp,sys,proc}
    chmod 1777 "$root/tmp"
    chmod 0555 "$root"/{sys,proc}
    { mount proc "$root/proc" -t proc -o nosuid,noexec,nodev && mount sys "$root/sys" -t sysfs -o nosuid,noexec,nodev,ro &&
        mount --bind /dev "$root/dev" && mount run "$root/run" -t tmpfs -o nosuid,nodev,mode=0755; } ||
        { notes+=("the install test couldn't mount its root's /proc, /sys, /dev"); break; }
    { grep -v '^[[:space:]]*NoExtract' "${PACMAN_CONF:-/etc/pacman.conf}"
        printf '\n[agros]\nSigLevel = Optional TrustedOnly\nServer = file://%s\n' "$repo"; } >"$w/pacman.conf"
    for try in 1 2 3; do
        echo "-- install test, round $round, try $try: base ${pkgs[*]}"
        log=$(pacman --config "$w/pacman.conf" -r "$root" -Sy --noconfirm --noprogressbar base "${pkgs[@]}" 2>&1)
        rc=$?
        printf '%s\n' "$log"
        ((rc)) && grep -Eq "$netfail" <<<"$log" || break
        ((try == 3)) || sleep "${AGROS_RETRY_WAIT:-60}"
    done
    if ((rc)) && grep -Eq "$netfail" <<<"$log"; then
        notes+=("the install test couldn't run (a download kept failing, or no room: not known whether it installs): $(grep -E "$netfail" <<<"$log" | tail -n1)")
        break
    fi
    # What failed, by the packages it names ("<name><tab><pacman's line>"): an install script's (the package being
    # installed, not a hook's), a file two ship, a conflict, a dependency not met; only [agros]'s kept
    hits=$(awk '
        /^:: Running (pre|post)-transaction hooks/ { cur = ""; next }
        /^(installing|upgrading|reinstalling) [^ ]+\.\.\.$/ { cur = $2; sub(/\.\.\.$/, "", cur); next }
        /command failed to execute correctly/ { if (cur != "") print cur "\tits install script failed"; next }
        / exists in both \047/ { split($0, q, "\047"); print q[2] "\t" $0; print q[4] "\t" $0; next }
        / exists in filesystem/ { x = $1; sub(/:$/, "", x); print x "\t" $0
            if (match($0, /owned by [^)]+/)) print substr($0, RSTART + 9, RLENGTH - 9) "\t" $0; next }
        / required by [^ ]+$/ { print $NF "\t" $0; next }
        / are in conflict/ { l = $0; sub(/^:: /, "", l); sub(/ are in conflict.*/, "", l)
            n = split(l, p, " and "); for (i = 1; i <= n; i++) print p[i] "\t" $0 }' <<<"$log" |
        while IFS=$'\t' read -r n why; do [[ -z ${ours[$n]:-} ]] || printf '%s\t%s\n' "$n" "$why"; done)
    [[ -n $hits ]] || ((rc)) || { passed=1; break; }
    [[ -n $hits ]] || {
        notes+=("a new install fails, nothing of [agros]'s to hold: $(grep -E '^(error|::)' <<<"$log" | tail -n3 | paste -sd' ')")
        break
    }
    # Each new build it names held; one already held (its published one in) that fails too: back, not held (no help).
    # (a published one named beside a new build, the other side of its file conflict: not that one's doing)
    blamed=$(while IFS=$'\t' read -r n why; do [[ -z ${new[$n]:-} ]] || echo "$why"; done <<<"$hits")
    changed=
    while IFS=$'\t' read -r n why; do
        if [[ -z ${new[$n]:-} ]] && grep -qxF -- "$why" <<<"$blamed"; then
            continue
        elif [[ -n ${new[$n]:-} ]]; then
            [[ -n ${hold[$n]:-} || -n ${stuck[$n]:-} ]] || { hold[$n]="a new install fails with its new build: $why" changed=1; }
        elif [[ -n ${hold[$n]:-} ]]; then
            unset "hold[$n]"
            stuck[$n]=$why changed=1
        else
            stuck[$n]=${stuck[$n]:-$why}
        fi
    done <<<"$hits"
    [[ -n $changed ]] || break
done
for n in "${!stuck[@]}"; do notes+=("$n: a new install fails with it, as published too (not held: no help): ${stuck[$n]}"); done
if [[ -z $passed && ${#notes[@]} == 0 ]]; then
    notes+=("a new install still fails after $((round - 1)) tries, with ${!hold[*]} held: $(grep -E '^(error|::)' <<<"$log" | tail -n3 | paste -sd' ')")
fi
{
    echo 'hold<<EOF'
    for n in "${!hold[@]}"; do echo "$n: ${hold[$n]}"; done | sort
    echo EOF
    echo 'note<<EOF'
    if ((${#notes[@]})); then printf '%s\n' "${notes[@]}"; fi
    echo EOF
} >>"$out"
if [[ -n $passed ]]; then echo "-- a new install goes through${hold[*]:+ with ${!hold[*]} held}"; fi
if ((${#notes[@]})); then printf '::warning::%s\n' "${notes[@]}"; fi
exit 0
