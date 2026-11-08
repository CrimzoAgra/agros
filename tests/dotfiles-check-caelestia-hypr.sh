#!/usr/bin/env bash
# dotfiles-check and Caelestia's own Hyprland config (~/.config/hypr, copied once by `caelestia install`): its repo
# (Caelestia's clone, its state file, as caelestia-cli keeps them) with a newer version of it than the one installed is
# a note (not a problem; notified once, low urgency) pointing to caelestia-hypr-refresh, never caelestia update; up to
# date, or newer only outside hypr/, nothing said. caelestia-hypr-refresh replaces the files not edited, writes .new
# beside edited ones (and links of yours), checks the config on a copy before anything goes live, leaves files turned
# into folders (or back) for you, and counts from the version it refreshed to
set -uo pipefail
. "$(dirname "$0")/lib.sh"
export HOME=$t/home XDG_STATE_HOME=$t/home/.local/state GIT_CONFIG_GLOBAL=/dev/null
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
# (Hyprland's config check and the shells: stand-ins, all fine)
# (Hyprland: a config with BROKEN in a file of ~/.config/hypr has errors, as has one with NEEDS_V2 in a file and no v2
# in variables.lua; $HYPR_SLOW: that file made, then the check takes $HYPR_SLOW_SECS s, 30 unless said)
cat >"$t/Hyprland" <<'H'
#!/bin/sh
[ -z "$HYPR_SLOW" ] || { touch "$HYPR_SLOW"; sleep "${HYPR_SLOW_SECS:-30}"; }
c=${XDG_CONFIG_HOME:-$HOME/.config}/hypr
mkdir -p "${XDG_CACHE_HOME:-$HOME/.cache}"; echo "$HOME" >>"${XDG_CACHE_HOME:-$HOME/.cache}/probe"
if grep -rqs --include='*.lua' BROKEN "$c" || { grep -rqs --include='*.lua' NEEDS_V2 "$c" && ! grep -qs v2 "$c/variables.lua"; }; then printf '======== Config parsing result:\n\nhyprland/keybinds.lua:1: BROKEN\n'; exit 1; fi
printf '======== Config parsing result:\n\nconfig ok\n'
H
printf '#!/bin/sh\nexit 0\n' >"$t/qs"
chmod +x "$t/Hyprland" "$t/qs"
check() { PATH=$t:$PATH "$here/.local/bin/dotfiles-check" 2>&1; }

# Caelestia's repo upstream (a bare one): hypr/ in its first version, installed from it
up=$t/upstream.git work=$t/work dots=$XDG_STATE_HOME/caelestia/dots
git init -q --bare -b main "$up"
git clone -q "$up" "$work" 2>/dev/null
mkdir -p "$work/hypr/hyprland"
echo 'old binds' >"$work/hypr/hyprland/keybinds.lua"; echo 'vars' >"$work/hypr/variables.lua"; echo 'readme' >"$work/README"
git -C "$work" add -A; git -C "$work" commit -qm one; git -C "$work" push -q origin main
git clone -q "$up" "$dots"
applied=$(git -C "$dots" rev-parse HEAD)
mkdir -p "$HOME/.config/hypr/hyprland"
cp "$work/hypr/hyprland/keybinds.lua" "$HOME/.config/hypr/hyprland/"; cp "$work/hypr/variables.lua" "$HOME/.config/hypr/"
cat >"$XDG_STATE_HOME/caelestia/dots-state.json" <<EOF
{"applied_rev": "$applied", "deployed_files": {"$HOME/.config/hypr/hyprland/keybinds.lua": "hypr/hyprland/keybinds.lua",
 "$HOME/.config/hypr/variables.lua": "hypr/variables.lua"}}
EOF

out=$(check)
grep -q "Hyprland config (~/.config/hypr) has an update" <<<"$out" && fail "an up-to-date Caelestia Hyprland config said to have an update: $out"
# Newer upstream outside hypr/ only: nothing said
echo 'readme 2' >"$work/README"; git -C "$work" commit -qam readme; git -C "$work" push -q origin main
out=$(check)
grep -q "has an update" <<<"$out" && fail "an upstream change outside hypr/ said as a Hyprland config update: $out"
# Newer upstream in hypr/ (fetched by the check itself): a note pointing to caelestia-hypr-refresh, never to
# caelestia update (its system update goes past Updates' Qt rebuild); not a problem, and as a notification low
# urgency, once for that version
echo 'new binds' >"$work/hypr/hyprland/keybinds.lua"; echo 'new rules' >"$work/hypr/hyprland/rules.lua"
echo 'new vars' >"$work/hypr/variables.lua"
git -C "$work" add -A; git -C "$work" commit -qm binds; git -C "$work" push -q origin main
echo 'my vars' >"$HOME/.config/hypr/variables.lua"
out=$(check)
grep -q "Hyprland config (~/.config/hypr) has an update: run caelestia-hypr-refresh" <<<"$out" ||
    fail "Caelestia's newer Hyprland config upstream not said: $out"
