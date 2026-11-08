#!/usr/bin/env bash
# dotfiles-sync's edges: a stray new file in the repo doesn't stop the sync (or its push), nor does VSCodium failing; an
# unknown argument shows the usage instead of syncing, and no repo says so; "add" refuses a link (not the program it
# points to); LibreWolf's settings aren't refreshed from a profile setup never applied them to (each would be dropped
# as "back to the default")
set -euo pipefail
. "$(dirname "$0")/lib.sh"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_CONFIG_GLOBAL=/dev/null
repo=$t/repo home=$t/home
git init -q --bare -b main "$t/remote.git"
git clone -q "$t/remote.git" "$repo" 2>/dev/null; git -C "$repo" checkout -q -b main 2>/dev/null || true
mkdir -p "$repo/.config/app" "$repo/.local/share/firefox" "$home/.config/app" "$t/bin"
echo same >"$repo/.config/app/conf"; cp "$repo/.config/app/conf" "$home/.config/app/conf"
printf 'user_pref("a.b", true);\nuser_pref("c.d", 1);\n' >"$repo/.local/share/firefox/settings.js"
git -C "$repo" add -A; git -C "$repo" commit -qm one; git -C "$repo" push -q -u origin main
printf '#!/bin/sh\nexit 0\n' >"$t/bin/codium"; chmod +x "$t/bin/codium"
run() { HOME=$home XDG_STATE_HOME=$home/.local/state DOTFILES_DIR=$repo LEGION_CONTROL_DIR=$t/none PATH=$t/bin:$PATH "$here/.local/bin/dotfiles-sync" "$@" 2>&1; }

# A stray file lying in the repo, and a commit an earlier run couldn't push: still pushed, the run ends well
echo notes >"$repo/notes.txt"
echo 2 >"$repo/.config/app/two"; git -C "$repo" add -A .config; git -C "$repo" commit -qm two
out=$(run) || fail "a stray untracked file failed the sync: $out"
[[ -z $(git -C "$repo" log --oneline '@{u}..') ]] || fail "an unpushed commit stayed unpushed next to a stray file: $out"

# VSCodium's extension list failing (a broken install, no display...): the rest of the sync goes on
printf '#!/bin/sh\necho half.listed\nexit 1\n' >"$t/bin/codium"
echo edited >"$home/.config/app/conf"
out=$(run) || fail "VSCodium failing ended the sync: $out"
[[ $out == *pushed:* ]] || fail "VSCodium failing stopped the push: $out"
grep -q half.listed "$repo/.config/VSCodium/extensions.txt" 2>/dev/null && fail "a failed extension list was kept"
printf '#!/bin/sh\nexit 0\n' >"$t/bin/codium"

# An unknown argument (--help, a typo): nothing synced, committed or pushed
head=$(git -C "$repo" rev-parse HEAD)
echo again >"$home/.config/app/conf"
if out=$(run --help); then fail "an unknown argument reported success: $out"; fi
[[ $(git -C "$repo" rev-parse HEAD) == "$head" && $(cat "$repo/.config/app/conf") == edited ]] ||
    fail "an unknown argument synced and committed: $out"

# No repo there (not cloned yet, DOTFILES_DIR wrong): says so, not git's error halfway through
if out=$(DOTFILES_DIR=$t/none HOME=$home PATH=$t/bin:$PATH "$here/.local/bin/dotfiles-sync" 2>&1); then fail "no repo reported success"; fi
[[ $out == "No dotfiles repo at $t/none"* ]] || fail "no repo: $out"
# Where setup ran from, recorded, but that clone gone since: ~/Projects/dotfiles, not "No dotfiles repo"
mkdir -p "$home/.local/state" "$home/Projects"; echo "$t/gone" >"$home/.local/state/dotfiles-repo"; ln -s "$repo" "$home/Projects/dotfiles"
out=$(HOME=$home LEGION_CONTROL_DIR=$t/none PATH=$t/bin:$PATH "$here/.local/bin/dotfiles-sync" -n 2>&1) || fail "a stale recorded repo: $out"
rm -r "$home/.local/state/dotfiles-repo" "$home/Projects"

# "add" of a link: refused, not the program it points to kept under its own path
mkdir -p "$home/.local/bin" "$home/.local/share/prog"; echo program >"$home/.local/share/prog/big"
ln -s "$home/.local/share/prog/big" "$home/.local/bin/tool"
run add "$home/.local/bin/tool" >/dev/null || true
[[ ! -e $repo/.local/share/prog/big ]] || fail "add kept the program a link points to"
[[ -z $(git -C "$repo" ls-files .local/share/prog) ]] || fail "add committed the program a link points to"

