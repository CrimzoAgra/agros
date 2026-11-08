#!/usr/bin/env bash
# dotfiles-sync's push: the other machine's commits pulled in first, and a commit an earlier run couldn't push is
# pushed by the next run (it said "nothing to commit" and left it); a rebase or a conflicted merge left open by hand
# gets nothing committed on top
set -euo pipefail
. "$(dirname "$0")/lib.sh"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_CONFIG_GLOBAL=/dev/null
git init -q --bare -b main "$t/remote.git"
git clone -q "$t/remote.git" "$t/a" 2>/dev/null; git clone -q "$t/remote.git" "$t/b" 2>/dev/null
for r in a b; do git -C "$t/$r" checkout -q -b main 2>/dev/null || true; done
echo 1 >"$t/a/one"; echo 3 >"$t/a/three"; git -C "$t/a" add -A; git -C "$t/a" commit -qm one; git -C "$t/a" push -q -u origin main
git -C "$t/b" pull -q origin main; git -C "$t/b" branch -q -u origin/main
source <(sed -n '/^shared() {/,/^# push <repo>/p; /^push() {/,/^}/p' "$here/.local/bin/dotfiles-sync")
# (the files made here, as the bookmarks: "--", committed as they are)
# The other machine pushed meanwhile; this one has a change to sync
echo 2 >"$t/a/two"; git -C "$t/a" add -A; git -C "$t/a" commit -qm two; git -C "$t/a" push -q
echo 3b >"$t/b/three"  # (a tracked file: a new one is kept with "dotfiles-sync add", not by lying in the folder)
push "$t/b" "" -- three >/dev/null
[[ -z $(git -C "$t/b" log --oneline '@{u}..') ]] || fail "the commit wasn't pushed after pulling the other machine's"
[[ -e $t/b/two ]] || fail "the other machine's commit wasn't pulled in"
# A commit left unpushed (an earlier run's push refused): nothing new to commit, still pushed
echo 4 >"$t/b/four"; git -C "$t/b" add -A; git -C "$t/b" commit -qm four
out=$(push "$t/b" "" 2>/dev/null)
[[ $out != *"nothing to commit"* ]] || fail "an unpushed commit was reported as nothing to commit"
[[ -z $(git -C "$t/b" log --oneline '@{u}..') ]] || fail "an unpushed commit stayed unpushed"
# Only the files the sync copied are committed: an edit in progress elsewhere in the repo is left out (and kept as it
# is), the other machine's commits pulled in under it all the same
git -C "$t/a" pull -q; echo 5 >"$t/a/five"; git -C "$t/a" add -A; git -C "$t/a" commit -qm five; git -C "$t/a" push -q
echo 3c >"$t/b/three"; echo wip >"$t/b/one"
out=$(push "$t/b" "" -- three 2>&1) || fail "the sync with an edit in progress: $out"
[[ $(git -C "$t/b" show HEAD:three) == 3c ]] || fail "the synced file not committed: $out"
[[ $(git -C "$t/b" show HEAD:one) == 1 ]] || fail "an edit in progress committed as the sync"
[[ $(cat "$t/b/one") == wip && -e $t/b/five ]] || fail "the edit in progress lost, or the other machine's not pulled: $out"
[[ $out == *"left out"*one* && -z $(git -C "$t/b" log --oneline '@{u}..') ]] || fail "the edit left out not said, or not pushed: $out"
git -C "$t/b" checkout -q -- one
# An edit in progress that clashes with what the pull brings: not left half-applied with conflict marks (every later
# sync would refuse), but kept whole in git's stash, the folder as pulled, and the sync said as failed
git -C "$t/a" pull -q; echo a2 >"$t/a/one"; git -C "$t/a" commit -qam a2; git -C "$t/a" push -q
echo 3d >"$t/b/three"; echo mine >"$t/b/one"
unpushed=
push "$t/b" "" -- three >"$t/out" 2>&1; out=$(cat "$t/out")  # (not in a subshell: it sets unpushed)
[[ -n $unpushed && $out == *"clash with what was pulled"* ]] || fail "a clashing edit in progress not said as failed: $out"
[[ -z $(git -C "$t/b" ls-files -u) && -z $(git -C "$t/b" status --porcelain --untracked-files=no) ]] ||
    fail "a clashing edit in progress left the folder half-merged: $(git -C "$t/b" status --porcelain)"