grep -q "caelestia update" <<<"$out" && fail "caelestia update (a system update past Updates) recommended: $out"
printf '#!/bin/sh\necho "notify $*" >>%s/notified\n' "$t" >"$t/notify-send"; chmod +x "$t/notify-send"
PATH=$t:$PATH "$here/.local/bin/dotfiles-check" --notify >/dev/null 2>&1
PATH=$t:$PATH "$here/.local/bin/dotfiles-check" --notify >/dev/null 2>&1
{ [[ $(grep -c "Hyprland config has an update" "$t/notified") == 1 ]] && grep -q "^notify -u low .*Hyprland config has an update" "$t/notified" &&
    ! grep "^notify -u critical" "$t/notified" | grep -q "Hyprland config"; } ||
    fail "the update not notified once, at low urgency: $(cat "$t/notified")"
# caelestia-hypr-refresh: the unedited file replaced, the new one added, the edited one kept with the new version
# beside it; then the config checked (Hyprland's stand-in: fine); after it, nothing newer
out=$(PATH=$t:$PATH "$here/.local/bin/caelestia-hypr-refresh" 2>&1) || fail "caelestia-hypr-refresh failed: $out"
{ [[ $(cat "$HOME/.config/hypr/hyprland/keybinds.lua") == 'new binds' && $(cat "$HOME/.config/hypr/hyprland/rules.lua") == 'new rules' &&
    $(cat "$HOME/.config/hypr/variables.lua") == 'my vars' && $(cat "$HOME/.config/hypr/variables.lua.new") == 'new vars' ]] &&
    [[ $out == *"config loads"* ]]; } || fail "caelestia-hypr-refresh didn't refresh as it should: $out"
[[ ! -e $HOME/.config/hypr/hyprland/keybinds.lua.new ]] || fail "an unedited file got a .new"
PATH=$t:$PATH "$here/.local/bin/caelestia-hypr-refresh" --check >/dev/null && fail "still newer after the refresh"
out=$(check)
grep -q "has an update" <<<"$out" && fail "the update still said after the refresh: $out"
# The next upstream change: from the refreshed version on (the file it replaced counts as unedited)
echo 'newer binds' >"$work/hypr/hyprland/keybinds.lua"; git -C "$work" commit -qam more; git -C "$work" push -q origin main
PATH=$t:$PATH "$here/.local/bin/caelestia-hypr-refresh" >/dev/null 2>&1
[[ $(cat "$HOME/.config/hypr/hyprland/keybinds.lua") == 'newer binds' && ! -e $HOME/.config/hypr/hyprland/keybinds.lua.new ]] ||
    fail "a file refreshed before taken for an edited one"
refresh() { PATH=$t:$PATH "$here/.local/bin/caelestia-hypr-refresh" "$@" 2>&1; }
push() { git -C "$work" add -A; git -C "$work" commit -qm "$1"; git -C "$work" push -q origin main; }

# A new file in a new folder upstream: added (its folder made), not lost
mkdir -p "$work/hypr/extra"; echo 'extra' >"$work/hypr/extra/more.lua"; push extra
out=$(refresh) || fail "the refresh with a new folder failed: $out"
[[ $(cat "$HOME/.config/hypr/extra/more.lua" 2>/dev/null) == extra ]] || fail "a new file in a new folder not added: $out"

# A file renamed upstream: the new name added, the old one (yours) left and said as no longer in Caelestia
git -C "$work" mv hypr/hyprland/rules.lua hypr/hyprland/windowrules.lua; push rename
out=$(refresh) || fail "the refresh with a rename failed: $out"
{ [[ $(cat "$HOME/.config/hypr/hyprland/windowrules.lua" 2>/dev/null) == 'new rules' && -e $HOME/.config/hypr/hyprland/rules.lua ]] &&
    grep -q "No longer in Caelestia, left as it is: ~/.config/hypr/hyprland/rules.lua" <<<"$out"; } ||
    fail "a renamed file not added, or the old one not said: $out"

