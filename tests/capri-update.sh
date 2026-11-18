#!/usr/bin/env bash
# capri-update with a stand-in fork (a local repo as her main), npm and cargo: installs her one binary, updates her to
# my fork's new commits, keeps her build when a commit fails her checks, doesn't build or doesn't install (and doesn't
# build it again), tries a download that failed again (three runs in a row: the commit's own), keeps the build before
# and any she's running from, uses the fork's last copy when it can't be reached, --check, one run at a time, and her
# Electron build from before replaced
set -uo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
g() { git -C "$1" -c user.name=t -c user.email=t@t "${@:2}"; }

git init -q -b main "$t/fork"
mkdir -p "$t/fork/src-tauri/icons"; echo icon >"$t/fork/src-tauri/icons/icon.png"; echo one >"$t/fork/app.js"
g "$t/fork" add -A; g "$t/fork" commit -qm one
# change <app.js> [<file>...]: my fork's next commit, with those files (what makes it fail below) and none of the last's
change() {
    (cd "$t/fork" && rm -f FAILTEST NOBUILD LOCKMISMATCH src-tauri/STALELOCK && echo "$1" >app.js && shift &&
        for f; do touch "$f"; done)
    g "$t/fork" add -A; g "$t/fork" commit -qm "$(cat "$t/fork/app.js")"
}
# npm: "ci" her packages (written down in cis), "run typecheck" and "run test" her checks (failing with a FAILTEST),
# "run tauri build" her binary (a script saying her app.js) in Rust's build folder, the build written down in builds
mkdir -p "$t/bin"
sed "s|@T@|$t|g" >"$t/bin/npm" <<'EOF'
#!/bin/sh
case $1 in
    ci) echo ci >>@T@/cis
        [ "$LC_ALL" = C ] || echo "npm ci" >>@T@/translated
        [ ! -e LOCKMISMATCH ] || { echo "npm error code EUSAGE"; echo "npm error npm ci can only install packages when your package.json and package-lock.json are in sync."; exit 1; }
        [ ! -e @T@/npmfail ] || { echo "npm error code ECONNRESET"; exit 1; }
        mkdir node_modules ;;
    run) [ -d node_modules ] || exit 1
        case $3 in
            typecheck | test) [ ! -e FAILTEST ] ;;
            tauri) [ "$4 $5 $6" = "build -- --no-bundle" ] && [ ! -e NOBUILD ] || exit 1
                echo "$CARGO_NET_OFFLINE $CARGO_TARGET_DIR" >>@T@/builds
                mkdir -p "$CARGO_TARGET_DIR/release" && printf '#!/bin/sh\necho %s\n' "$(cat app.js)" >"$CARGO_TARGET_DIR/release/capri" &&
                    chmod +x "$CARGO_TARGET_DIR/release/capri" ;;
            *) exit 1 ;;
        esac ;;
    *) exit 1 ;;
esac
EOF
# cargo and rustc: none with a norust file (rustup with no toolchain chosen); "cargo fetch" her crates, failing with a
# stale Cargo.lock (src-tauri/STALELOCK) or the network down (cargofail)
sed "s|@T@|$t|g" >"$t/bin/cargo" <<'EOF'
#!/bin/sh
[ ! -e @T@/norust ] || { echo "error: rustup could not choose a version of cargo to run" >&2; exit 1; }
case $1 in
    --version) echo "cargo 1.90.0" ;;
    fetch) [ "$LC_ALL" = C ] || echo "cargo fetch" >>@T@/translated
        [ "$2" = --locked ] || exit 1
        [ ! -e STALELOCK ] || { echo "error: the lock file $PWD/Cargo.lock needs to be updated but --locked was passed to prevent this"; exit 101; }
        [ ! -e @T@/cargofail ] || { echo "error: failed to download from \`https://index.crates.io/config.json\`"; exit 101; } ;;
    *) exit 1 ;;