[[ $(cat "$t/b/one") == a2 && $(git -C "$t/b" show HEAD:three) == 3d && -z $(git -C "$t/b" log --oneline '@{u}..') ]] ||
    fail "the sync itself not pulled and pushed: $out"
git -C "$t/b" stash show -p | grep -q '^+mine' || fail "the edit in progress not kept in the stash"
[[ $(push "$t/b" "" -- three 2>&1) == *"nothing to commit"* ]] || fail "the next sync refused after a clashing edit"
git -C "$t/b" stash drop -q
# The commit failing (no name and email set yet, a hook): said, failed, nothing pushed or set aside as an edit in
# progress (it went on, stashed the sync's own copies and said "pushed")
printf '#!/bin/sh\nexit 1\n' >"$t/b/.git/hooks/pre-commit"; chmod +x "$t/b/.git/hooks/pre-commit"
echo 3e >"$t/b/three"; head=$(git -C "$t/b" rev-parse HEAD); stashes=$(git -C "$t/b" stash list | wc -l)
unpushed=
push "$t/b" "" -- three >"$t/out" 2>&1; out=$(cat "$t/out")
{ [[ -n $unpushed && $out == *"NOT synced"* && $out != *pushed:* ]] && [[ $(git -C "$t/b" rev-parse HEAD) == "$head" ]] &&
    [[ $(git -C "$t/b" stash list | wc -l) == "$stashes" && $(cat "$t/b/three") == 3e ]]; } ||
    fail "a failed commit not said as failed, or its copies set aside: $out"
rm "$t/b/.git/hooks/pre-commit"; git -C "$t/b" checkout -q -- three
# The whole script: a file an earlier run copied but couldn't commit (it stopped: a rebase open, a failed commit) is
# committed by the next run, though it's no longer a change from home; a repo copy edited there (newer than yours at
# home: the run says it's skipped) isn't committed or pushed, nor an edit outside what it syncs; what was staged of
# them is staged again after the pull, and an older stash of yours is left alone
mkdir -p "$t/b/.config/app" "$t/h/.config/app" "$t/bin"
echo 1 >"$t/b/.config/app/x"; echo y1 >"$t/b/.config/app/y"; echo z1 >"$t/b/.config/app/z"; git -C "$t/b" add -A; git -C "$t/b" commit -qm x; git -C "$t/b" push -q
echo older >"$t/b/one"; git -C "$t/b" stash push -q -m "an older stash of yours"
echo 2 >"$t/h/.config/app/x"; echo 2 >"$t/b/.config/app/x"
echo y-home >"$t/h/.config/app/y"; touch -d '1 hour ago' "$t/h/.config/app/y"; echo y-editing >"$t/b/.config/app/y"
# (and one edited in the repo, not committed, older than yours at home, which the app rewrote since: not copied over)
echo z-editing >"$t/b/.config/app/z"; touch -d '1 hour ago' "$t/b/.config/app/z"; echo z-home >"$t/h/.config/app/z"
echo wip2 >"$t/b/one"; git -C "$t/b" add one; echo 6 >"$t/b/five"
git -C "$t/a" pull -q; echo 7 >"$t/a/seven"; git -C "$t/a" add -A; git -C "$t/a" commit -qm seven; git -C "$t/a" push -q
printf '#!/bin/sh\nexit 0\n' >"$t/bin/codium"; chmod +x "$t/bin/codium"
out=$(HOME=$t/h DOTFILES_DIR=$t/b LEGION_CONTROL_DIR=$t/none PATH=$t/bin:$PATH "$here/.local/bin/dotfiles-sync" 2>&1) ||
    fail "the sync failed: $out"