# A link of yours in ~/.config/hypr changed upstream: left a link, Caelestia's version beside it as .new
echo 'env' >"$t/my-env.lua"; ln -sf "$t/my-env.lua" "$HOME/.config/hypr/hyprland/env.lua"
mkdir -p "$work/hypr/hyprland"; echo 'new env' >"$work/hypr/hyprland/env.lua"; push env
out=$(refresh) || fail "the refresh with a link of yours failed: $out"
{ [[ -L $HOME/.config/hypr/hyprland/env.lua && $(cat "$t/my-env.lua") == env ]] &&
    [[ $(cat "$HOME/.config/hypr/hyprland/env.lua.new") == 'new env' ]]; } || fail "a link of yours replaced, or no .new beside it: $out"

# A file Caelestia turned into a folder, then a folder into a file: left as they are, said, the rest refreshed
git -C "$work" rm -q hypr/extra/more.lua; mkdir -p "$work/hypr/extra/more.lua"; echo 'x' >"$work/hypr/extra/more.lua/x.lua"
echo 'binds 3' >"$work/hypr/hyprland/keybinds.lua"; push tofolder
out=$(refresh) || fail "the refresh with a file turned into a folder failed: $out"
{ [[ -f $HOME/.config/hypr/extra/more.lua && $(cat "$HOME/.config/hypr/hyprland/keybinds.lua") == 'binds 3' ]] &&
    grep -q "turned into a folder.*~/.config/hypr/extra/more.lua" <<<"$out"; } || fail "a file turned into a folder not left and said: $out"
git -C "$work" rm -rq hypr/extra; echo 'now a file' >"$work/hypr/extra"; push tofile
out=$(refresh) || fail "the refresh with a folder turned into a file failed: $out"
{ [[ -d $HOME/.config/hypr/extra && ! -e $HOME/.config/hypr/extra.new ]] && grep -q "turned into a folder.*~/.config/hypr/extra\b" <<<"$out"; } ||
    fail "a folder turned into a file not left and said: $out"

# A file of yours (edited) that Caelestia's other changes need changed too: the check fails, nothing changes, and its
# new version is written beside it all the same, named, to merge; merged, the refresh goes through
echo 'vars v2' >"$work/hypr/variables.lua"; echo 'NEEDS_V2' >"$work/hypr/hyprland/keybinds.lua"; push v2
if out=$(refresh); then fail "a refresh needing an edited file merged reported success: $out"; fi
{ [[ $(cat "$HOME/.config/hypr/variables.lua.new") == 'vars v2' && $(cat "$HOME/.config/hypr/hyprland/keybinds.lua") == 'binds 3' ]] &&
    [[ $out == *"merged with Caelestia's new versions first (~/.config/hypr/variables.lua.new)"* ]]; } ||
    fail "the edited file's new version not written beside it and named when the check failed: $out"
echo 'my vars v2' >"$HOME/.config/hypr/variables.lua"
out=$(refresh) || fail "the refresh after merging failed: $out"
[[ $(cat "$HOME/.config/hypr/hyprland/keybinds.lua") == NEEDS_V2 ]] || fail "the refresh after merging didn't go through: $out"

# Caelestia's new version doesn't pass the config check: nothing in ~/.config/hypr changed (the file it would replace
# as it was, the one it would add not there), the version not taken as done (still newer), the check's errors said
before=$(cat "$XDG_STATE_HOME/caelestia-hypr-refresh")
echo 'BROKEN binds' >"$work/hypr/hyprland/keybinds.lua"; mkdir -p "$work/hypr/more"; echo 'x' >"$work/hypr/more/new.lua"; push broken
if out=$(refresh); then fail "a refresh that didn't pass the config check reported success: $out"; fi
{ [[ $(cat "$HOME/.config/hypr/hyprland/keybinds.lua") == NEEDS_V2 && ! -e $HOME/.config/hypr/more ]] &&
    [[ $(cat "$XDG_STATE_HOME/caelestia-hypr-refresh") == "$before" ]] &&
    [[ $out == *"didn't pass the check"*"BROKEN"* ]]; } ||
    fail "a refresh that failed the config check not put back, or not said: $out"
refresh --check >/dev/null || fail "after a refresh put back, no longer said to have an update"
[[ ! -e $XDG_STATE_HOME/hypr-config-check ]] || fail "the check's errors left on record for the config put back: $(cat "$XDG_STATE_HOME/hypr-config-check")"

