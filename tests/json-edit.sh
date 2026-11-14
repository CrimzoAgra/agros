#!/usr/bin/env bash
# json-edit: a missing file started as {}; an empty one (Caelestia mid-rewrite) or one that isn't JSON left as it is,
# exit 1, after trying again; --lock runs a command under the file's lock, a json-edit inside it not waiting on it
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
je=$here/.local/bin/json-edit f=$t/dir/s.json
# shellcheck disable=SC2016  # (jq's own variables)
"$je" "$f" --arg v x '.a = $v' || fail "a missing file"
[[ $(jq -c . "$f") == '{"a":"x"}' ]] || fail "a missing file not started as {}: $(cat "$f")"
: >"$f"
"$je" "$f" '.b = 1' && fail "an empty file reported changed"
[[ -e $f && ! -s $f ]] || fail "an empty file replaced: $(cat "$f")"
echo '{"a": ' >"$f"
"$je" "$f" '.b = 1' && fail "a file that isn't JSON reported changed"
[[ $(cat "$f") == '{"a": ' ]] || fail "a file that isn't JSON replaced: $(cat "$f")"
[[ ! -e $f.tmp ]] || fail "its temporary file left behind"
# Empty while Caelestia rewrites it, whole again by the second try: changed, the settings kept
: >"$f"; (sleep 0.4; echo '{"keep": 1}' >"$f") &
"$je" "$f" '.b = 1' || fail "a file whole again by the next try"
wait
[[ $(jq -c . "$f") == '{"keep":1,"b":1}' ]] || fail "the file whole again: $(cat "$f")"
# --lock: the command under the lock (another json-edit waits for it), one inside it doesn't wait on it
timeout 5 "$je" --lock "$f" sh -c 'sleep 0.5; "$1" "$2" ".c = 1"' _ "$je" "$f" & sleep 0.2
timeout 5 "$je" "$f" '.d = .c' || fail "after --lock's command"
wait
[[ $(jq -c . "$f") == '{"keep":1,"b":1,"c":1,"d":1}' ]] || fail "--lock: not run under the lock: $(cat "$f")"
# A link stays a link (its target changed), and the file's mode is kept
echo '{}' >"$t/target.json"; chmod 600 "$t/target.json"; ln -s "$t/target.json" "$t/link.json"
"$je" "$t/link.json" '.e = 1' || fail "a linked file not changed"
[[ -L $t/link.json && $(jq -c . "$t/target.json") == '{"e":1}' ]] || fail "a link replaced by a file, or its target not changed"
[[ $(stat -c %a "$t/target.json") == 600 ]] || fail "the file's mode not kept: $(stat -c %a "$t/target.json")"
echo "ok json-edit"