[[ $(git -C "$t/b" show HEAD:.config/app/x) == 2 && -z $(git -C "$t/b" log --oneline '@{u}..') && -e $t/b/seven ]] ||
    fail "a file copied by an earlier run not committed and pushed: $out"
[[ $out == *"skipped: .config/app/y"* && $(git -C "$t/b" show HEAD:.config/app/y) == y1 && $(cat "$t/b/.config/app/y") == y-editing ]] ||
    fail "a repo copy edited there (newer than home's) committed, or lost: $out"
[[ $out == *"skipped: .config/app/z (the repo's copy has changes not committed"* && $(cat "$t/b/.config/app/z") == z-editing && $(git -C "$t/b" show HEAD:.config/app/z) == z1 ]] ||
    fail "an edit not committed in the repo copied over (yours newer), or committed: $out"
[[ $(git -C "$t/b" show HEAD:one) == a2 && $(cat "$t/b/one") == wip2 && $(cat "$t/b/five") == 6 ]] ||
    fail "an edit outside the sync committed, or lost: $out"
[[ $(git -C "$t/b" diff --cached --name-only) == one && $(git -C "$t/b" diff --name-only) == $'.config/app/y\n.config/app/z\nfive' ]] ||
    fail "what was staged not staged again: staged $(git -C "$t/b" diff --cached --name-only), not $(git -C "$t/b" diff --name-only)"
[[ $(git -C "$t/b" stash list) == *"an older stash of yours"* && $(git -C "$t/b" stash list | wc -l) == 1 ]] ||
    fail "an older stash popped, or the sync's own left: $(git -C "$t/b" stash list)"
git -C "$t/b" stash drop -q; git -C "$t/b" reset -q --hard
# A copy the sync made but couldn't commit (a rebase open in the repo that run), then a newer change at home: the
# sync's own copy (as it noted it) is copied over and committed, not taken for an edit in progress and skipped for good
echo w1 >"$t/b/.config/app/w"; git -C "$t/b" add -A; git -C "$t/b" commit -qm w; git -C "$t/b" push -q
echo w2 >"$t/h/.config/app/w"
rb=$(git -C "$t/b" rev-parse --path-format=absolute --git-path rebase-merge); mkdir "$rb"
out=$(HOME=$t/h DOTFILES_DIR=$t/b LEGION_CONTROL_DIR=$t/none PATH=$t/bin:$PATH "$here/.local/bin/dotfiles-sync" 2>&1) || true
[[ $out == *"rebase is in progress"* && $(cat "$t/b/.config/app/w") == w2 ]] || fail "test setup: the stopped run: $out"
rmdir "$rb"
echo w3 >"$t/h/.config/app/w"
out=$(HOME=$t/h DOTFILES_DIR=$t/b LEGION_CONTROL_DIR=$t/none PATH=$t/bin:$PATH "$here/.local/bin/dotfiles-sync" 2>&1) ||
    fail "the sync after a stopped one failed: $out"
[[ $(git -C "$t/b" show HEAD:.config/app/w) == w3 && -z $(git -C "$t/b" log --oneline '@{u}..') ]] ||
    fail "the sync's own uncommitted copy taken for an edit in progress: $out"
! grep -q ' \.config/app/w$' "$(git -C "$t/b" rev-parse --path-format=absolute --git-path dotfiles-sync-written)" 2>/dev/null ||
    fail "a committed copy still noted as the sync's pending one"
