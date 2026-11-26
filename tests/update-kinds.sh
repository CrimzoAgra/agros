#!/usr/bin/env bash
# update-kinds (the kinds of update both update-apps and the boot's auto-update run), with stand-ins for the network
# (curl serves local files), fwupd, npm, uv and cargo: Proton's newest build added beside the old ones, the ones a game
# uses kept, an unused old one removed, a download not matching its checksum refused; firmware listed and installed;
# developer tools updated only when there, npm's only with its prefix in your home
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
mkdir -p "$t/bin" "$t/home" "$t/srv"
# The programs update-kinds may use, alone on PATH (with the stand-ins): a tool on this machine (npm, uv...) isn't taken
# for one the test has
mkdir "$t/sys"
for c in bash env jq awk sed grep cut sort tail head ls mktemp rm mv cp mkdir tar gzip sha512sum timeout cat dirname \
    readlink tr paste seq sleep printf touch xz find id flock vercmp; do
    p=$(command -v "$c") && ln -s "$p" "$t/sys/$c"
done
run() { HOME=$t/home PATH=$t/bin:$t/sys STEAM_ROOT=$t/steam "$here/.local/bin/update-kinds" "$@"; }
stub checkupdates 'exit 2'
for c in paru flatpak notify-send; do stub "$c" 'true'; done
# Steam running ($STEAM_RUNS; asked for this user's alone), and what's running ($PS: ps's lines)
# shellcheck disable=SC2016  # (expanded by the stand-ins)
stub pgrep 'echo "pgrep $*" >>'"$t"'/pgrep; [ -n "${STEAM_RUNS:-}" ]'
# shellcheck disable=SC2016
# ($PS_MORE: a long list after it, as on a busy desktop: read whole, or ps is cut off mid-list and the match lost)
stub ps 'printf "%s\n" "${PS:-}"; [ -z "${PS_MORE:-}" ] || seq 200000'

# --- Proton: GE-Proton11-6 (a game's), GE-Proton11-5 (nothing's, this one's install), GE-Proton11-4 (nothing's, put
# there by hand: never removed), the newest GE-Proton11-12 on GitHub
# (Steam's folder a link, as ~/.steam/root is: a running Proton's path is the real one)
tools=$t/steam/compatibilitytools.d
mkdir -p "$t/steam-real/compatibilitytools.d" "$t/steam-real/config" "$t/srv/GE-Proton11-12-x86_64"
ln -s steam-real "$t/steam"
for v in GE-Proton11-4 GE-Proton11-5 GE-Proton11-6; do
    mkdir "$tools/$v"
    printf '"compatibilitytools"\n{\n  "compat_tools"\n  {\n    "%s" // Internal name\n    {\n    }\n  }\n}\n' "$v" >"$tools/$v/compatibilitytool.vdf"
done
cat >"$t/steam/config/config.vdf" <<'V'
"InstallConfigStore"
{
	"Software"
	{
		"Valve"
		{
			"Steam"
			{
				"CompatToolMapping"
				{
					"0"
					{
						"name"		"proton_experimental"
					}
					"1245620"
					{
						"name"		"GE-Proton11-6"
						"config"		""
					}
				}
			}
		}
	}
}
V
touch "$tools/GE-Proton11-5/.agros-installed"
echo GE-Proton11-12 >"$t/srv/GE-Proton11-12-x86_64/version"
tar -czf "$t/srv/GE-Proton11-12-x86_64.tar.gz" -C "$t/srv" GE-Proton11-12-x86_64
(cd "$t/srv" && sha512sum GE-Proton11-12-x86_64.tar.gz >GE-Proton11-12-x86_64.sha512sum)
gh=https://github.com/GloriousEggroll/proton-ge-custom/releases/download/GE-Proton11-12
cat >"$t/srv/ge.json" <<J
{"tag_name": "GE-Proton11-12", "assets": [
 {"browser_download_url": "$gh/GE-Proton11-12-aarch64.tar.gz"},
 {"browser_download_url": "$gh/GE-Proton11-12-x86_64.sha512sum"},
 {"browser_download_url": "$gh/GE-Proton11-12-x86_64.tar.gz"}]}
