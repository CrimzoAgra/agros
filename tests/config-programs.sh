#!/usr/bin/env bash
# What the desktop's configs run is there: every program the Hyprland config (hl.exec_cmd, its login starts, io.popen),
# the user units (Exec*=), the Quickshell apps (command:, execDetached) and Caelestia's settings (the Super menu's
# actions) run. One of ~/.local/bin is a script in .local/bin; any other comes with a package agros-desktop installs, or
# the base system (the table below: a new one is added there with its package, one no longer run taken out). Every unit
# Lua starts is in .config/systemd/user, the apps the default apps and the dock's pins name are installed, and so is each
# package Caelestia's manifest lists for the parts of its dots AgrOS takes. A package dropped from agros-desktop, or a
# script renamed, while a config still runs it, fails here, not as a login start, a key or a button that does nothing
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
# Caelestia's own Hyprland config too, at the commit agros-hyprland-settings pins: its keys' and login starts' programs,
# with the apps its variables name (hypr-vars.lua's over its own: Super+W's browser...)
dots=$(sed -n 's/^_dots=//p' "$here/packages/agros-hyprland-settings/PKGBUILD")
if git init -q "$t/dots" && git -C "$t/dots" fetch -q --depth 1 https://github.com/caelestia-dots/caelestia "$dots" 2>/dev/null; then
    git -C "$t/dots" checkout -q FETCH_HEAD
    dots=$t/dots
else
    skipped "Caelestia's dots couldn't be fetched: its own keys' programs not checked"
    dots=""
fi
python3 -I - "$here" "$dots" <<'P'
import glob, json, os, re, shlex, sys
here, dots = sys.argv[1], sys.argv[2]

# program -> its package; "optional:" one that isn't always installed (each place that runs it says why that's fine)
PROGRAMS = {
    "btop": "btop", "df": "coreutils", "fish": "fish", "flock": "util-linux", "foot": "foot",
    "gtk-launch": "gtk3", "head": "coreutils", "hyprctl": "hyprland", "journalctl": "systemd", "nmcli": "networkmanager", "qs": "quickshell-git", "readlink": "coreutils",
    "sh": "bash", "sleep": "coreutils", "systemctl": "systemd", "cat": "coreutils",
    "mkdir": "coreutils", "mv": "coreutils", "timeout": "coreutils", "md5sum": "coreutils",
    "caelestia": "caelestia-cli", "loginctl": "systemd",
    # (the widgets' GPU meter: only with NVIDIA's driver loaded, which brings it)
    "nvidia-smi": "optional:nvidia-utils",
    # (its login start is off by default: agros-welcome --system installs it with a Logitech device plugged in)
}
# ...and Caelestia's
CAELESTIA = {
    "gnome-keyring-daemon": "gnome-keyring", "polkit-gnome-authentication-agent-1": "polkit-gnome",
    "wl-paste": "wl-clipboard", "trash-empty": "trash-cli", "gsettings": "glib2", "agent": "geoclue",
    "gammastep": "gammastep", "mpris-proxy": "bluez-utils", "hyprpicker": "hyprpicker", "wpctl": "wireplumber",
    "pkill": "procps-ng", "ydotool": "ydotool", "cliphist": "cliphist", "notify-send": "libnotify",
    "codium": "vscodium", "thunar": "thunar", "pwvucontrol": "pwvucontrol", "librewolf": "librewolf",
}
if dots:
    PROGRAMS.update(CAELESTIA)
# Always there (the base system), and a package another one of agros-desktop's brings (gtk3, glib2: Thunar's)
BASE = {"bash", "coreutils", "util-linux", "systemd", "procps-ng"}
PULLED = {"gtk3": "thunar", "glib2": "thunar"}
pkgbuild = open(f"{here}/packages/agros-desktop/PKGBUILD").read()
depends = set(re.sub(r"#.*", "", re.search(r"^depends=\((.*?)^\)", pkgbuild, re.S | re.M).group(1)).split())
failures = []

