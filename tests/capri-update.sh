#!/usr/bin/env bash
# capri-update with stand-in repos (a fork and an original with v* releases) and a stand-in npm: installs her, merges a
# new release, keeps her build when a release conflicts with the fork, doesn't build or fails its check (and doesn't
# retry it), --check; her folder from the old Capri (another original) cloned again
set -uo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
fail() { echo "FAIL: $*"; exit 1; }
g() { git -C "$1" -c user.name=t -c user.email=t@t "${@:2}"; }

# The original: a release; the fork: that plus a change of its own
git init -q -b main "$t/up"
mkdir -p "$t/up/assets" "$t/up/src"; echo icon >"$t/up/assets/icon.png"; echo 'a' >"$t/up/app.js"; echo 'x' >"$t/up/other.js"
g "$t/up" add -A; g "$t/up" commit -qm one; g "$t/up" tag v0.1.0
git clone -q "$t/up" "$t/fork"
echo 'mine' >"$t/fork/app.js"; g "$t/fork" commit -qam "my change"
# npm: "ci" makes her Electron, "run build" her out/ (none when the code has a NOBUILD file), "run typecheck" her check
# (fails when it has a FAILTEST file); node: Electron's download
mkdir -p "$t/bin"
cat >"$t/bin/npm" <<'EOF'
#!/bin/sh
case $1 in
    ci) [ ! -e "$NPMFAIL.mark" ] || mkdir .capri-build
        [ ! -e "$NPMFAIL" ] && mkdir -p node_modules/.bin node_modules/electron && : >node_modules/electron/install.js && printf '#!/bin/sh\necho v45\n' >node_modules/.bin/electron && chmod +x node_modules/.bin/electron ;;
    run) case $3 in
            build) [ -e NOBUILD ] || { mkdir -p out/main && : >out/main/index.js; } ;;
            typecheck) [ ! -e FAILTEST ] ;;
            test) [ ! -e FAILTESTS ] ;;
            *) exit 1 ;;
        esac ;;
esac
EOF
printf '#!/bin/sh\nexit 0\n' >"$t/bin/node"
printf '#!/bin/sh\nexit 0\n' >"$t/bin/notify-send"
# hyprctl: notes each call but the window list (a config reload binds her key once she's installed; not the real
# desktop's), and a game open then (a reload takes it out of fullscreen); sleep (after-games' wait): the game closes
# (and the update's lock, if the reload's wait for a game held it: every capri-update kept waiting through the game)
sed "s|T|$t|g" >"$t/bin/hyprctl" <<'EOF'
#!/bin/sh
[ ! -e /proc/$$/fd/9 ] || echo "lock held by $*" >>T/hyprctl
if [ "$3" = clients ]; then [ -e T/game ] && echo '[{"tags":["game"],"title":"g"}]' || echo '[]'
elif [ -e T/game ]; then echo "$* with a game open" >>T/hyprctl
else echo "$*" >>T/hyprctl; fi
EOF
printf '#!/bin/sh\nrm -f %s/game\n' "$t" >"$t/bin/sleep"
# git: notes when it could ask for a GitHub login in the terminal (the private fork with none: setup --yes waited on it)
printf '#!/bin/sh\n[ "$GIT_TERMINAL_PROMPT" = 0 ] || echo "$*" >>"%s/prompts"\nexec %s "$@"\n' "$t" "$(command -v git)" >"$t/bin/git"
chmod +x "$t/bin/"*
fork=$t/fork
run() { HOME="$t/ho|me" HYPRLAND_INSTANCE_SIGNATURE= XDG_DATA_HOME= XDG_STATE_HOME= CLAUDE_CONFIG_DIR= CODEX_HOME= AGY_CONFIG_DIR= PATH=$t/bin:$PATH CAPRI_FORK=$fork CAPRI_UPSTREAM=$t/up \
    NPMFAIL=$t/npmfail "$here/.local/bin/capri-update" "$@" 2>&1; }
cur() { readlink "$t/ho|me/.local/share/capri/current"; }
app="$t/ho|me/.local/share/capri"

out=$(run --check) || fail "--check before install: $out"
[[ -z $out && ! -e $app ]] || fail "--check installed something: $out"
# Her packages not downloaded (network, disk full): not installed, and tried again next time
touch "$t/npmfail"
out=$(run) && fail "an install whose packages failed reported success"
[[ ! -e $app/current ]] || fail "installed without her packages"
[[ ! -e $t/hyprctl ]] || fail "the config reloaded with her not installed"
rm "$t/npmfail"
touch "$t/game"
out=$(run) || fail "install failed: $out"
for _ in {1..50}; do [[ -s $t/hyprctl ]] && break; sleep 0.1; done  # (in the background, after any game)
[[ $(cat "$t/hyprctl" 2>/dev/null) == "-i 0 reload" ]] ||  # (Hyprland named: run from outside it, an SSH login)
    fail "her first install didn't load the config again after the game: $(cat "$t/hyprctl" 2>/dev/null)"