J
# curl: the release's JSON from its API, a file from its name; with -o, into that file. dw-proton's: none here
# shellcheck disable=SC2016  # (expanded by the stand-in)
stub curl 'o=; for a; do [ "$prev" = -o ] && o=$a; prev=$a; done; u=${@: -1}
case $u in */proton-ge-custom/releases/latest) f='"$t"'/srv/ge.json ;; */releases/latest) exit 22 ;; *) f='"$t"'/srv/${u##*/} ;; esac
[ -f "$f" ] || exit 22; if [ -n "$o" ]; then cp "$f" "$o"; else cat "$f"; fi'
out=$(run --list)
[[ $out == $'proton\tGE-Proton\tGE-Proton11-6\tGE-Proton11-12' ]] || fail "Proton's newest not listed: $out"
# A download not matching its checksum: refused, nothing removed
cp "$t/srv/GE-Proton11-12-x86_64.sha512sum" "$t/good"
# (its first digit changed for another, whatever it was)
sed -i 's/^0/1/; t; s/^./0/' "$t/srv/GE-Proton11-12-x86_64.sha512sum"
cmp -s "$t/good" "$t/srv/GE-Proton11-12-x86_64.sha512sum" && fail "test setup: the checksum not broken"
out=$(run proton) && fail "a Proton not matching its checksum reported success"
[[ $out == *"doesn't match its checksum, not installed"* && ! -e $tools/GE-Proton11-12-x86_64 && -d $tools/GE-Proton11-5 ]] ||
    fail "a Proton not matching its checksum installed, or the old ones touched: $out"
[[ -z $(find "$tools" -maxdepth 1 -name '.agros-proton.*') ]] || fail "the refused download left behind"
cp "$t/good" "$t/srv/GE-Proton11-12-x86_64.sha512sum"
# (a download an earlier run left, cut off: removed; one under way, recent, isn't. A Lutris game on GE-Proton11-3, named
# without the folder's -x86_64 as Lutris newer than 0.5.22 (its development version) does: kept, though it's in Steam's
# folder)
mkdir "$tools/.agros-proton.Old0ld" "$tools/.agros-proton.New0nw" "$tools/GE-Proton11-3-x86_64"
touch -d '7 hours ago' "$tools/.agros-proton.Old0ld"
touch "$tools/GE-Proton11-3-x86_64/.agros-installed"
mkdir -p "$t/home/.local/share/lutris/games"
printf 'wine:\n  version: GE-Proton11-3\n' >"$t/home/.local/share/lutris/games/x.yml"
out=$(run proton) || fail "the Proton update failed: $out"
[[ ! -e $tools/.agros-proton.Old0ld && -e $tools/.agros-proton.New0nw ]] || fail "a download left behind not swept, or one under way taken: $(ls -a "$tools")"
[[ -d $tools/GE-Proton11-3-x86_64 ]] || fail "a Proton a Lutris game is on (named without -x86_64) removed"
rm -rf "$tools/.agros-proton.New0nw" "$tools/GE-Proton11-3-x86_64" "$t/home/.local/share/lutris"
# A relative runner_dir in lutris.conf: a folder named from wherever this runs, not one it looks in (nothing listed,
# installed or removed there)
rel=$t/cwd/rel/wine
mkdir -p "$rel/GE-Proton11-5" "$rel/.agros-proton.Old0ld" "$t/home/.local/share/lutris"
touch "$rel/GE-Proton11-5/.agros-installed"; touch -d '7 hours ago' "$rel/.agros-proton.Old0ld"
echo 'runner_dir = rel' >"$t/home/.local/share/lutris/lutris.conf"
[[ -z $(cd "$t/cwd" && run --list | grep Lutris) ]] || fail "a relative runner_dir's Protons listed"
(cd "$t/cwd" && run proton >/dev/null) || fail "the Proton update failed with a relative runner_dir"
[[ -d $rel/GE-Proton11-5 && -d $rel/.agros-proton.Old0ld && ! -e $rel/GE-Proton11-12-x86_64 ]] ||
    fail "a relative runner_dir's folder, from where it ran, changed: $(ls -a "$rel")"
rm -rf "$t/cwd" "$t/home/.local/share/lutris"
[[ $(cat "$tools/GE-Proton11-12-x86_64/version" 2>/dev/null) == GE-Proton11-12 ]] || fail "the newest Proton not installed: $out"
[[ -d $tools/GE-Proton11-6 && ! -e $tools/GE-Proton11-5 ]] || fail "the used Proton removed, or the unused one kept: $(ls "$tools")"
[[ -d $tools/GE-Proton11-4 ]] || fail "a Proton put there by hand removed"
[[ -e $tools/GE-Proton11-12-x86_64/.agros-installed ]] || fail "the new Proton not marked as this one's install"
[[ $out == *"Restart Steam to see: GE-Proton11-12-x86_64"* ]] || fail "Steam's restart not said: $out"
[[ -z $(run --list) ]] || fail "Proton still listed once installed: $(run --list)"
grep -q "^pgrep -u $(id -u) -x steam$" "$t/pgrep" || fail "Steam's running not looked for as this user's: $(cat "$t/pgrep" 2>/dev/null)"
# One this installed, running (its real path, not Steam's link): kept; stopped, removed
mkdir "$tools/GE-Proton11-2"; touch "$tools/GE-Proton11-2/.agros-installed"
PS="$t/steam-real/compatibilitytools.d/GE-Proton11-2/files/bin/wine64 game.exe" PS_MORE=1 run proton >/dev/null
[[ -d $tools/GE-Proton11-2 ]] || fail "a running Proton removed"
run proton >/dev/null
[[ ! -e $tools/GE-Proton11-2 ]] || fail "a stopped old Proton kept"
# From the boot's run (--boot), Steam running: the notice handed to it on fd 3 (it tells you once you're logged in),
# not sent from here. (notify-send noted; each run's output read through fd 5 too, which what it sends in the
# background inherits: read whole, every notification it sent is noted. Run from Updates, the same notice is sent)
stub notify-send 'echo "$*" >>'"$t"'/notified'
mkdir "$tools/GE-Proton11-1"; rm -rf "$tools/GE-Proton11-12-x86_64"; : >"$t/notified"
: "$(STEAM_RUNS=1 run proton 5>&1 >/dev/null)"
grep -q "New Proton: GE-Proton11-12-x86_64" "$t/notified" || fail "test setup: Updates' Steam notice not sent: $(cat "$t/notified")"
rm -rf "$tools/GE-Proton11-12-x86_64"; : >"$t/notified"
: "$(STEAM_RUNS=1 run --boot proton 3>"$t/boot-notes" 5>&1 >/dev/null)"
[[ $(cat "$t/boot-notes") == $'steam\tNew Proton: GE-Proton11-12-x86_64\tRestart Steam to pick it in a game\'s settings' && ! -s $t/notified ]] ||
    fail "the boot's Steam notice not handed over: $(cat "$t/boot-notes") / $(cat "$t/notified")"
rm -rf "$tools/GE-Proton11-1"
stub notify-send 'true'
# Steam's default on the old one: kept too
sed -i 's/"name"\t\t"GE-Proton11-6"/"name"\t\t"x"/; s/proton_experimental/GE-Proton11-6/' "$t/steam/config/config.vdf"
run proton >/dev/null
[[ -d $tools/GE-Proton11-6 ]] || fail "the Proton Steam's default uses removed"
# No Proton family there: nothing looked up
rm -rf "$tools"/GE-*
stub curl 'echo "curl $*" >>'"$t"'/curl; exit 22'
run --list >/dev/null; run proton >/dev/null
[[ ! -e $t/curl ]] || fail "a Proton family looked up with none installed"

# --- Proton in Lutris's Wine runners (under XDG_DATA_HOME): Lutris's own dw-proton-x86_64 (no version in its name: its
# version file's, dwproton-11.0-14), a game's; dwproton-11.0-15-x86_64, this one's install, nothing's;
# dwproton-11.0-16-x86_64, put there by hand, nothing's. The newest, dwproton-11.0-17, added beside them
export XDG_DATA_HOME=$t/data
wine=$XDG_DATA_HOME/lutris/runners/wine
mkdir -p "$wine"/{dw-proton-x86_64,dwproton-11.0-15-x86_64,dwproton-11.0-16-x86_64} "$XDG_DATA_HOME/lutris/games" "$t/srv/dwproton-11.0-17-x86_64"
echo "1790724403 dwproton-11.0-14" >"$wine/dw-proton-x86_64/version"
echo "1790724404 dwproton-11.0-15" >"$wine/dwproton-11.0-15-x86_64/version"
touch "$wine/dwproton-11.0-15-x86_64/.agros-installed"
printf 'game:\n  exe: x.exe\nversion: Standard\nwine:\n  version: dw-proton-x86_64\n' >"$XDG_DATA_HOME/lutris/games/ea-app-1.yml"
echo "1790724405 dwproton-11.0-17" >"$t/srv/dwproton-11.0-17-x86_64/version"
tar -cJf "$t/srv/dwproton-11.0-17-x86_64.tar.xz" -C "$t/srv" dwproton-11.0-17-x86_64
(cd "$t/srv" && sha512sum dwproton-11.0-17-x86_64.tar.xz >dwproton-11.0-17-x86_64.sha512sum)
dw=https://dawn.wine/dawn-winery/dwproton/releases/download/dwproton-11.0-17
cat >"$t/srv/dw.json" <<J
{"tag_name": "dwproton-11.0-17", "assets": [
 {"browser_download_url": "$dw/dwproton-11.0-17-x86_64.sha512sum"},
 {"browser_download_url": "$dw/dwproton-11.0-17-x86_64.tar.xz"}]}
J
# shellcheck disable=SC2016
stub curl 'o=; for a; do [ "$prev" = -o ] && o=$a; prev=$a; done; u=${@: -1}
case $u in */dwproton/releases/latest) f='"$t"'/srv/dw.json ;; */releases/latest) exit 22 ;; *) f='"$t"'/srv/${u##*/} ;; esac
[ -f "$f" ] || exit 22; if [ -n "$o" ]; then cp "$f" "$o"; else cat "$f"; fi'
stub notify-send 'echo "$*" >>'"$t"'/notified'
out=$(run --list)
[[ $out == $'proton\tdwproton (Lutris)\tdwproton-11.0-16\tdwproton-11.0-17' ]] || fail "Lutris's dwproton not listed: $out"
out=$(run proton) || fail "the Lutris Proton update failed: $out"
[[ -e $wine/dwproton-11.0-17-x86_64/.agros-installed && -d $wine/dw-proton-x86_64 && -d $wine/dwproton-11.0-16-x86_64 &&
    ! -e $wine/dwproton-11.0-15-x86_64 ]] || fail "Lutris's: the newest not added, a game's or a hand-installed one removed, or this one's old one kept: $(ls "$wine")"
[[ $out == *"Wine version. Your games on dw-proton-x86_64 keep it until you pick dwproton-11.0-17-x86_64."* ]] || fail "how to pick it in Lutris not said: $out"
for _ in $(seq 50); do [[ -s $t/notified ]] && break; sleep 0.1; done
grep -q "New Proton in Lutris: dwproton-11.0-17-x86_64" "$t/notified" || fail "Lutris's new Proton not notified: $(cat "$t/notified" 2>/dev/null)"
[[ -z $(run --list) ]] || fail "Lutris's Proton still listed once installed: $(run --list)"
# Lutris's config in ~/.config/lutris when that's there (its own rule): the Wine runner's default there keeps one
mkdir -p "$t/home/.config/lutris/runners"; printf 'wine:\n  version: "dwproton-11.0-16-x86_64"\n' >"$t/home/.config/lutris/runners/wine.yml"
touch "$wine/dwproton-11.0-16-x86_64/.agros-installed"
run proton >/dev/null
[[ -d $wine/dwproton-11.0-16-x86_64 && ! -e $wine/dw-proton-x86_64/.agros-installed ]] || fail "Lutris's default Wine version removed"
rm "$t/home/.config/lutris/runners/wine.yml"
run proton >/dev/null
[[ ! -e $wine/dwproton-11.0-16-x86_64 && -d $wine/dw-proton-x86_64 ]] || fail "an unused one this installed kept, or Lutris's own removed (its games now on ~/.config's, none)"
unset XDG_DATA_HOME

# --- Firmware: listed from fwupd; installed by it (a UEFI capsule applied at the next restart): no longer offered once
# installed ($t/fw-done), still offered when fwupd skipped it ($FW_SKIPS: needs AC power) though it exits 0
# shellcheck disable=SC2016
stub fwupdmgr 'echo "fwupdmgr $*" >>'"$t"'/fw
case $1 in
    get-updates) [ -e '"$t"'/fw-done ] && exit 2; echo "{\"Devices\":[{\"DeviceId\":\"d1\",\"Name\":\"UEFI dbx\",\"Version\":\"1\",\"Releases\":[{\"Version\":\"2\"}]}]}" ;;
    update) [ -n "${FW_SKIPS:-}" ] && echo "  ‣ Device requires AC power to be connected" || touch '"$t"'/fw-done ;;