# A Lua or JS call's arguments from the "(" or "[" at i: string literals as they are (a JS template's ${...} and any
# expression joined to them, Lua's "..", as X), each top-level argument one string
def arguments(src, i, close):
    args, cur, depth, i = [], "", 0, i + 1
    while i < len(src):
        ch = src[i]
        if ch in "\"'`":
            q, i, s = ch, i + 1, ""
            while src[i] != q:
                if src[i] == "\\":
                    s += {"n": "\n"}.get(src[i + 1], src[i + 1]); i += 2; continue
                if q == "`" and src.startswith("${", i):
                    d, i = 1, i + 2
                    while d:
                        d += {"{": 1, "}": -1}.get(src[i], 0); i += 1
                    s += "X"; continue
                s += src[i]; i += 1
            # (a string inside an expression, os.getenv("HOME"): the expression's X)
            cur += s if not depth else ""
        elif ch in "([{":
            depth += 1; cur += "X" if depth == 1 and not cur.endswith("X") else ""
        elif ch in ")]}" and depth:
            depth -= 1
        elif ch in ")]" and ch == close:
            args.append(cur); return args
        elif ch == "," and not depth:
            args.append(cur); cur = ""
        elif not ch.isspace() and not src.startswith("..", i) and not depth and not cur.endswith("X"):
            cur += "X"
        i += 2 if src.startswith("..", i) else 1
    return args

# Words before a command (the next word is one), and the shell's own commands (no package)
KEYWORDS = {"if", "then", "else", "elif", "fi", "while", "until", "do", "done", "!", "{", "}", "exec"}
BUILTINS = {"[", "test", ":", "echo", "printf", "exit", "wait", "kill", "true", "false", "cd", "set", "export", "for",
            "unset", "read", "return", "local", "continue", "break"}
SEPARATORS = {";", "&&", "||", "|", "&", "(", ")", "\n", ";;"}
# Each program a shell command line runs (where): sh -c's script and $(...) inside it too, and what a wrapper runs
def programs(line, where):
    try:
        lex = shlex.shlex(line, posix=True, punctuation_chars=True)
        lex.whitespace_split = True
        words = list(lex)
    except ValueError as e:
        failures.append(f"{where}: can't read {line!r} ({e})"); return
    for w in words:
        for sub in re.findall(r"\$\(([^()]*)\)", w):
            programs(sub, where)
    first, in_case, k = True, None, 0
    while k < len(words):
        w = words[k]; k += 1
        # (case's word, its patterns up to ")", each branch's commands up to ";;")
        if in_case == "word":
            in_case = "pattern" if w == "in" else "word"; continue
        if in_case == "pattern":
            if w == ")": in_case, first = "branch", True
            elif w == "esac": in_case = None
            continue
        if in_case == "branch" and w == ";;":
            in_case = "pattern"; continue
        if w == "esac":
            in_case = None; continue
        if w in SEPARATORS:
            first = True; continue
        if re.fullmatch(r"[<>]+&?|&>", w):
            k += 1; continue  # (a redirection: its target)
        if not first or w in KEYWORDS or re.fullmatch(r"\w+=.*", w):
            continue
        first = False
        if w == "case":
            in_case = "word"; continue
        m = re.fullmatch(r"(?:~|\$HOME|\$\{HOME\}|%h|X)/\.local/bin/([\w.+-]+)", w)
        if not m and (w in BUILTINS or w.startswith("$") or w[:1].isdigit() or w == "X" or w.startswith("X/")):
            continue  # (the shell's own, or a variable's: not known here)
        name = m.group(1) if m else os.path.basename(w) if w.startswith("/") else w
        # (a bare name in .local/bin is that script: ~/.local/bin comes first on the desktop's PATH)
        if m and not os.path.isfile(f"{here}/.local/bin/{name}"):
            failures.append(f"{where}: runs ~/.local/bin/{name}, which isn't in .local/bin")
        elif not m and not os.path.isfile(f"{here}/.local/bin/{name}"):
            seen.add(name)
            if name not in PROGRAMS:
                failures.append(f"{where}: runs {name}: not in this test's list of programs and their packages")
        # What a wrapper runs: the rest of its command (to the next separator) is a command of its own
        j = k
        while j < len(words) and words[j] not in SEPARATORS:
            j += 1
        rest = words[k:j]
        if name in {"sh", "bash"} and rest[:1] == ["-c"] and len(rest) > 1:
            programs(rest[1], where)
        elif name == "fish" and rest[:1] in (["-c"], ["-C"]) and len(rest) > 1:
            programs(rest[1], where)
        elif name in {"app-launch", "env", "setsid", "nice", "flock", "timeout", "foot"}:
            # (their own options and, flock's lock file, timeout's time, foot's -a/-T values, before the command)
            while rest and (rest[0].startswith("-") or re.fullmatch(r"\w+=.*", rest[0])):
                rest = rest[2:] if name == "foot" and rest[0] in {"-a", "-T", "-o", "-c", "-W", "-w", "-D"} else rest[1:]
            if name in {"flock", "timeout"}:
                rest = rest[1:]
            if rest:
                programs(shlex.join(rest), where)
        k = j