[[ $(cat "$app/current/app.js") == mine ]] || fail "not the fork's code"
[[ -x $app/current/node_modules/.bin/electron ]] || fail "no Electron"
[[ -f $app/current/out/main/index.js ]] || fail "not built"
grep -q "^Exec=$t/ho|me/.local/bin/capri$" "$t/ho|me/.local/share/applications/capri.desktop" || fail "no launcher entry"
[[ -f "$t/ho|me/.local/share/icons/hicolor/256x256/apps/capri.png" ]] || fail "no icon"
out=$(run) || fail "second run: $out"
grep -q "up to date (v0.1.0)" <<<"$out" || fail "not up to date: $out"
first=$(cur)
# The fork from elsewhere for one run (a copy of it: $CAPRI_FORK), then from its own address again
git clone -q --bare "$t/fork" "$t/fork-copy.git"
fork=$t/fork-copy.git
out=$(run --check) || fail "--check from a copy of the fork: $out"
[[ $(git -C "$app/src" remote get-url origin) == "$t/fork-copy.git" ]] || fail "the fork's copy not fetched from"
fork=$t/fork
out=$(run --check) || fail "--check: $out"
[[ $(git -C "$app/src" remote get-url origin) == "$t/fork" ]] || fail "the fork's address not set back"

# A release that merges: built, switched to, the build before kept
echo 'y' >"$t/up/other.js"; g "$t/up" commit -qam two; g "$t/up" tag v0.2.0
grep -q "update available (v0.2.0)" <<<"$(run --check)" || fail "--check missed v0.2.0"
# (after a run cut off mid-merge: its half-done merge is dropped, not taken for a conflict)
g "$app/src" fetch -q --tags upstream; g "$app/src" merge -q --no-commit --no-ff v0.2.0 >/dev/null
out=$(run) || fail "v0.2.0: $out"
[[ $(cat "$app/current/other.js") == y && $(cat "$app/current/app.js") == mine ]] || fail "v0.2.0 not merged with the fork"
second=$(cur)
[[ $second != "$first" && -d $app/$first ]] || fail "the build before wasn't kept"

# A release that conflicts with the fork: she stays, it's written down, not tried again
echo 'theirs' >"$t/up/app.js"; g "$t/up" commit -qam three; g "$t/up" tag v0.3.0
out=$(run) && fail "a conflicting release reported success"
[[ $(cur) == "$second" ]] || fail "switched to a conflicting release"
grep -q "app.js" "$t/ho|me/.local/state/capri-update-failed" || fail "the conflict wasn't written down"
out=$(run) || fail "the retry of a failed release failed: $out"
grep -q "up to date (v0.2.0); not on v0.3.0" <<<"$out" || fail "a failed release was tried again: $out"
[[ -z $(run --check) ]] || fail "--check offers a release that failed"

# A release that doesn't build: she stays, it's written down
g "$t/up" checkout -q v0.1.0 -- app.js; touch "$t/up/NOBUILD"; g "$t/up" add -A; g "$t/up" commit -qm nobuild; g "$t/up" tag v0.3.5
out=$(run) && fail "a release that doesn't build reported success"
[[ $(cur) == "$second" ]] || fail "switched to a release that doesn't build"
grep -q "build failed on v0.3.5" "$t/ho|me/.local/state/capri-update-failed" || fail "the failed build wasn't written down"
# A release whose check fails: she stays; the one after it that passes is installed and the failure cleared
g "$t/up" rm -q NOBUILD; touch "$t/up/FAILTEST"; g "$t/up" add -A; g "$t/up" commit -qm four; g "$t/up" tag v0.4.0
out=$(run) && fail "a release failing its check reported success"
[[ $(cur) == "$second" ]] || fail "switched to a release failing its check"
g "$t/up" rm -q FAILTEST; g "$t/up" commit -qm five; g "$t/up" tag v0.5.0
mkdir -p "$app/0dead00/node_modules"  # (a run cut off mid-build: its merge isn't made again, so it's never finished)
out=$(run) || fail "v0.5.0: $out"
[[ ! -d $app/0dead00 && -d $app/src/.git ]] || fail "a build a cut-off run left wasn't removed (or the clone went)"
[[ $(cur) != "$second" && ! -e "$t/ho|me/.local/state/capri-update-failed" ]] || fail "v0.5.0 not installed: $out"
[[ ! -d $app/$first ]] || fail "builds older than the one before weren't removed"