esac
EOF
printf '#!/bin/sh\n[ ! -e %s/norust ] || exit 1\necho "rustc 1.90.0"\n' "$t" >"$t/bin/rustc"
# cp: fails with a cpfail file (her binary not copied: a full disk)
printf '#!/bin/sh\n[ ! -e %s/cpfail ] || exit 1\nexec %s "$@"\n' "$t" "$(command -v cp)" >"$t/bin/cp"
printf '#!/bin/sh\necho "$*" >>%s/notified\n' "$t" >"$t/bin/notify-send"
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
# git: notes when it could ask for a GitHub login in the terminal (the private fork with none: an unattended run waited on it)
printf '#!/bin/sh\n[ "$GIT_TERMINAL_PROMPT" = 0 ] || echo "$*" >>"%s/prompts"\nexec %s "$@"\n' "$t" "$(command -v git)" >"$t/bin/git"
chmod +x "$t/bin/"*
fork=$t/fork
run() { HOME="$t/ho|me" HYPRLAND_INSTANCE_SIGNATURE='' NOTIFY_WHEN_UP_TRIES=1 PATH=$t/bin:$PATH CAPRI_FORK=$fork \
    "$here/.local/bin/capri-update" "$@" 2>&1; }
cur() { readlink "$app/current"; }
short() { git -C "$t/fork" rev-parse --short HEAD; }
app="$t/ho|me/.local/share/capri"
failedf="$t/ho|me/.local/state/capri-update-failed"
# reloads <n>: the config reloaded n times (in the background, after any game)
reloads() {
    for _ in {1..50}; do [[ $(grep -c reload "$t/hyprctl" 2>/dev/null) == "$1" ]] && return 0; sleep 0.1; done
    return 1
}

out=$(run --check) || fail "--check before install: $out"
[[ -z $out && ! -e $app ]] || fail "--check installed something: $out"
# Rust not installed (or rustup with no toolchain): said, nothing installed, tried again next time (not written down)
touch "$t/norust"
out=$(run); rc=$?
((rc == 2)) && grep -q "Rust isn't installed" <<<"$out" || fail "Rust missing not said ($rc): $out"
[[ ! -e $app/current && ! -e $failedf ]] || fail "installed, or written down as the commit's, without Rust"
rm "$t/norust"
# Her packages not downloaded (network): not installed, and tried again next time
touch "$t/npmfail"
out=$(run) && fail "an install whose packages failed reported success"
[[ ! -e $app/current && ! -e $failedf ]] || fail "installed without her packages, or written down as the commit's"
[[ ! -e $t/hyprctl ]] || fail "the config reloaded with her not installed"
rm "$t/npmfail"
touch "$t/game"
out=$(run) || fail "install failed: $out"
reloads 1 && [[ $(cat "$t/hyprctl") == "-i 0 reload" ]] ||  # (Hyprland named: run from outside it, an SSH login)
    fail "her first install didn't load the config again after the game: $(cat "$t/hyprctl" 2>/dev/null)"
[[ $("$app/current/capri") == one && $(cur) == "$(short)" ]] || fail "not the fork's code: $out"
[[ $(cat "$app/current/.capri-build") == "$(git -C "$t/fork" rev-parse HEAD)" ]] || fail "her build not marked"
[[ $(LC_ALL=C ls -A "$app/current" | paste -sd' ') == ".capri-build capri" ]] || fail "more than her binary kept: $(ls -A "$app/current")"
[[ $(cat "$t/builds") == "true $app/target" ]] || fail "not built offline in the shared Rust build: $(cat "$t/builds")"
grep -qF "Exec=\"$t/ho|me/.local/bin/capri\"" "$t/ho|me/.local/share/applications/capri.desktop" || fail "no launcher entry"
[[ $(cat "$t/ho|me/.local/share/icons/hicolor/256x256/apps/capri.png") == icon ]] || fail "no icon"
out=$(run) || fail "second run: $out"
grep -q "up to date ($(short))" <<<"$out" || fail "not up to date: $out"
first=$(cur)
# The fork from elsewhere for one run (a copy of it: $CAPRI_FORK), then from its own address again
git clone -q --bare "$t/fork" "$t/fork-copy.git"
fork=$t/fork-copy.git
out=$(run --check) || fail "--check from a copy of the fork: $out"
[[ $(git -C "$app/src" remote get-url origin) == "$t/fork-copy.git" ]] || fail "the fork's copy not fetched from"
fork=$t/fork
out=$(run --check) || fail "--check: $out"
[[ $(git -C "$app/src" remote get-url origin) == "$t/fork" ]] || fail "the fork's address not set back"

