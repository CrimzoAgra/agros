#!/usr/bin/env bash
# agros-personal --save onto a made-up pen drive, then agros-personal into another home: the logins (Claude Code's too) come back (LibreWolf's into
# the new profile, whatever its name), caches stay out, replaced files are backed up, the weather's place comes back,
# nothing is readable on the drive, a wrong passphrase brings nothing back, and it won't save into the repo. Without
# the drive: signing in refused with no terminal, the weather's place asked
set -euo pipefail
. "$(dirname "$0")/lib.sh"
repo=$t/repo drive=$t/drive; mkdir -p "$repo/.local/bin" "$drive" "$t/mods"
cp "$here/.local/bin/firefox-bookmarks-export" "$here/.local/bin/agros-personal" "$repo/.local/bin/"
export GNUPGHOME=$t/gnupg; mkdir -m 700 "$GNUPGHOME"
echo "correct horse battery staple" >"$t/pass"; export PERSONAL_PASSFILE=$t/pass
run() {  # <home> <function> [unused] [drive folder]: agros-personal's function (personal_main: the restore)
    HOME=$1 XDG_RUNTIME_DIR=$t bash -c '
        set -euo pipefail
        source "$0/.local/bin/agros-personal"; personal_dir=$2
        personal_open() { :; }; personal_claude_open() { :; }  # (yours, open while this runs, are not the made-up ones)
        "$1"' "$repo" "$2" "${4-$drive}"
}
profile() {  # <home> <folder name>
    mkdir -p "$1/.config/librewolf/librewolf/$2"
    printf '[Profile0]\nName=default\nPath=%s\nDefault=1\n' "$2" >"$1/.config/librewolf/librewolf/profiles.ini"
}

old=$t/old; profile "$old" abc.default-release
lw=$old/.config/librewolf/librewolf/abc.default-release
echo SECRET-LOGIN >"$lw/logins.json"; mkdir -p "$lw/storage/default/moz-extension+++x"; echo ext >"$lw/storage/default/moz-extension+++x/d"
mkdir -p "$old/.config/equibop/sessionData/Cache" "$old/.local/share/keyrings" "$old/.cache/lutris" "$old/.config/caelestia"
echo SECRET-TOKEN >"$old/.config/equibop/sessionData/token"; echo cache >"$old/.config/equibop/sessionData/Cache/c"
echo SECRET-KEYRING >"$old/.local/share/keyrings/login.keyring"; echo SECRET-BNET >"$old/.cache/lutris/.bnet.auth"
echo '{"services": {"weatherLocation": "Porto"}}' >"$old/.config/caelestia/shell.json"
mkdir -p "$old/.claude/projects/-home-me/memory" "$old/.claude/skills/s"
echo SECRET-CLAUDE >"$old/.claude/.credentials.json"; echo '{"oauthAccount": 1}' >"$old/.claude.json"
mkdir -p "$old/.local/share/Steam/config" "$old/.local/share/Steam/userdata/42/config" "$old/.local/share/Steam/userdata/42/7"
mkdir -p "$old/.config/dots"; echo SECRET-SGDB >"$old/.config/dots/steamgriddb.key"
echo SECRET-STEAM >"$old/.local/share/Steam/config/config.vdf"; echo cfg >"$old/.local/share/Steam/userdata/42/config/localconfig.vdf"
echo shot >"$old/.local/share/Steam/userdata/42/7/screenshot"
echo note >"$old/.claude/projects/-home-me/memory/MEMORY.md"; echo skill >"$old/.claude/skills/s/SKILL.md"
mkdir -p "$t/gitdrive/.git"; run "$old" personal_save x "$t/gitdrive" >/dev/null 2>&1 && fail "saved into a git repo"
run "$old" personal_save >/dev/null || fail "--save-personal failed"
file=$drive/dotfiles-personal.tar.gpg
[[ -s $file ]] || fail "nothing on the drive"
grep -aq SECRET "$file" && fail "the drive's file can be read without the passphrase"
ls "$t"/personal.* >/dev/null 2>&1 && fail "staged files left in the runtime folder"

