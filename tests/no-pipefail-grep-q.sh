#!/usr/bin/env bash
# Lint: under pipefail, a pipeline into a reader that stops early (grep -q, which exits at its first match) fails when
# the writer is still writing: it dies of SIGPIPE, the pipeline's status is its 141, and "found" reads as "not found"
# (a running Proton taken for a stopped one and removed under a game). It kept coming back, so every shell script in
# the repo that sets pipefail is checked: no pipeline ends in grep -q (-q in any cluster, --quiet, --silent): read the
# output whole instead (grep -q ... <<<"$(writer)", or grep without -q >/dev/null). Readers that stop early only as
# their job (head, grep -m/--max-count) are flagged only where the pipeline's status decides something: a condition
# (if, while, until, !, &&, ||, but || true and || :) or, under set -e, a statement of its own or an assignment's
# whole value. A line (or the statement's first line) with "# pipefail-ok: <why>" is let through.
#   tests/no-pipefail-grep-q.sh [<file>...]   the repo's scripts, or those files
set -uo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
lint() {
    python3 -I - "$@" <<'PY'
import os, re, sys

def mask(src):
    """The code alone: quoted text, comments and here-documents blanked (same length, newlines kept), a command
    substitution's code kept (in double quotes too). Returns the masked text and each "(" -> its ")" (with its kind)."""
    out = list(src)
    n = len(src)
    stack = []      # ('dq',) for a double quote, ('sub', open_pos) for $( , ('par', open_pos) for (
    pairs = {}      # open pos -> (close pos, kind)
    heredocs = []   # delimiters waiting for the next newline
    i = 0
    def blank(a, b):
        for k in range(a, b):
            if out[k] != '\n':
                out[k] = ' '
    in_dq = lambda: stack and stack[-1][0] == 'dq'
    while i < n:
        c = src[i]
        if in_dq():
            if c == '\\':
                blank(i, min(i + 2, n)); i += 2; continue
            if c == '"':
                stack.pop(); i += 1; continue
            if src.startswith('$(', i) and not src.startswith('$((', i):
                stack.append(('sub', i + 1)); i += 2; continue
            if c != '\n':
                out[i] = '_'
            i += 1; continue
        if c == '\\':
            if i + 1 < n and src[i + 1] == '\n':
                pass   # a continued line: kept as it is (cont() reads it as one line)
            else:
                blank(i + 1, min(i + 2, n))
            i += 2; continue
        if c == '#' and (i == 0 or src[i - 1] in ' \t\n;|&()'):
            j = src.find('\n', i)
            j = n if j < 0 else j
            blank(i, j); i = j; continue
        if c == "'" or src.startswith("$'", i):
            s = i + (2 if c == '$' else 1)
            j = s
            while j < n and src[j] != "'":
                j += 2 if (c == '$' and src[j] == '\\') else 1
            for k in range(s, min(j, n)):
                if out[k] != '\n':
                    out[k] = '_'
            i = j + 1; continue
        if c == '"':
            stack.append(('dq',)); i += 1; continue
        if src.startswith('$((', i):
            stack.append(('par', i + 1)); i += 2; continue   # arithmetic: its own "(", matched as one
        if src.startswith('$(', i):
            stack.append(('sub', i + 1)); i += 2; continue
        if c in '<>' and i + 1 < n and src[i + 1] == '(':
            stack.append(('proc', i + 1)); i += 2; continue
        if c == '(':
            stack.append(('par', i)); i += 1; continue
        if c == ')':
            # (a case pattern's ")" closes nothing: popped only when one is open)
            if stack and stack[-1][0] in ('sub', 'par', 'proc'):
                kind, o = stack.pop()
                pairs[o] = (i, kind)
            i += 1; continue
        m = re.match(r'<<(-?)\s*([\'"]?)([A-Za-z_][A-Za-z0-9_]*)\2', src[i:]) if src.startswith('<<', i) and not src.startswith('<<<', i) else None
        if m:
            heredocs.append((m.group(3), m.group(1) == '-'))
            i += m.end(); continue
        if c == '\n' and heredocs:
            j = i + 1
            for word, tabs in heredocs:
                while j < n:
                    e = src.find('\n', j)
                    e = n if e < 0 else e
                    line = src[j:e]
                    blank(j, e)
                    j = e + 1
                    if (line.lstrip('\t') if tabs else line) == word:
                        break
            heredocs = []
            i = j; continue
        i += 1
    return ''.join(out), pairs

READER = re.compile(r'(?<![|>])\|&?(?!\|)[\s]*((?:[A-Za-z_][A-Za-z0-9_]*=\S*\s+|command\s+|env\s+)*)(?:\S*/)?(e?grep|fgrep|head)\b([^|;&)\n]*)')

def quiet(args):
    for w in args.split():
        if w == '--':
            break
        if w in ('--quiet', '--silent'):
            return True
        if re.fullmatch(r'-[A-Za-z0-9]+', w):
            for ch in w[1:]:
                if ch == 'q':
                    return True
                if ch in 'efmABCdD':
                    break
    return False

def max_count(args):
    for w in args.split():
        if w == '--':
            break
        if w.startswith('--max-count'):
            return True
        if re.fullmatch(r'-[A-Za-z0-9]+', w):
            for ch in w[1:]:
                if ch == 'm':
                    return True
                if ch in 'efABCdD':
                    break
    return False

def cont(code, k):
    """The newline at k continues the statement: after a "|", "&&", "||" or a backslash"""
    return code[:k].rstrip(' \t').endswith(('|', '&&', '||', '\\'))

def statement_start(code, pos, lo):
    """Where the statement holding pos starts (after the last separator before it, from lo), and that separator."""
    k = pos
    while k > lo:
        k -= 1
        ch = code[k]
        if ch == '\n' or ch == ';' or ch == '{' or ch == '(':
            if ch == '\n' and cont(code, k):
                continue
            return k + 1, ch
        if code.startswith('&&', k - 1) or code.startswith('||', k - 1):
            return k + 1, code[k - 1:k + 1]
    return lo, ''

def statement_end(code, pos, hi):
    k = pos
    while k < hi:
        ch = code[k]
        if ch == '\n':
            if cont(code, k):
                k += 1; continue
            return k, ''
        if ch in ';)}':
            return k, ch
        if code.startswith('&&', k) or code.startswith('||', k):
            return k, code[k:k + 2]
        k += 1
    return hi, ''

def ignored_after(code, k):
    return re.match(r'\s*\|\|\s*(true|:)\b', code[k:]) is not None

def status_used(code, pairs, pos, errexit):
    # the innermost "(" around pos
    inner = None
    for o, (c, kind) in pairs.items():
        if o < pos < c and (inner is None or o > inner[0]):
            inner = (o, c, kind)
    if inner and inner[2] == 'proc':
        return False
    lo = inner[0] + 1 if inner else 0
    hi = inner[1] if inner else len(code)
    start, sep = statement_start(code, pos, lo)
    end, esep = statement_end(code, pos, hi)
    head = code[start:pos].lstrip()
    if re.match(r'(if|elif|while|until|!)\b', head) or sep in ('&&', '||'):
        return True
    if esep in ('&&', '||'):
        return not ignored_after(code, end)
    if inner and inner[2] == 'sub':
        if code[end:hi].strip(' \t\n;'):
            return False          # not the substitution's last statement: its status is lost
        o, c, _ = inner
        start, _sep = statement_start(code, o - 1, 0)
        before = code[start:o - 1]
        if not re.fullmatch(r'\s*[A-Za-z_][A-Za-z0-9_]*(\[[^\]]*\])?\+?=', before):
            return False          # the substitution's status is lost in a command's words (local x=$(...) too)
        after = code[c + 1:]
        if re.match(r'\s*(&&|\|\|)', after):
            return not ignored_after(code, c + 1)
        return errexit and re.match(r'[ \t]*(\n|;|$|\)|\})', after) is not None
    return errexit

def check(path):
    try:
        src = open(path, encoding='utf-8', errors='replace').read()
    except OSError:
        return []
    code, pairs = mask(src)
    if not re.search(r'(^|[;\s])(set\s+(-[A-Za-z]*o\s+pipefail|-o\s+pipefail)|shopt\s+-so\s+pipefail)', code, re.M):
        return []
    errexit = re.search(r'(^|[;\s])set\s+(-[A-Za-z]*e[A-Za-z]*\b|-o\s+errexit)', code, re.M) is not None
    lines = src.split('\n')
    hits = []
    for m in READER.finditer(code):
        prog, args = m.group(2), m.group(3)
        pos = m.start()
        bad = None
        if prog != 'head' and quiet(args):
            bad = 'grep -q'
        elif (prog == 'head' or max_count(args)) and status_used(code, pairs, pos, errexit):
            bad = prog + (' -m' if prog != 'head' else '')
        if not bad:
            continue
        ln = code.count('\n', 0, pos)
        first = code.count('\n', 0, statement_start(code, pos, 0)[0])
        if any('# pipefail-ok:' in lines[k] for k in range(max(first - 1, 0), ln + 1)):
            continue
        hits.append('%s:%d: a pipeline into %s under pipefail: %s' % (path, ln + 1, bad, lines[ln].strip()))
    return hits

def scripts(root):
    for d, dirs, files in os.walk(root):
        dirs[:] = [x for x in dirs if x not in ('.git', 'node_modules')]
        for f in files:
            p = os.path.join(d, f)
            if f.endswith(('.sh', '.install')) or f == 'PKGBUILD':
                yield p; continue
            try:
                with open(p, 'rb') as h:
                    first = h.readline(200)
            except OSError:
                continue
            if re.match(rb'#!.*\b(ba|da|k|z)?sh\b', first):
                yield p

paths = sys.argv[1:]
if len(paths) == 1 and os.path.isdir(paths[0]):
    paths = sorted(scripts(paths[0]))
found = [h for p in paths for h in check(p)]
print('\n'.join(found))
sys.exit(1 if found else 0)
PY
}