# A new commit: said by --check, built, switched to, the build before kept, Rust's build the same one
change two
grep -qx "capri: update available ($(short))" <<<"$(run --check)" || fail "--check missed the new commit"
out=$(run) || fail "two: $out"
[[ $("$app/current/capri") == two && -x $app/$first/capri ]] || fail "two not installed, or the build before not kept: $out"
second=$(cur)

# A commit failing her checks: she stays, it's written down and said, not built again, not offered by --check
change three FAILTEST
out=$(run); rc=$?
((rc == 2)) && [[ $(cur) == "$second" ]] || fail "switched to a commit failing her checks ($rc): $out"
[[ $(head -1 "$failedf") == "$(git -C "$t/fork" rev-parse HEAD)" ]] && grep -q "checks failed on $(short)" "$failedf" ||
    fail "the failed check wasn't written down: $(cat "$failedf")"
for _ in {1..50}; do grep -q "Capri not updated" "$t/notified" 2>/dev/null && break; sleep 0.1; done  # (in the background)
grep -q "Capri not updated" "$t/notified" || fail "the failure not said in a notification"
n=$(wc -l <"$t/cis")
out=$(run) || fail "the run after a failed commit failed: $out"
grep -q "failed before, not tried again" <<<"$out" && [[ $(wc -l <"$t/cis") == "$n" ]] || fail "a failed commit was tried again: $out"
[[ -z $(run --check) ]] || fail "--check offers a commit that failed"
# One that doesn't build, a lockfile that doesn't match package.json, a stale Cargo.lock: the same
change four NOBUILD
out=$(run) && fail "a commit that doesn't build reported success"
grep -q "build failed on $(short)" "$failedf" || fail "the failed build wasn't written down: $(cat "$failedf")"
change five LOCKMISMATCH
out=$(run) && fail "a lockfile that doesn't match reported success"
grep -q "package-lock.json don't match" "$failedf" || fail "a lockfile that doesn't match not written down: $(cat "$failedf")"
change six src-tauri/STALELOCK
out=$(run) && fail "a stale Cargo.lock reported success"
grep -q "don't match her Cargo.lock" "$failedf" || fail "a stale Cargo.lock not written down: $(cat "$failedf")"
[[ $(cur) == "$second" ]] || fail "switched to a commit that failed"
# Her crates not downloaded (the network): tried again, and at the third run in a row it's that commit's own
change seven
touch "$t/cargofail"
for _ in 1 2; do
    out=$(run) && fail "a failed crates download reported success"
    [[ $(head -1 "$failedf") != "$(git -C "$t/fork" rev-parse HEAD)" ]] || fail "a failed download written down as the commit's"
done
out=$(run) && fail "a third failed download reported success"
grep -q "didn't download.*3 runs in a row" "$failedf" || fail "the third failed download not written down: $(cat "$failedf")"
rm "$t/cargofail"