new=$t/new; profile "$new" xyz.default-release
mkdir -p "$new/.config/equibop/sessionData" "$new/.config/caelestia"
echo mine >"$new/.config/equibop/sessionData/token"
echo '{"services": {"weatherLocation": ""}}' >"$new/.config/caelestia/shell.json"
echo "wrong" >"$t/pass"
run "$new" personal_main >/dev/null 2>&1 && fail "a wrong passphrase was taken"
[[ $(cat "$new/.config/equibop/sessionData/token") == mine ]] || fail "a wrong passphrase still changed files"
echo "correct horse battery staple" >"$t/pass"
nl=$new/.config/librewolf/librewolf/xyz.default-release
echo stale >"$nl/logins.json-wal"  # the new profile's journal, which would be replayed over the one brought back
run "$new" personal_main >/dev/null || fail "--personal failed"
[[ -e $nl/logins.json-wal ]] && fail "a stale journal left beside a file brought back"
[[ $(cat "$nl/logins.json") == SECRET-LOGIN ]] || fail "LibreWolf's logins not in the new profile"
[[ -f $nl/storage/default/moz-extension+++x/d ]] || fail "extension data missing"
[[ -e $new/.config/librewolf/librewolf/librewolf ]] && fail "LibreWolf's files left under librewolf/"
[[ $(cat "$new/.config/equibop/sessionData/token") == SECRET-TOKEN ]] || fail "Discord's login not back"
[[ -e $new/.config/equibop/sessionData/Cache ]] && fail "a cache came along"
[[ $(cat "$new/.local/share/keyrings/login.keyring") == SECRET-KEYRING ]] || fail "keyring not back"
[[ $(cat "$new/.cache/lutris/.bnet.auth") == SECRET-BNET ]] || fail "Lutris login not back"
[[ $(jq -r .services.weatherLocation "$new/.config/caelestia/shell.json") == Porto ]] || fail "weather place not back"
[[ -e $new/weather-location ]] && fail "weather-location left in the home"
[[ $(cat "$new/.local/share/Steam/config/config.vdf") == SECRET-STEAM && -f $new/.local/share/Steam/userdata/42/config/localconfig.vdf ]] || fail "Steam's login not back"
[[ $(cat "$new/.config/dots/steamgriddb.key") == SECRET-SGDB ]] || fail "SteamGridDB's key not back"
[[ -e $new/.local/share/Steam/userdata/42/7 ]] && fail "more of Steam's userdata than its settings came along"
[[ $(cat "$new/.claude/.credentials.json") == SECRET-CLAUDE && -f $new/.claude.json ]] || fail "Claude Code's account not back"
[[ -f $new/.claude/projects/-home-me/memory/MEMORY.md && -f $new/.claude/skills/s/SKILL.md ]] || fail "Claude Code's memories or skills not back"
grep -rqx mine "$new"/.dotfiles-backup/*-personal/.config/equibop/sessionData/token 2>/dev/null || fail "replaced file not backed up"

# without the drive's file
bare=$t/bare; mkdir -p "$bare/.config/caelestia" "$t/empty"
echo '{"services": {"weatherLocation": "Porto"}}' >"$bare/.config/caelestia/shell.json"
run "$bare" personal_main true "$t/empty" </dev/null >/dev/null 2>&1 && fail "signing in ran with no terminal"
run "$bare" personal_weather <<<"" >/dev/null 2>&1
[[ $(jq -r .services.weatherLocation "$bare/.config/caelestia/shell.json") == Porto ]] || fail "Enter didn't keep the place"
run "$bare" personal_weather <<<"Matosinhos" >/dev/null 2>&1
[[ $(jq -r .services.weatherLocation "$bare/.config/caelestia/shell.json") == Matosinhos ]] || fail "the place typed wasn't set"
# shell.json not valid JSON: said, the step goes on, no temp file left
echo '{ broken' >"$bare/.config/caelestia/shell.json"
out=$(run "$bare" personal_weather <<<"Lisbon" 2>&1) || fail "a broken shell.json stopped the step: $out"
[[ $out == *"isn't valid JSON"* && ! -e $bare/.config/caelestia/shell.json.tmp ]] || fail "a broken shell.json not said, or its temp file left: $out"
echo "ok agros-personal-restore"