# Stopped during the check (a closed terminal's SIGHUP, or SIGTERM, to the whole group): ~/.config/hypr as it was,
# nothing half done, and its staging folder gone; one an earlier kill left, taken away at the next run
export TMPDIR=$t/tmpd
# (a runtime folder there already: else the check makes one of its own in TMPDIR)
[[ -d ${XDG_RUNTIME_DIR:-} ]] || { export XDG_RUNTIME_DIR=$t/run; mkdir -p -m 700 "$t/run"; }
mkdir -p "$TMPDIR/caelestia-hypr-refresh.old"; touch -d '1 hour ago' "$TMPDIR/caelestia-hypr-refresh.old"
for sig in HUP TERM; do
    rm -f "$t/slow"
    set -m
    HYPR_SLOW=$t/slow PATH=$t:$PATH "$here/.local/bin/caelestia-hypr-refresh" >/dev/null 2>&1 & refresher=$!
    set +m
    for _ in {1..100}; do [[ -e $t/slow ]] && break; sleep 0.1; done
    [[ -e $t/slow ]] || fail "test setup: the slow check never started"
    sleep 0.5
    kill -"$sig" -- -"$refresher" 2>/dev/null; wait "$refresher" 2>/dev/null
    { [[ $(cat "$HOME/.config/hypr/hyprland/keybinds.lua") == NEEDS_V2 && ! -e $HOME/.config/hypr/more ]] &&
        [[ -z $(find "$HOME/.config/hypr" -name '*.refresh*') ]]; } || fail "a refresh stopped ($sig) during its check changed ~/.config/hypr"
    [[ -z $(ls -A "$TMPDIR") ]] || fail "a refresh stopped ($sig) left its staging folder (or an old one stayed): $(ls -A "$TMPDIR")"
done

# Two at once: the second, while the first is still running (here stopped, as by Ctrl+Z or the laptop asleep), says
# so and ends, its staging folder left alone; the first, let go on, ends as it would have
rm -f "$t/slow"
set -m
HYPR_SLOW=$t/slow HYPR_SLOW_SECS=3 PATH=$t:$PATH "$here/.local/bin/caelestia-hypr-refresh" >"$t/first.out" 2>&1 & first=$!
set +m
for _ in {1..100}; do [[ -e $t/slow ]] && break; sleep 0.1; done
[[ -e $t/slow ]] || fail "test setup: the first run's slow check never started"
kill -STOP -- -"$first"
rc=0; out=$(refresh) || rc=$?
staged=$(ls -A "$TMPDIR")
kill -CONT -- -"$first"; wait "$first" 2>/dev/null
{ [[ $rc == 2 && $out == *"Another caelestia-hypr-refresh is running"* && $staged == caelestia-hypr-refresh.* ]] &&
    grep -q "didn't pass the check" "$t/first.out"; } ||
    fail "a second run alongside a stopped one didn't just say so, or swept its folder (rc $rc): $out / $staged / $(cat "$t/first.out")"
[[ -z $(ls -A "$TMPDIR") ]] || fail "the first run's staging folder left: $(ls -A "$TMPDIR")"

# Caelestia's upstream fixed again; the checks on the copy keep their caches to themselves (the keymap scroll-lock
# makes there named a path in the staging folder), the live one checked after it's gone
echo 'binds 4' >"$work/hypr/hyprland/keybinds.lua"; git -C "$work" rm -rq hypr/more; push fixed
rm -f "$HOME/.cache/probe"
out=$(refresh) || fail "the refresh after the fix failed: $out"
{ [[ $(cat "$HOME/.config/hypr/hyprland/keybinds.lua") == 'binds 4' ]] && ! grep -q caelestia-hypr-refresh "$HOME/.cache/probe" &&
    [[ -z $(ls -A "$TMPDIR") ]]; } || fail "the staged check wrote into your cache, or the refresh didn't go through: $out / $(cat "$HOME/.cache/probe")"

