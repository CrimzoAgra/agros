#!/usr/bin/env bash
# claude-notify (Claude Code's Stop hook): no notification while Capri's window is focused (her chat is open); else one
# titled with the project folder and the answer's start, whatever that starts with ("- " a list: notify-send took it
# for options), cut at 200 characters, not bytes
set -euo pipefail
. "$(dirname "$0")/lib.sh"
mkdir -p "$t/bin"
printf '#!/bin/sh\necho "{\\"class\\": \\"$FOCUSED\\"}"\n' >"$t/bin/hyprctl"
# (notify-send as GLib reads its options: "--" ends them, any other argument starting with "-" is one)
cat >"$t/bin/notify-send" <<EOF
#!/usr/bin/env bash
args=()
while ((\$#)); do
    case \$1 in --) shift; args+=("\$@"); break ;; -a|-i) shift 2 ;; -*) echo "Unknown option \$1" >&2; exit 1 ;; *) args+=("\$1"); shift ;; esac
done
printf '%s\n' "\${args[@]}" >"$t/sent"
EOF
chmod +x "$t/bin/"*
notify() { rm -f "$t/sent"; FOCUSED=$1 PATH=$t/bin:$PATH LC_ALL=C "$here/.local/bin/claude-notify" <<<"$2"; }

notify "Capri Desktop" '{"cwd": "/home/me/proj", "last_assistant_message": "hi"}' || fail "failed with Capri focused"
[[ ! -e $t/sent ]] || fail "notified while Capri's chat was open"
notify foot '{"cwd": "/home/me/proj", "last_assistant_message": "- first\n\n  - second"}' || fail "an answer starting with a list"
[[ $(sed -n 1p "$t/sent") == "Capri: proj" && $(sed -n 2p "$t/sent") == "- first - second" ]] || fail "sent: $(cat "$t/sent")"
long=$(printf 'a%.0s' {1..199})çã
notify foot "{\"cwd\": \"/p\", \"last_assistant_message\": \"$long\"}" || fail "a long answer"
body=$(sed -n 2p "$t/sent")
iconv -f UTF-8 -t UTF-8 <<<"$body" >/dev/null 2>&1 || fail "the body was cut inside a letter"
[[ $body == "$(printf 'a%.0s' {1..199})ç" ]] || fail "not cut at 200 characters: $body"
notify foot '{"cwd": "/p"}' && [[ $(sed -n 2p "$t/sent") == Done ]] || fail "no answer text: not \"Done\""
# A Claude Code without last_assistant_message: the last answer's text from the conversation's file
printf '%s\n' '{"type": "assistant", "message": {"content": [{"type": "text", "text": "older"}]}}' \
    '{"type": "user", "message": {"content": "next"}}' \
    '{"type": "assistant", "message": {"content": [{"type": "tool_use", "name": "Bash"}, {"type": "text", "text": "the last"}]}}' \
    >"$t/transcript.jsonl"
notify foot "{\"cwd\": \"/p\", \"transcript_path\": \"$t/transcript.jsonl\"}" && [[ $(sed -n 2p "$t/sent") == "the last" ]] ||
    fail "no last_assistant_message: the conversation's last answer not used: $(cat "$t/sent")"

# agros-welcome wires it as Claude Code's Stop hook: added beside the settings and hooks there, once
mkdir -p "$t/home/.claude"
echo '{"model": "opus", "hooks": {"Stop": [{"hooks": [{"type": "command", "command": "other-hook"}]}], "PreToolUse": []}}' \
    >"$t/home/.claude/settings.json"
hook() { HOME=$t/home CLAUDE_CONFIG_DIR='' bash -c 'source "$1"; claude_notify_hook' _ "$here/.local/bin/agros-welcome"; }
hook >/dev/null; hook >/dev/null
s=$t/home/.claude/settings.json
[[ $(jq -r .model "$s") == opus && $(jq -c .hooks.PreToolUse "$s") == "[]" ]] || fail "other settings not kept: $(cat "$s")"
[[ $(jq -r '[.hooks.Stop[].hooks[].command] | join(" ")' "$s") == "other-hook $t/home/.local/bin/claude-notify" ]] ||
    fail "the Stop hook not added once beside the other: $(cat "$s")"
rm "$s"; hook >/dev/null
[[ $(jq -r '.hooks.Stop[0].hooks[0] | "\(.type) \(.command)"' "$s") == "command $t/home/.local/bin/claude-notify" ]] ||
    fail "no settings yet: the hook not added: $(cat "$s")"
echo 'not json' >"$s"; hook >/dev/null
[[ $(cat "$s") == "not json" ]] || fail "settings that aren't JSON overwritten"
# Settings of another shape (hooks or its Stop list odd): left untouched, said, and the step goes on (set -e)
for odd in '{"hooks": {"Stop": {}}}' '{"hooks": []}' '{"hooks": {"Stop": ["x"]}}' '{"hooks": {"Stop": [{"hooks": {}}]}}' '[]'; do
    echo "$odd" >"$s"
    out=$(HOME=$t/home CLAUDE_CONFIG_DIR='' bash -c 'set -euo pipefail; source "$1"; claude_notify_hook; echo carried on' _ \
        "$here/.local/bin/agros-welcome" 2>&1) || fail "settings $odd ended the step: $out"
    [[ $out == *"carried on" && $out == *"!!"* && $(cat "$s") == "$odd" ]] || fail "settings $odd: $out / $(cat "$s")"
done
echo "ok claude-notify"