# The next good commit: installed, the failure cleared; a build a cut-off run left and builds older than the one before
# removed; her clone, Rust's build and a folder of yours there kept
mkdir -p "$app/0dead00" "$app/rust"
change eight
out=$(run) || fail "eight: $out"
[[ $("$app/current/capri") == eight && ! -e $failedf ]] || fail "eight not installed, or the failure kept: $out"
[[ ! -d $app/0dead00 && ! -d $app/$first && -d $app/$second ]] || fail "old builds not removed, or the one before not kept"
[[ -d $app/rust && -d $app/src/.git && -d $app/target ]] || fail "a folder not hers removed"
third=$(cur)
# A Capri still running from an older build (two updates without her restarted): that build stays until she's gone
cp "$(command -v sleep)" "$app/$second/capri"
"$app/$second/capri" 60 & running=$!
on_exit "kill $running"
change nine; out=$(run) || fail "nine: $out"
change ten; out=$(run) || fail "ten: $out"
[[ -d $app/$second ]] || fail "the build a running Capri is on was removed"
kill $running; wait $running 2>/dev/null
change eleven; out=$(run) || fail "eleven: $out"
[[ ! -d $app/$second && ! -d $app/$third ]] || fail "builds no longer running weren't removed"
# My fork's main set back to the build before: switched back to it, not built again
g "$t/fork" reset -q --hard HEAD~1
n=$(wc -l <"$t/builds")
out=$(run) || fail "ten again: $out"
[[ $("$app/current/capri") == ten && $(wc -l <"$t/builds") == "$n" ]] || fail "the build before not reused: $out"
# Her binary not copied (a full disk): not switched to, not written down; the next run installs it
change twelve
touch "$t/cpfail"
out=$(run) && fail "a build not copied reported success"
[[ $("$app/current/capri") == ten && ! -e $failedf && ! -d $app/$(short) ]] || fail "switched, or written down, with a full disk: $out"
rm "$t/cpfail"
out=$(run) || fail "twelve after a full disk: $out"
[[ $("$app/current/capri") == twelve ]] || fail "twelve not installed after a full disk: $out"

# The fork unreachable (no GitHub login, at boot): its last copy used, said, nothing offered
change thirteen
fork=$t/nowhere
out=$(run --check) || fail "--check with the fork unreachable: $out"
[[ $out == *"not fetched"*"last copy used"* && $out != *"update available"* ]] || fail "the fork unreachable not said: $out"
out=$(run) || fail "an update with the fork unreachable: $out"
grep -q "up to date" <<<"$out" || fail "her last copy not used: $out"
fork=$t/fork

# One at a time: a --check while an update runs says nothing, an update waits its turn
lock="$t/ho|me/.local/state/capri-update.lock"
flock "$lock" sleep 3 & holder=$!
# (until it holds the lock, however busy the machine: a fixed wait lost the race with the other tests running)
for _ in {1..50}; do flock -n "$lock" true || break; sleep 0.1; done
start=$SECONDS
out=$(run --check)
[[ -z $out && $((SECONDS - start)) -lt 2 ]] || fail "--check during an update waited or said something: $out"
out=$(run) || fail "thirteen: $out"
grep -q "waiting for the other" <<<"$out" && grep -q "$(short) installed" <<<"$out" || fail "the update didn't wait its turn: $out"
wait $holder

# Her Electron build from before (current on it, her clone the same fork): replaced by her binary and not kept, and the
# config loaded again (her key now looks for her binary)
e=$app/e1ec7a0
mkdir -p "$e/node_modules/.bin"; echo '{}' >"$e/package.json"; echo "a b" >"$e/.capri-build"
ln -sfn e1ec7a0 "$app/current"
change fourteen
grep -qx "capri: update available ($(short))" <<<"$(run --check)" || fail "--check missed the Electron build's replacement"
out=$(run) || fail "the Electron build not replaced: $out"
[[ $("$app/current/capri") == fourteen && ! -d $e ]] || fail "the Electron build kept: $out"
reloads 2 || fail "the config not loaded again over the Electron build: $(cat "$t/hyprctl")"
# Her clone gone, her build still here: --check says so, an update clones her again
rm -rf "$app/src"
grep -q "update available" <<<"$(run --check)" || fail "--check with her clone gone said nothing"
out=$(run) || fail "her clone not made again: $out"
[[ -d $app/src/.git ]] && grep -q "up to date" <<<"$out" || fail "her clone not made again: $out"
[[ ! -e $t/prompts ]] || fail "git could ask for a login: $(head -1 "$t/prompts")"
[[ ! -e $t/translated ]] || fail "npm or cargo ran in the session's language (their messages are read in English): $(head -3 "$t/translated")"
# (checked last: the reload is in the background, and the updates since have given it the time)
[[ $(wc -l <"$t/hyprctl") == 2 ]] || fail "an update reloaded the config (only her first install and the Electron one's need it)"
echo "ok capri-update"