esac; true'
[[ $(run --list) == $'firmware\tUEFI dbx\t1\t2' ]] || fail "firmware not listed: $(run --list)"
out=$(FW_SKIPS=1 run firmware) && fail "a firmware update fwupd skipped (exit 0) reported success: $out"
[[ $out == *"Firmware not installed: UEFI dbx"* ]] || fail "a skipped firmware update not said: $out"
out=$(run firmware) || fail "the firmware update failed: $out"
grep -q '^fwupdmgr update -y --no-reboot-check' "$t/fw" && [[ $out == *"applied at the next restart"* ]] || fail "firmware not installed: $out"
# ...not one the EFI partition has no room for (the shutdown's install found it: auto-update's firmware-noroom): not
# listed, nor tried by Update all (it never fits: every run failed on it). A newer release of it is, as at shutdown
rm -f "$t/fw-done" "$t/fw"; mkdir -p "$t/au"
printf 'd1\tUEFI dbx\t1\t2\n' >"$t/au/firmware-noroom"
export AUTO_UPDATE_DIR=$t/au
[[ -z $(run --list) ]] || fail "firmware with no room on the EFI partition listed: $(run --list)"
out=$(run firmware) || fail "the firmware update failed with only one with no room waiting: $out"
! grep -q '^fwupdmgr update' "$t/fw" || fail "firmware with no room on the EFI partition tried again: $(cat "$t/fw")"
printf 'd1\tUEFI dbx\t1\t1.5\n' >"$t/au/firmware-noroom"
[[ $(run --list) == $'firmware\tUEFI dbx\t1\t2' ]] || fail "a newer firmware than the one with no room not listed: $(run --list)"
run firmware >/dev/null || fail "a newer firmware than the one with no room not installed"
grep -qx 'fwupdmgr update -y --no-reboot-check --no-unreported-check d1' "$t/fw" || fail "a newer firmware not tried: $(cat "$t/fw")"
unset AUTO_UPDATE_DIR
stub fwupdmgr 'exit 1'
run firmware >/dev/null && fail "a failed firmware update reported success"
rm "$t/bin/fwupdmgr"

