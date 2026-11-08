#!/usr/bin/env bash
# capri-update (stand-in repos and npm, as tests/capri-update.sh) when a release and my fork don't fit: the conflicts
# with a rule of their own settled (a file my fork deleted, her lines), a pre-release not taken over its release, a
# release failing her tests not switched to, and a newest release that doesn't merge: my fork still installed (a first
# install) and updated, with the release it has. What fails the same every time (a lockfile that doesn't match, a
# download failing three runs in a row, a release with no history in common) written down as that release's, not tried
# again. One run at a time: a --check during an update says nothing, an update
# waits
set -uo pipefail
. "$(dirname "$0")/lib.sh"
g() { git -C "$1" -c user.name=t -c user.email=t@t "${@:2}"; }
git init -q -b main "$t/up"
mkdir -p "$t/up/assets" "$t/up/src/shared/lines"; echo icon >"$t/up/assets/icon.png"
echo a >"$t/up/app.js"; echo x >"$t/up/other.js"; echo g >"$t/up/gone.js"; echo '["hi"]' >"$t/up/src/shared/lines/en.json"
g "$t/up" add -A; g "$t/up" commit -qm one; g "$t/up" tag v0.1.0
git clone -q "$t/up" "$t/fork"
echo mine >"$t/fork/app.js"; echo '["ola"]' >"$t/fork/src/shared/lines/en.json"; g "$t/fork" rm -q gone.js
g "$t/fork" commit -qam "my changes"
mkdir -p "$t/bin"
# npm: as tests/capri-update.sh's; her tests ("run test") fail when the code has a FAILTESTS file
cat >"$t/bin/npm" <<'EOF'
#!/bin/sh
case $1 in
    ci) [ "$LC_ALL" = C ] || echo "npm ci" >>"$TRANSLATED"
        [ ! -e LOCKMISMATCH ] || { echo "npm error code EUSAGE"; echo "npm error npm ci can only install packages when your package.json and package-lock.json are in sync."; exit 1; }
        [ ! -e NETFAIL ] || { echo "npm error code ECONNRESET"; exit 1; }
        mkdir -p node_modules/.bin node_modules/electron && : >node_modules/electron/install.js &&
        printf '#!/bin/sh\necho v45\n' >node_modules/.bin/electron && chmod +x node_modules/.bin/electron ;;
    run) case $3 in
            build) mkdir -p out/main && : >out/main/index.js ;;
            typecheck) true ;;
            test) [ ! -e FAILTESTS ] ;;
            *) exit 1 ;;
        esac ;;
esac
EOF
printf '#!/bin/sh\nexit 0\n' >"$t/bin/node"
printf '#!/bin/sh\necho "$*" >>%s/notified\n' "$t" >"$t/bin/notify-send"
printf '#!/bin/sh\n[ "$3" = clients ] && echo "[]"; exit 0\n' >"$t/bin/hyprctl"
# git and npm: noted when run in the session's language (a pt_PT one translates the messages capri-update reads)
# shellcheck disable=SC2016  # (expanded by the stand-in)
printf '#!/bin/sh\n[ "$LC_ALL" = C ] || echo "git $*" >>"%s/translated"\nexec %s "$@"\n' "$t" "$(command -v git)" >"$t/bin/git"
chmod +x "$t/bin/"*
h="$t/ho me"
run() { HOME=$h LANG=pt_PT.UTF-8 LC_ALL='' TRANSLATED=$t/translated HYPRLAND_INSTANCE_SIGNATURE='' XDG_DATA_HOME='' XDG_STATE_HOME='' PATH=$t/bin:$PATH CAPRI_FORK=$t/fork \
    CAPRI_UPSTREAM=$t/up "$here/.local/bin/capri-update" "$@" 2>&1; }
app="$h/.local/share/capri"
failed="$h/.local/state/capri-update-failed"