# LibreWolf: a profile setup never applied settings.js to (only one of its settings there): settings.js left alone
lw=$home/.config/librewolf/librewolf; mkdir -p "$lw/p.default"
printf '[Install1]\nDefault=p.default\n' >"$lw/profiles.ini"
printf 'user_pref("a.b", true);\n' >"$lw/p.default/prefs.js"
out=$(run -n)
[[ $out != *"changed: LibreWolf settings"* ]] || fail "settings.js refreshed from a profile it was never applied to: $out"
# ...and refreshed from one it was (setup's mark): a setting gone from prefs.js is back to its default, dropped
touch "$lw/p.default/.dotfiles-imported"
out=$(run -n)
[[ $out == *"changed: LibreWolf settings"* ]] || fail "settings.js not refreshed from a profile it was applied to: $out"
# "add" with no file named: the usage, exit 1, nothing synced, committed or pushed
head=$(git -C "$repo" rev-parse HEAD)
echo add-alone >"$home/.config/app/conf"
if out=$(run add); then fail "add with no file reported success: $out"; fi
[[ $out == *"dotfiles-sync add <file>"* && $(git -C "$repo" rev-parse HEAD) == "$head" && $(cat "$repo/.config/app/conf") != add-alone ]] ||
    fail "add with no file synced, or didn't show the usage: $out"
# One at a time: a run while another holds the lock waits for it, then goes on
mkdir -p "$home/.local/state"
flock "$home/.local/state/dotfiles-sync.lock" sleep 1 & holder=$!
sleep 0.3
out=$(run -n) || fail "a run after another failed: $out"
[[ $out == *"Waiting for the other dotfiles-sync"* ]] || fail "a run alongside another didn't wait: $out"
wait $holder
# Something the sync starts and leaves running (git's gc in the background; a stand-in VSCodium here) doesn't keep the
# lock: the next sync doesn't wait on it
printf '#!/bin/sh\n(sleep 3 >/dev/null 2>&1 &)\nexit 0\n' >"$t/bin/codium"
run -n >/dev/null || fail "the sync with a background child failed"
flock -n "$home/.local/state/dotfiles-sync.lock" true || fail "the lock still held after the sync ended (by what it left running)"
printf '#!/bin/sh\nexit 0\n' >"$t/bin/codium"
# The sync itself ending with flock's "busy" status (75; here git add failing with it): that status, once, not taken
# for the lock being busy and the whole sync run again after "Waiting..."
# shellcheck disable=SC2016  # (expanded by the stand-in)
printf '#!/bin/sh\n[ "$3" = add ] && { echo add >>"%s/adds"; exit 75; }\nexec %s "$@"\n' "$t" "$(command -v git)" >"$t/bin/git"
chmod +x "$t/bin/git"
echo new >"$home/.config/app/new"
rc=0; out=$(run add "$home/.config/app/new") || rc=$?
rm "$t/bin/git"
[[ $rc == 75 && $(wc -l <"$t/adds") == 1 && $out != *Waiting* ]] ||
    fail "a sync ending with 75 taken for the lock busy (rc $rc, $(wc -l <"$t/adds") runs): $out"
# Ctrl+C (SIGINT to the whole process group) during the pull, an edit in progress in the repo set aside for it: put
# back as it was before the sync ends, not left in git's stash
git -C "$repo" add -A; git -C "$repo" commit -qm settle; git -C "$repo" push -q
echo "mine, in progress" >"$repo/.config/app/two"
echo "to push" >"$home/.config/app/conf"
# shellcheck disable=SC2016  # (expanded by the stand-in)
printf '#!/bin/sh\n[ "$3" = pull ] && { touch "%s/pulling"; exec sleep 30; }\nexec %s "$@"\n' "$t" "$(command -v git)" >"$t/bin/git"
chmod +x "$t/bin/git"
set -m
run >"$t/int.out" & syncer=$!
set +m
for _ in {1..100}; do [[ -e $t/pulling ]] && break; sleep 0.1; done
[[ -e $t/pulling ]] || fail "test setup: the hanging pull never started: $(cat "$t/int.out")"
kill -INT -- -"$syncer"
rc=0; wait "$syncer" || rc=$?
rm "$t/bin/git"
[[ $(cat "$repo/.config/app/two") == "mine, in progress" && -z $(git -C "$repo" stash list) ]] ||
    fail "an interrupted pull left the edit in progress in git's stash (rc $rc): $(cat "$t/int.out") / $(git -C "$repo" stash list)"
grep -q "put back" "$t/int.out" || fail "the interrupted sync didn't say the edit was put back: $(cat "$t/int.out")"
# One left there all the same (cut off where nothing could put it back): said at every run after
git -C "$repo" stash push -q -m "dotfiles-sync 2026-01-01 10:00:00: your edits in progress"
out=$(run -n) || fail "a dry run with a sync's stash left failed: $out"
[[ $out == *"still in git's stash: git -C $repo stash pop stash@{0}"* ]] || fail "a sync's stash left not said: $out"
git -C "$repo" stash pop -q
echo "ok dotfiles-sync-edge"