# --- Flatpaks: each installation's -origin remotes (an app installed from a file) have their URL emptied before its
# flatpak update (flatpak-bundle-update --no-origin-urls), else flatpak took the app from the URL its file named; one
# that couldn't be ($MODIFY_FAILS: the system's password prompt cancelled) leaves that installation not updated. At
# boot the user's alone (root does the system's)
# shellcheck disable=SC2016  # (expanded by the stand-in)
stub flatpak 'echo "flatpak $*" >>'"$t"'/fp
case $1 in
    remotes) printf "app-origin\thttps://example.com/repo\nflathub\thttps://dl.flathub.org/repo/\n" ;;
    remote-modify) [ -z "${MODIFY_FAILS:-}" ] || [ "$2" != --system ] || exit 1 ;;
esac
exit 0'
run flatpak >/dev/null || fail "the Flatpaks' update failed"
[[ $(grep -E '^flatpak (remote-modify|update)' "$t/fp") == $'flatpak remote-modify --user --url= app-origin\nflatpak update --user -y\nflatpak remote-modify --system --url= app-origin\nflatpak update --system -y' ]] ||
    fail "a flatpak update before its -origin remotes' URLs were emptied: $(cat "$t/fp")"
rm -f "$t/fp"
out=$(MODIFY_FAILS=1 run flatpak) && fail "the Flatpaks' update succeeded with a system -origin remote's URL left: $out"
[[ $out == *"Flatpaks (system installation) not updated"* ]] && grep -qx 'flatpak update --user -y' "$t/fp" &&
    ! grep -q '^flatpak update --system' "$t/fp" || fail "the system's Flatpaks updated with an -origin remote's URL left: $out / $(cat "$t/fp")"