# A Capri still running from an older build (two updates without her restarted): that build stays until she's gone
third=$(cur)
(cd "$app/$second" && exec sleep 60) & running=$!
echo 'z' >"$t/up/other.js"; g "$t/up" commit -qam six; g "$t/up" tag v0.6.0
out=$(run) || fail "v0.6.0: $out"
echo 'w' >"$t/up/other.js"; g "$t/up" commit -qam seven; g "$t/up" tag v0.7.0
out=$(run) || fail "v0.7.0: $out"
[[ -d $app/$second ]] || fail "the build a running Capri is on was removed"
kill $running; wait $running 2>/dev/null
echo 'v' >"$t/up/other.js"; g "$t/up" commit -qam eight; g "$t/up" tag v0.8.0
out=$(run) || fail "v0.8.0: $out"
[[ ! -d $app/$second && ! -d $app/$third ]] || fail "builds no longer running weren't removed"
# Her build's mark not written (a full disk): not switched to (unmarked, the next run removed it as one cut off: hers)
fourth=$(cur)
echo 'u' >"$t/up/other.js"; g "$t/up" commit -qam nine; g "$t/up" tag v0.9.0
touch "$t/npmfail.mark"
out=$(run) && fail "a build with no mark reported success"
[[ $(cur) == "$fourth" && -f $app/$fourth/.capri-build ]] || fail "switched to a build with no mark: $(cur)"
rm "$t/npmfail.mark"
out=$(run) || fail "v0.9.0 after a full disk: $out"
[[ $(cur) != "$fourth" && -f $app/current/.capri-build ]] || fail "v0.9.0 not installed after a full disk: $out"
# A release tag moved upstream (the same v* on other code): refused, said (dotfiles-check's file), nothing switched;
# fetched again once that tag is taken out, said no more
fifth=$(cur)
# (a combination that failed before, written down: kept alongside, not overwritten by the moved tag)
failedf="$t/ho|me/.local/state/capri-update-failed"
printf 'aaa bbb\nAn older failure.\n' >"$failedf"
echo 't' >"$t/up/other.js"; g "$t/up" commit -qam ten; g "$t/up" tag -f v0.9.0 >/dev/null
out=$(run --check) && fail "a moved tag was taken: $out"
grep -q "v0.9.0 was moved" <<<"$out" && grep -q "v0.9.0 was moved" "$failedf" || fail "a moved tag wasn't said: $out"
{ head -1 "$failedf" | tr ';' '\n' | grep -qx "aaa bbb" && grep -q "An older failure" "$failedf"; } ||
    fail "the moved tag overwrote what failed before: $(cat "$failedf")"
out=$(run) && fail "an update over a moved tag reported success: $out"
[[ $(cur) == "$fifth" ]] || fail "switched with a release tag moved"
[[ $(grep -c "was moved" "$failedf") == 1 ]] || fail "the moved tag written down twice: $(cat "$failedf")"
g "$app/src" tag -d v0.9.0 >/dev/null
out=$(run --check) || fail "--check after the moved tag was taken out: $out"
grep -q "moved" "$failedf" && fail "the moved tag still said after it was taken out: $(cat "$failedf")"
[[ $(cat "$failedf") == $'aaa bbb\nAn older failure.' ]] || fail "what failed before lost with the moved tag: $(cat "$failedf")"
rm "$failedf"
# A release tag deleted upstream: gone here too (pruned), not merged as a release that's no more
g "$t/up" tag -d v0.8.0 >/dev/null
run --check >/dev/null
[[ -z $(git -C "$app/src" tag -l v0.8.0) ]] || fail "a release tag deleted upstream kept"

# Her folder a clone of the old Capri (another original, its own tags): --check says so, then it's cloned again from
# this one and built; the old Capri's build not kept to go back to, and her hooks from it (a script now gone) said
g "$app/src" remote set-url upstream "$t/old-original"
g "$app/src" tag -f v9.9.9 >/dev/null
grep -q "update available (the new Capri)" <<<"$(run --check)" || fail "--check missed the old Capri"
mkdir -p "$t/ho|me/.claude"
printf '{"command": "node \\"%s/current/hooks/capri-hook.js\\""}\n' "$app" >"$t/ho|me/.claude/settings.json"
echo 's' >"$t/up/other.js"; g "$t/up" commit -qam eleven; g "$t/up" tag v1.0.0
out=$(run) || fail "the old Capri not replaced: $out"
[[ $(git -C "$app/src" remote get-url upstream) == "$t/up" && -z $(git -C "$app/src" tag -l v9.9.9) ]] ||
    fail "her old clone kept"
[[ $(cat "$app/current/other.js") == s && $(cat "$app/current/app.js") == mine ]] || fail "not built from the new one: $out"
[[ ! -d $app/$fifth ]] || fail "the old Capri's build kept"
grep -q "old Capri's hooks are still on" <<<"$out" || fail "her old hooks not said: $out"
[[ ! -e $t/prompts ]] || fail "git could ask for a login: $(head -1 "$t/prompts")"
# (checked last: the reload is in the background, and the updates since have given it the time)
[[ $(wc -l <"$t/hyprctl") == 1 ]] || fail "an update reloaded the config (only her first install needs it)"
echo "ok capri-update"
