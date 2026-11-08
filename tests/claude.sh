#!/usr/bin/env bash
# ~/.local/bin/claude: the editor extension's CLI (its newest version); with no extension the next claude on PATH (not
# itself again, under its own name or a link), and with neither said, not run in a loop
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
fail() { echo "FAIL: $*"; exit 1; }
mkdir -p "$t/home/.local/bin" "$t/other"
ln -s "$here/.local/bin/claude" "$t/home/.local/bin/claude"  # (as setup installs it: a copy or a link, on PATH first)
printf '#!/bin/sh\necho "other $*"\n' >"$t/other/claude"; chmod +x "$t/other/claude"
run() { HOME=$t/home PATH=$t/home/.local/bin:$here/.local/bin:$1:/usr/bin:/bin "$t/home/.local/bin/claude" --version 2>&1; }
for v in 2.1.9 2.1.10; do
    d=$t/home/.vscode-oss/extensions/anthropic.claude-code-$v-linux-x64/resources/native-binary
    mkdir -p "$d"; printf '#!/bin/sh\necho "extension %s $*"\n' "$v" >"$d/claude"; chmod +x "$d/claude"
done
[[ $(run "$t/other") == "extension 2.1.10 --version" ]] || fail "not the extension's newest CLI: $(run "$t/other")"
rm -r "$t/home/.vscode-oss"
[[ $(run "$t/other") == "other --version" ]] || fail "no extension: not the other claude on PATH: $(run "$t/other")"
out=$(timeout 10 bash -c "$(declare -f run); t=$t here=$here; run $t/none") && fail "with no Claude Code at all it succeeded: $out"
[[ $out == *"isn't installed"* ]] || fail "with no Claude Code at all, not said: $out"
echo "ok claude"