rm -f "$t/fp"
run --boot flatpak >/dev/null || fail "the boot's Flatpak update failed"
[[ $(grep -E '^flatpak (remote-modify|update)' "$t/fp") == $'flatpak remote-modify --user --url= app-origin\nflatpak update --user -y --noninteractive' ]] ||
    fail "the boot's Flatpak update not the user's alone, after its -origin remotes' URLs were emptied: $(cat "$t/fp")"
# Run in a terminal (update-apps): flatpak setting the terminal up for its progress, in a process group of timeout's
# own, was stopped by the kernel (SIGTTOU) and never ended, timeout's own deadline included
if scr=$(command -v script); then
    stub flatpak '[ "$1" != update ] || '"$(command -v stty)"' sane </dev/tty'
    HOME=$t/home PATH=$t/bin:$t/sys STEAM_ROOT=$t/steam SHELL=/bin/bash timeout -s KILL 30 \
        "$scr" -qec "$here/.local/bin/update-kinds flatpak" /dev/null >/dev/null ||
        fail "the Flatpaks' update, run in a terminal, stopped or failed"
fi
stub flatpak 'true'

# --- Developer tools: only those there; npm's global packages only with its prefix in your home
# shellcheck disable=SC2016
stub npm 'echo "npm $*" >>'"$t"'/dev; case "$*" in "config get prefix") echo "$NPM_PREFIX" ;; "outdated -g --json") echo "{\"pnpm\":{\"current\":\"9.0.0\",\"latest\":\"10.1.0\"}}" ;; esac'
stub uv 'echo "uv $*" >>'"$t"'/dev; [ "$*" = "tool list" ] && echo "ruff v0.1"; true'
NPM_PREFIX=/usr run dev >/dev/null || fail "the developer tools' update failed"
grep -q 'npm install' "$t/dev" && fail "/usr's npm packages (pacman's) updated"
grep -q '^uv tool upgrade --all$' "$t/dev" || fail "uv's tools not updated: $(cat "$t/dev")"
[[ -z $(NPM_PREFIX=/usr run --list) ]] || fail "/usr's npm packages listed"
: >"$t/dev"
[[ $(NPM_PREFIX=$t/home/.npm-global run --list) == $'dev\tnpm pnpm\t9.0.0\t10.1.0' ]] || fail "npm's outdated not listed"
mkdir -p "$t/home/.cargo"; echo '{"installs":{}}' >"$t/home/.cargo/.crates2.json"; stub cargo 'echo "cargo $*" >>'"$t"'/dev'
out=$(NPM_PREFIX=$t/home/.npm-global run dev) || fail "the developer tools' update failed"
grep -q '^npm install -g pnpm@latest$' "$t/dev" || fail "npm's own packages not updated: $(cat "$t/dev")"
[[ $out == *"cargo install cargo-update does that"* ]] && ! grep -q '^cargo' "$t/dev" || fail "cargo without cargo-update not said: $out"
grep -qE '^(rustup|pipx)' "$t/dev" && fail "a tool not installed run"
stub cargo-install-update 'true'
NPM_PREFIX=/usr run dev >/dev/null
grep -q '^cargo install-update -a$' "$t/dev" || fail "cargo's programs not updated with cargo-update there"
# One run at a time per user: another holding its lock (the boot's), this one waits, then runs
mkdir -p "$t/home/.local/state/agros"
exec 6>>"$t/home/.local/state/agros/update-kinds.lock"; flock 6
: >"$t/dev"
NPM_PREFIX=/usr run dev >"$t/waited" 2>&1 6>&- &
waiter=$!
sleep 1
[[ ! -s $t/dev ]] && grep -q "Waiting for the other update run" "$t/waited" || fail "a second run didn't wait for the first: $(cat "$t/waited")"
flock -u 6; exec 6>&-
wait "$waiter" || fail "the run that waited failed: $(cat "$t/waited")"
grep -q '^uv tool upgrade' "$t/dev" || fail "the run that waited didn't run after: $(cat "$t/waited")"
# A helper that leaves something running in the background (a notice, a reload) doesn't hold the lock
# past the run: the next one doesn't wait for it
stub uv 'echo "uv $*" >>'"$t"'/dev; sleep 5 >/dev/null 2>&1 & true'
NPM_PREFIX=/usr run dev >/dev/null 2>&1
flock -n "$t/home/.local/state/agros/update-kinds.lock" true || fail "a helper's background job kept the run's lock"
# The repo's list through the upstream gate (update-gate, the real one), on checkupdates' own copy of the lists: a new
# Hyprland not checked by AgrOS yet not listed as waiting; once approved, listed
echo 'IgnorePkg = hyprland' >"$AGROS_GATE"
: >"$t/qu"
# shellcheck disable=SC2016  # (expanded by the stand-in)
stub pacman 'args=" $* "; echo "pacman $*" >>'"$t"'/qu
case $1 in
    -Q) [ "${@: -1}" = hyprland ] && echo "hyprland 0.57.2-1" ;;
    -Si) echo "Version         : 0.58.0-1" ;;
    -Qu) conf=$(sed -n "s/.*--config \([^ ]*\) .*/\1/p" <<<"$args")
         grep -q "Include = $AGROS_GATE" "$conf" || echo "hyprland 0.57.2-1 -> 0.58.0-1" ;;