# A release changing a file my fork deleted, and her lines (kept by position: my fork's own): merged, mine kept
echo g2 >"$t/up/gone.js"; echo '["hi", "new"]' >"$t/up/src/shared/lines/en.json"; echo y >"$t/up/other.js"
g "$t/up" commit -qam two; g "$t/up" tag v0.2.0
out=$(run) || fail "the release with the known conflicts not installed: $out"
[[ $(cat "$app/current/other.js") == y && $(cat "$app/current/app.js") == mine && ! -e $app/current/gone.js ]] ||
    fail "v0.2.0 not merged as it should: $out"
[[ $(cat "$app/current/src/shared/lines/en.json") == '["ola"]' ]] || fail "her lines not mine"
grep -q "v0.2.0 installed" <<<"$out" && [[ ! -e $failed ]] || fail "not said as installed: $out"

# A pre-release, then its release: the release (git's version order put v0.3.0-beta after it)
echo beta >"$t/up/other.js"; g "$t/up" commit -qam beta; g "$t/up" tag v0.3.0-beta
echo rel >"$t/up/other.js"; g "$t/up" commit -qam rel; g "$t/up" tag v0.3.0
out=$(run) || fail "v0.3.0: $out"
[[ $(cat "$app/current/other.js") == rel ]] || fail "the pre-release taken over its release: $out"
on030=$(readlink "$app/current")
# A pre-release newer than every release (v1.0.0-beta over v0.3.0): not taken, git's version order notwithstanding
echo b2 >"$t/up/beta.js"; g "$t/up" add -A; g "$t/up" commit -qm beta2; g "$t/up" tag v1.0.0-beta
out=$(run) || fail "with a newer pre-release: $out"
grep -q "up to date (v0.3.0)" <<<"$out" || fail "a pre-release taken over the newest release: $out"
g "$t/up" tag -d v1.0.0-beta >/dev/null

# A release failing her tests: not switched to, said, she stays on the release she's on
touch "$t/up/FAILTESTS"; g "$t/up" add -A; g "$t/up" commit -qm failtests; g "$t/up" tag v0.3.1
out=$(run) && fail "a release failing her tests reported success: $out"
[[ $(readlink "$app/current") == "$on030" ]] || fail "switched to a release failing her tests"
grep -q "build failed on v0.3.1" "$failed" || fail "the failed tests not written down: $(cat "$failed")"
out=$(run) || fail "run again: $out"
grep -q "up to date (v0.3.0); not on v0.3.1" <<<"$out" || fail "the failed release tried again: $out"
g "$t/up" rm -q FAILTESTS; g "$t/up" commit -qm fixed; g "$t/up" tag v0.3.2

# One at a time: a --check while an update runs says nothing and leaves her folder alone; an update waits its turn
lock="$h/.local/state/capri-update.lock"
flock "$lock" sleep 2 & holder=$!
sleep 0.3
start=$SECONDS
out=$(run --check) || fail "--check during an update failed: $out"
[[ -z $out && $((SECONDS - start)) -lt 2 ]] || fail "--check during an update waited or said something: $out"
out=$(run) || fail "an update after another one: $out"
grep -q "waiting for the other" <<<"$out" && grep -q "v0.3.2 installed" <<<"$out" || fail "the update didn't wait its turn: $out"
wait $holder

# Electron's download stalled: given up on (its time limit: 15 min, a second here), she stays on her build, and it's
# tried again next time (not written down as a release that fails)
printf '#!/bin/sh\n[ -e %s/stall ] && exec sleep 30\nexit 0\n' "$t" >"$t/bin/node"
printf '#!/bin/sh\nshift; exec /usr/bin/timeout 1 "$@"\n' >"$t/bin/timeout"
chmod +x "$t/bin/node" "$t/bin/timeout"
on032=$(readlink "$app/current")
echo z >"$t/up/other.js"; g "$t/up" commit -qam three; g "$t/up" tag v0.3.3
touch "$t/stall"
start=$SECONDS
out=$(run) && fail "a stalled download reported success: $out"
((SECONDS - start < 20)) || fail "the stalled download waited on"
[[ $(readlink "$app/current") == "$on032" && ! -e $failed ]] || fail "switched, or the release written down as failing: $out"
rm "$t/stall"
out=$(run) || fail "the download after a stalled one: $out"
grep -q "v0.3.3 installed" <<<"$out" || fail "not tried again after a stalled download: $out"