# What was staged no longer going back staged (stash apply --index failing): the edits back as plain changes, said,
# the sync's stash dropped
echo 3e >"$t/b/three"; echo wip3 >"$t/b/one"; git -C "$t/b" add one
# shellcheck disable=SC2329  # (called by push, sourced above)
git() { [[ " $* " == *" stash apply -q --index "* ]] && return 1; command git "$@"; }
out=$(push "$t/b" "" -- three 2>&1)
unset -f git
[[ $out == *"unstaged now"* && $(cat "$t/b/one") == wip3 && -z $(git -C "$t/b" diff --cached --name-only) &&
    -z $(git -C "$t/b" stash list) && $(git -C "$t/b" show HEAD:three) == 3e ]] ||
    fail "apply --index failing: the edits not back unstaged, not said, or the stash left: $out / $(git -C "$t/b" stash list)"
git -C "$t/b" checkout -q -- one
# Another stash made on top of the sync's meanwhile: none taken back (the sync's isn't the newest any more), said as failed
echo 3f >"$t/b/three"; echo wip4 >"$t/b/one"
# shellcheck disable=SC2329  # (called by push, sourced above)
git() {
    command git "$@"
    local rc=$?
    [[ " $* " != *" pull --rebase "* ]] || { echo other >>"$t/b/five"; command git -C "$t/b" stash push -q -m "another stash"; }
    return "$rc"
}
unpushed=
push "$t/b" "" -- three >"$t/out" 2>&1; out=$(cat "$t/out")
unset -f git
[[ -n $unpushed && $out == *"not on top of it any more"* && $(git -C "$t/b" stash list | wc -l) == 2 && $(cat "$t/b/one") == "$(git -C "$t/b" show HEAD:one)" ]] ||
    fail "a stash on top of the sync's: one taken back, or not said: $out / $(git -C "$t/b" stash list)"
git -C "$t/b" stash clear
# Both machines changed the same file: the rebase is undone (no conflict marks, no half-done rebase), the commit stays
git -C "$t/a" pull -q; echo a >"$t/a/one"; git -C "$t/a" commit -qam a; git -C "$t/a" push -q
echo b >"$t/b/one"
unpushed=
push "$t/b" "" -- one >/dev/null 2>&1 || true
[[ -n ${unpushed:-} ]] || fail "a conflicting sync wasn't reported as not pushed"
[[ ! -d $t/b/.git/rebase-merge && ! -d $t/b/.git/rebase-apply ]] || fail "a conflicting sync left a rebase open"
grep -q '<<<<<<<' "$t/b/one" && fail "a conflicting sync left conflict marks"
[[ $(cat "$t/b/one") == b ]] || fail "a conflicting sync lost this machine's change"
out=$(push "$t/b" "" 2>/dev/null)
[[ $out == *"NOT pushed"* ]] || fail "the next run didn't say it's still not pushed: $out"
# A rebase left open by hand, synced from another folder: left alone (nothing committed on top, not aborted)
git -C "$t/b" pull -q --rebase >/dev/null 2>&1 || true
[[ -d $t/b/.git/rebase-merge || -d $t/b/.git/rebase-apply ]] || fail "test setup: no rebase open"
head=$(git -C "$t/b" rev-parse HEAD)
out=$(cd / && push "$t/b" "" 2>/dev/null)
[[ $out == *"rebase is in progress"* ]] || fail "an open rebase wasn't seen from another folder: $out"
[[ $(git -C "$t/b" rev-parse HEAD) == "$head" ]] || fail "something was committed on top of an open rebase"
# A merge with conflicts left by a pull by hand: nothing committed (add -u would commit the conflict marks)
git -C "$t/b" rebase --abort
git -C "$t/b" pull -q --no-rebase >/dev/null 2>&1 || true
[[ -n $(git -C "$t/b" ls-files -u) ]] || fail "test setup: no merge conflict"
head=$(git -C "$t/b" rev-parse HEAD)
out=$(push "$t/b" "" 2>/dev/null)
[[ $out == *"merge is in progress"* ]] || fail "a merge with conflicts wasn't seen: $out"
[[ $(git -C "$t/b" rev-parse HEAD) == "$head" ]] || fail "a merge's conflict marks were committed"
echo "ok dotfiles-sync-push"