esac
true'
out=$(CHECKUPDATES_DB=$t/cdb run --list | grep '^system' || true)
[[ -z $out ]] || fail "a Hyprland not checked yet listed as waiting: $out"
echo 'hyprland 0.58.0' >"$AGROS_GATE_CACHE"
out=$(CHECKUPDATES_DB=$t/cdb run --list | grep '^system' || true)
[[ $out == $'system\thyprland\t0.57.2-1\t0.58.0-1' ]] || fail "an approved Hyprland not listed: $out"
[[ -z $(grep -e '^pacman -Q[ u]' -e '^pacman -Si' "$t/qu" | grep -v -- "--dbpath $t/cdb") ]] ||
    fail "not on checkupdates' copy of the lists: $(cat "$t/qu")"
rm -f "$AGROS_GATE" "$AGROS_GATE_CACHE"
# Two lists at once (Updates opened while the 6-hourly check runs): checkupdates syncs one copy per user and, as the
# real one, fails on its lock (1, "Cannot fetch updates") while another syncs it. Neither said "offline": the second
# waits for the first. And the lock let go once the copy's read: what runs after (paru's AUR, a job it leaves in the
# background) doesn't hold up the next list
# shellcheck disable=SC2016  # (expanded by the stand-in)
stub checkupdates 'mkdir "'"$t"'/cu-busy" 2>/dev/null || exit 1; sleep 1; rm -r "'"$t"'/cu-busy"; exit 2'
stub paru 'sleep 5 >/dev/null 2>&1 & true'
run --list >"$t/list1" & l1=$!
run --list >"$t/list2" & l2=$!
wait "$l1" "$l2"
! grep -q '^offline' "$t/list1" "$t/list2" ||
    fail "two lists at once: one said offline (checkupdates' lock): $(cat "$t/list1" "$t/list2")"
flock -n "$t/home/.local/state/agros/update-list.lock" true || fail "the list's lock held past the list (paru's job)"
echo "ok update-kinds"