seen = set()
lua = sorted(glob.glob(f"{here}/.config/caelestia/**/*.lua", recursive=True))
for f in lua + (sorted(glob.glob(f"{dots}/hypr/**/*.lua", recursive=True)) if dots else []):
    src = open(f).read()
    rel = "Caelestia's " + os.path.relpath(f, dots) if dots and f.startswith(dots) else os.path.relpath(f, here)
    for m in re.finditer(r"\b(hl\.exec_cmd|io\.popen|at_login|hl\.dsp\.exec_cmd)\(", src):
        line = src.count("\n", 0, m.start()) + 1
        args = arguments(src, m.end() - 1, ")")
        cmd = args[1] if m.group(1) == "at_login" and len(args) > 1 else args[0] if args else "X"
        if cmd.strip() != "X":  # (a variable: at_login's own exec_cmd(cmd))
            programs(cmd, f"{rel}:{line}")
    # Units it starts are the repo's
    for unit in re.findall(r"systemctl --user start ([\w@.-]+)", src):
        unit = unit if "." in unit else unit + ".service"
        if not os.path.isfile(f"{here}/.config/systemd/user/{unit}"):
            failures.append(f"{rel}: starts {unit}, which isn't in .config/systemd/user")
if dots:
    variables = {}
    for f in (f"{dots}/hypr/variables.lua", f"{here}/.config/caelestia/hypr-vars.lua"):
        variables.update(re.findall(r'^\s*(\w+)\s*=\s*"([^"]*)"', open(f).read(), re.M))
    for name in ("terminal", "browser", "editor", "fileExplorer", "audioSettings", "sleepGestureCmd"):
        programs(variables.get(name, "X"), f"Caelestia's variable {name}")
for f in sorted(glob.glob(f"{here}/.config/systemd/user/*")):
    rel = os.path.relpath(f, here)
    for m in re.finditer(r"^Exec\w*=[-@:+!]*(.*)$", open(f).read(), re.M):
        programs(m.group(1), rel)
    for m in re.finditer(r"^OnFailure=([\w-]+@)", open(f).read(), re.M):
        if not os.path.isfile(f"{here}/.config/systemd/user/{m.group(1)}.service"):
            failures.append(f"{rel}: OnFailure= names {m.group(1)}.service, which isn't there")
for f in sorted(glob.glob(f"{here}/.config/quickshell/**/*.qml", recursive=True)):
    src, rel = open(f).read(), os.path.relpath(f, here)
    src = re.sub(r"\$\{(?:root\.)?home\}|\$\{Quickshell\.env\(\"HOME\"\)\}", "~", src)
    for m in re.finditer(r"(?:\bcommand:\s*|execDetached\(\s*)\[", src):
        line = src.count("\n", 0, m.start()) + 1
        args = [a for a in arguments(src, m.end() - 1, "]")]
        if args and args[0] != "X":
            programs(shlex.join(args), f"{rel}:{line}")

