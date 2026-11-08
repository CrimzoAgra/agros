#!/usr/bin/env bash
# dotfiles-sync -n (shows, changes nothing): a file you changed is synced, one the repo got newer (pulled, not yet
# copied home) is skipped instead of copied back over
set -euo pipefail
. "$(dirname "$0")/lib.sh"
repo=$t/repo home=$t/home
mkdir -p "$repo/.config/app" "$home/.config/app" "$t/bin"
printf '#!/bin/sh\nexit 0\n' >"$t/bin/codium"; chmod +x "$t/bin/codium"   # no editor extensions to list
echo old >"$repo/.config/app/mine"; echo old >"$repo/.config/app/pulled"
# The repo's wrapper, a link at home (Claude Code's installer's): not the program it points to copied over the wrapper
mkdir -p "$repo/.local/bin" "$home/.local/bin" "$repo/.config/VSCodium"
echo wrapper >"$repo/.local/bin/claude"; echo program >"$t/claude-program"; ln -s "$t/claude-program" "$home/.local/bin/claude"
# An extension list, and none installed here (codium lists nothing): the repo's kept
echo some.extension >"$repo/.config/VSCodium/extensions.txt"
git -C "$repo" init -q && git -C "$repo" add -A && git -C "$repo" -c user.name=t -c user.email=t@t commit -qm one --date=@1000000000
echo edited >"$home/.config/app/mine"                                 # changed at home now
echo stale >"$home/.config/app/pulled"; touch -d @1000000000 "$home/.config/app/pulled"
# Pulled later, though committed (elsewhere) before your file last changed: what counts is when it arrived here
echo new >"$repo/.config/app/pulled"; touch -d @1000000000 "$home/.config/app/pulled"
GIT_COMMITTER_DATE=@999999999 git -C "$repo" -c user.name=t -c user.email=t@t commit -qam two --date=@999999999
out=$(HOME=$home DOTFILES_DIR=$repo LEGION_CONTROL_DIR=$t/none PATH=$t/bin:$PATH "$here/.local/bin/dotfiles-sync" -n 2>&1)
grep -q "changed: .config/app/mine" <<<"$out" || fail "your change not synced: $out"
grep -q "skipped: .config/app/pulled" <<<"$out" || fail "a newer repo file would be overwritten: $out"
[[ $(cat "$repo/.config/app/pulled") == new && $(cat "$repo/.config/app/mine") == old ]] || fail "-n changed the repo"
grep -q "\.local/bin/claude" <<<"$out" && fail "a link at home synced over the repo's file: $out"
grep -q "VSCodium extensions" <<<"$out" && fail "an empty extension list would replace the repo's: $out"
echo "ok dotfiles-sync"