# A merge whose package.json and lockfile don't match (npm ci refuses it every time): written down as that release's
# own, not tried again and again; she stays on hers
on033=$(readlink "$app/current")
touch "$t/up/LOCKMISMATCH"; g "$t/up" add -A; g "$t/up" commit -qm lock; g "$t/up" tag v0.3.4
out=$(run) && fail "a lockfile that doesn't match reported success: $out"
grep -q "package-lock.json don't match" "$failed" || fail "a lockfile that doesn't match not written down: $(cat "$failed" 2>/dev/null)"
[[ $(readlink "$app/current") == "$on033" ]] || fail "switched with her packages not installed"
out=$(run) || fail "run again: $out"
grep -q "up to date (v0.3.3); not on v0.3.4" <<<"$out" || fail "the lockfile mismatch tried again: $out"
g "$t/up" rm -q LOCKMISMATCH; g "$t/up" commit -qm unlock
# Her packages failing to download the same way three runs in a row: tried again twice, then that release's own
touch "$t/up/NETFAIL"; g "$t/up" add -A; g "$t/up" commit -qm net; g "$t/up" tag v0.3.5
for n in 1 2; do
    out=$(run) && fail "a failed download reported success: $out"
    ! grep -q "didn.t install" "$failed" || fail "a download failing (run $n) written down as the release's: $(cat "$failed")"
done
out=$(run) && fail "a third failed download reported success: $out"
grep -q "3 runs in a row" "$failed" || fail "the third failed download not written down: $(cat "$failed" 2>/dev/null)"
out=$(run) || fail "run again: $out"
grep -q "up to date (v0.3.3); not on v0.3.5" <<<"$out" || fail "a release failing three runs in a row tried again: $out"
g "$t/up" rm -q NETFAIL; g "$t/up" commit -qm unnet
# A release with no history in common with my fork (the original's rewritten): written down, not tried again
g "$t/up" tag v0.3.6 "$(g "$t/up" commit-tree 'HEAD^{tree}' -m rewritten)"
out=$(run) && fail "an unrelated release reported success: $out"
grep -q "no history in common" "$failed" || fail "an unrelated release not written down: $(cat "$failed" 2>/dev/null)"
out=$(run) || fail "run again: $out"
grep -q "up to date (v0.3.3); not on v0.3.6" <<<"$out" || fail "an unrelated release tried again: $out"

# A first install whose newest release doesn't merge with my changes: my fork as it is (with the release it has), the
# release's conflict said; my fork's next change installed too; then said up to date
h="$t/second home"
app="$h/.local/share/capri"
failed="$h/.local/state/capri-update-failed"
echo theirs >"$t/up/app.js"; g "$t/up" commit -qam theirs; g "$t/up" tag v0.4.0
# (my fork with a tag of its own named as that release, on its own code: not taken for the original's, nor said "moved")
g "$t/fork" tag v0.4.0
out=$(run) && fail "a newest release that doesn't merge reported success: $out"
[[ $(cat "$app/current/app.js" 2>/dev/null) == mine && $(cat "$app/current/other.js") == x ]] ||
    fail "my fork not installed with the release it has: $out"
grep -q "conflicts in: app.js" "$failed" && grep -q "Capri not on v0.4.0" "$t/notified" ||
    fail "the newest release's conflict not said: $out"
echo f2 >"$t/fork/fork2.js"; g "$t/fork" add -A; g "$t/fork" commit -qm "another change"
out=$(run) && fail "the newest still not merging reported success: $out"
[[ $(cat "$app/current/fork2.js" 2>/dev/null) == f2 ]] || fail "my fork's change not installed: $out"
out=$(run) || fail "run again: $out"
grep -q "up to date (v0.1.0); not on v0.4.0" <<<"$out" || fail "not said as up to date: $out"
[[ -z $(run --check) ]] || fail "--check offers a release that doesn't merge"
[[ ! -e $t/translated ]] || fail "git or npm ran in the session's language (their messages are read in English): $(head -3 "$t/translated")"
echo "ok capri-update-fallback"