# Caelestia's settings (shell.json): its Super menu's actions and idle steps. Not the ones Caelestia does itself
# (autocomplete, setMode, its session verbs: suspend, logout..., also as "systemctl <verb>")
VERBS = {"autocomplete", "setmode", "logout", "suspend", "suspendthenhibernate", "hibernate", "poweroff", "reboot"}
def shell_json(node, where):
    if isinstance(node, dict):
        for key, value in node.items():
            if key in {"command", "idleAction", "returnAction"} and isinstance(value, list) and value:
                verb = value[1] if value[0] in {"systemctl", "loginctl"} and len(value) == 2 else value[0]
                if re.sub(r"[-_]", "", verb).lower() not in VERBS:
                    programs(shlex.join(value), f"{where} ({key})")
            else:
                shell_json(value, where)
    elif isinstance(node, list):
        for value in node:
            shell_json(value, where)
shell_json(json.load(open(f"{here}/.config/caelestia/shell.json")), ".config/caelestia/shell.json")

# The apps the default apps (mimeapps.list) and the dock's pins name: a launcher entry of the repo's, of a package
# agros-desktop installs, or of a Flatpak agros-welcome installs (by what it's installed from)
ENTRIES = {"librewolf": "librewolf", "thunar": "thunar", "org.gnome.TextEditor": "gnome-text-editor",
           "net.lutris.Lutris": "lutris", "com.nuvio.media.desktop": "flatpak:NuvioMedia/NuvioDesktop"}
welcome = open(f"{here}/.local/bin/agros-welcome").read()
mime = re.findall(r"=(.*)", open(f"{here}/.config/mimeapps.list").read())
pins = re.findall(r'"([^"]+)"', open(f"{here}/.config/quickshell/sidedock/pins.json").read())
for app in [e.removesuffix(".desktop") for l in mime for e in l.split(";") if e] + pins:
    pkg = ENTRIES.get(app, "")
    if os.path.isfile(f"{here}/.local/share/applications/{app}.desktop"):
        continue
    if pkg.startswith("flatpak:") and pkg[8:] in welcome or pkg in depends:
        continue
    failures.append(f"{app}.desktop (mimeapps.list, the dock's pins): no launcher entry of the repo's, nor a package or "
                    "Flatpak AgrOS installs with it")

# Each program's package installed by agros-desktop (or always there); the list holding nothing no config runs
for name, pkg in sorted(PROGRAMS.items()):
    if name not in seen:
        failures.append(f"{name}: no config runs it any more (take it out of this test's list)")
    elif not pkg.startswith("optional:") and pkg not in depends | BASE and PULLED.get(pkg) not in depends:
        failures.append(f"{name}: its package {pkg} isn't in agros-desktop's depends")

# Caelestia's own list of what its configs need (its manifest.toml, at the pinned commit): each package of the
# components AgrOS takes (those its installer takes by default, and those agros-hyprland-settings copies: _components)
# in agros-desktop's depends. A pin moved on to dots that need a new package (a font, a theme, a tool a key runs that
# the program list above can't see) fails here, not as a key, a font or a theme missing after the update
if dots:
    import tomllib
    # (taken by default, but not on AgrOS, each with why; and a package of a component taken, replaced)
    NOT_TAKEN = {"firefox": "LibreWolf in its place, its settings AgrOS's own"}
    REPLACED = {"spotify": "Flathub's, agros-welcome's"}
    manifest = tomllib.load(open(f"{dots}/manifest.toml", "rb"))
    settings = open(f"{here}/packages/agros-hyprland-settings/PKGBUILD").read()
    copied = {c.split("|")[0] for c in shlex.split(re.search(r"^_components=\((.*?)\)", settings, re.M).group(1))}
    for c in manifest.get("components", []):
        entries = {e.get("src") for e in c.get("entries", [])}
        if c["name"] in NOT_TAKEN or not (c.get("default") or entries & copied):
            continue
        for pkg in c.get("packages", []):
            if pkg.startswith("local:") or pkg in REPLACED or pkg in depends:
                continue
            failures.append(f"Caelestia's {c['name']} needs {pkg} (its manifest.toml): not in agros-desktop's depends")
    for pkg in manifest.get("packages", []):
        if pkg not in depends:
            failures.append(f"Caelestia needs {pkg} (its manifest.toml): not in agros-desktop's depends")
if failures:
    print("FAIL: " + "\n".join(failures)); sys.exit(1)
P
echo "ok config-programs"