# The lint itself: what it must catch, and what it must let through
cat >"$t/bad" <<'S'
#!/bin/bash
set -euo pipefail
ps -eo args= | grep -qF x && echo running
if pacman -Slq agros 2>/dev/null | grep -qxF "$p"; then :; fi
printf '%s\n' a b |
    grep -Eq a || echo no
v=$(git tag -l | head -1)
x=$(ps | grep -m1 foo) || exit 1
echo "$(id -nG | grep -wq wheel && echo yes)"
S
cat >"$t/good" <<'S'
#!/bin/bash
set -uo pipefail
grep -qF x <<<"$(ps -eo args=)" && echo running
ps -eo args= | grep -F x >/dev/null
[[ $a || $b ]] && grep -q x file
echo "a | grep -q b" 'c | grep -q d'
# ps | grep -q comment
v=$(git tag -l | head -1)
f "$(find . | head -3)"
lint=$(command -v a b | head -1) || true
while read -r l; do :; done < <(ls | head -2)
cat <<EOF
ps | grep -q heredoc
EOF
ps | grep -q y  # pipefail-ok: the test's own
S
printf '#!/bin/sh\nps | grep -q x\n' >"$t/no-pipefail"
out=$(lint "$t/bad")
[[ $(wc -l <<<"$out") == 6 ]] || fail "the lint missed a pipeline into an early reader: $out"
out=$(lint "$t/good" "$t/no-pipefail") || fail "the lint flagged what's sound: $out"

# The repo's scripts (or those named)
(($#)) || set -- "$here"
out=$(lint "$@") || fail "$(wc -l <<<"$out") pipeline(s) into an early reader under pipefail (read the output whole):
$out"
echo "ok no-pipefail-grep-q"