# A folder of yours inside it that's a link (as stow makes), then all of ~/.config/hypr a link: what's under a link
# not changed (Caelestia's version not written into the folder it leads to), said; the rest refreshed, and the
# staging copy never writing through a link either
mkdir -p "$t/stow"; mv "$HOME/.config/hypr/hyprland" "$t/stow/hyprland"; ln -s "$t/stow/hyprland" "$HOME/.config/hypr/hyprland"
echo 'BROKEN general' >"$work/hypr/hyprland/general.lua"; echo 'vars v3' >"$work/hypr/variables.lua"; mkdir -p "$work/hypr/more"
echo 'more' >"$work/hypr/more/a.lua"; push linked
before=$(find "$t/stow" -type f -exec sha256sum {} + | sort)
out=$(refresh) || fail "the refresh with a linked folder failed: $out"
{ [[ $(find "$t/stow" -type f -exec sha256sum {} + | sort) == "$before" && $(cat "$HOME/.config/hypr/more/a.lua") == more ]] &&
    grep -q "In a linked folder of yours, not changed.*~/.config/hypr/hyprland/general.lua" <<<"$out"; } ||
    fail "a file in a linked folder changed, or not said: $out"
rm "$HOME/.config/hypr/hyprland"; mv "$t/stow/hyprland" "$HOME/.config/hypr/hyprland"
mv "$HOME/.config/hypr" "$t/stow/hypr"; ln -s "$t/stow/hypr" "$HOME/.config/hypr"
echo 'more 2' >"$work/hypr/more/a.lua"; push linked2
before=$(find "$t/stow" -type f -exec sha256sum {} + | sort)
out=$(refresh) || fail "the refresh with ~/.config/hypr a link failed: $out"
{ [[ $(find "$t/stow" -type f -exec sha256sum {} + | sort) == "$before" ]] && grep -q "In a linked folder of yours.*more/a.lua" <<<"$out"; } ||
    fail "a linked ~/.config/hypr changed, or not said: $out"
rm "$HOME/.config/hypr"; mv "$t/stow/hypr" "$HOME/.config/hypr"

# Its files where XDG_CONFIG_HOME says (Caelestia's record names them there): refreshed there, not in a stale
# ~/.config/hypr. Its record naming none of the changed files where this looks: said, the version not taken as done
mkdir -p "$t/xdg"; cp -a "$HOME/.config/hypr" "$t/xdg/hypr"
jq --arg h "$HOME/.config/hypr/" --arg x "$t/xdg/hypr/" '.deployed_files |= with_entries(.key |= sub("^" + $h; $x))' \
    "$XDG_STATE_HOME/caelestia/dots-state.json" >"$t/s.json" && mv "$t/s.json" "$XDG_STATE_HOME/caelestia/dots-state.json"
echo 'binds 5' >"$work/hypr/hyprland/keybinds.lua"; push xdg
out=$(XDG_CONFIG_HOME=$t/xdg refresh) || fail "the refresh into XDG_CONFIG_HOME failed: $out"
[[ $(cat "$t/xdg/hypr/hyprland/keybinds.lua") == 'binds 5' && $(cat "$HOME/.config/hypr/hyprland/keybinds.lua") == 'binds 4' ]] ||
    fail "not refreshed where XDG_CONFIG_HOME says: $out"
before=$(cat "$XDG_STATE_HOME/caelestia-hypr-refresh")
echo 'binds 6' >"$work/hypr/hyprland/keybinds.lua"; push elsewhere
rc=0; out=$(refresh) || rc=$?
[[ $rc == 2 && $out == *"None of Caelestia's changed files are in"* && $(cat "$XDG_STATE_HOME/caelestia-hypr-refresh") == "$before" ]] ||
    fail "a refresh with none of the files where it looks took the version as done (rc $rc): $out"
unset TMPDIR

# The version Caelestia installed unknown to its clone (upstream rewrote its history), none refreshed to: said,
# nothing done; --check says so too (on stderr), not an update
rm -f "$XDG_STATE_HOME/caelestia-hypr-refresh"
jq '.applied_rev = "0123456789abcdef0123456789abcdef01234567"' "$XDG_STATE_HOME/caelestia/dots-state.json" >"$t/s.json" &&
    mv "$t/s.json" "$XDG_STATE_HOME/caelestia/dots-state.json"
rc=0; out=$(refresh) || rc=$?
[[ $rc == 2 && $out == *"isn't in its clone"* && ! -e $XDG_STATE_HOME/caelestia-hypr-refresh ]] ||
    fail "an unknown installed version not said (rc $rc): $out"
rc=0; out=$(PATH=$t:$PATH "$here/.local/bin/caelestia-hypr-refresh" --check 2>"$t/err") || rc=$?
[[ $rc == 2 && -z $out && $(cat "$t/err") == *"isn't in its clone"* ]] || fail "--check claimed an update from an unknown version (rc $rc): $out"
echo "ok dotfiles-check-caelestia-hypr"
