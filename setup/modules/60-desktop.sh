# shellcheck shell=bash disable=SC2154  # $repo and $yes come from setup.sh
# about: Caelestia overlay and wallpaper, GTK window buttons off, LibreWolf bookmarks/settings, VSCodium extensions, Claude Code plugins
# scope: user

# Claude Code's plugins, as "GitHub repo of its marketplace|plugin@marketplace"
CLAUDE_PLUGINS=(
    "DietrichGebert/ponytail|ponytail@ponytail"              # minimal code: justifies each line first (needs node)
    "addyosmani/agent-skills|agent-skills@addy-agent-skills" # Addy Osmani's engineering skills
)

module_desktop() {
    command -v caelestia >/dev/null && caelestia_setup
    window_buttons
    firefox_setup
    vscode_extensions
    claude_plugins
}

caelestia_setup() {
    # (run in an && list, so set -e is off in here: a failure said, not left silent)
    if "$HOME/.local/bin/caelestia-overlay"; then
        echo "Caelestia overlay (your changes to Caelestia) built."
    else
        echo "!! The Caelestia overlay didn't build (run: ~/.local/bin/caelestia-overlay)"
    fi
    # Run from the desktop: the running Caelestia keeps the files it loaded (it doesn't see the rebuilt overlay), so
    # it's restarted onto the new ones. Started by Hyprland, with the desktop's environment: from elsewhere (an SSH
    # login) it came up without the icon theme and app list, and the bar lost its logo and app icons
    # (by Quickshell's own list, as dotfiles-check: a shell its crash handler restarted shows no "-c caelestia" in ps).
    # Hyprland named (-i, its first one when this isn't run inside it): from an SSH login or a text console hyprctl
    # doesn't know it, and the restart failed with nothing said
    if qs list --all 2>/dev/null | grep -q "/quickshell/caelestia/shell.qml" &&
        hyprctl -i "${HYPRLAND_INSTANCE_SIGNATURE:-0}" dispatch 'hl.dsp.exec_cmd("~/.local/bin/caelestia-restart")' >/dev/null 2>&1; then
        echo "Caelestia restarted with them."
    fi
    # Only the first time (its own mark, not Caelestia's wallpaper file, which Caelestia may have written already): run
    # again (after a pull), it would replace the wallpaper and colours you've picked since
    local mark="$HOME/.local/state/dotfiles-wallpaper-set"
    if [[ -e $mark ]]; then
        echo "Wallpaper and colours left as you have them."
        return 0
    fi
    # Then the colours from it (Caelestia starts on its fixed teal scheme). In that order: the dynamic scheme is refused
    # while no wallpaper is set ("No wallpaper set"), and a fresh install kept the teal accent.
    # Hyprland named for the CLI too (the same first one as -i 0): it asks Hyprland whether its config is Lua, and from an
    # SSH login or a text console wrote the window borders' colours to current.conf, which the Lua config doesn't read
    local sig=${HYPRLAND_INSTANCE_SIGNATURE:-$(hyprctl instances -j 2>/dev/null | jq -r '.[0].instance // empty' 2>/dev/null)}
    if HYPRLAND_INSTANCE_SIGNATURE=$sig caelestia wallpaper -f "$HOME/Pictures/Wallpapers/wallpaper.jpg" 2>/dev/null; then
        if HYPRLAND_INSTANCE_SIGNATURE=$sig caelestia scheme set -n dynamic >/dev/null 2>&1; then
            echo "Wallpaper and colours set."
        else
            echo "!! Wallpaper set, but not its colours (run: caelestia scheme set -n dynamic)"
        fi
        mkdir -p "${mark%/*}" && touch "$mark"
    else
        echo "Wallpaper will be set from inside Caelestia (run: caelestia wallpaper -f ~/Pictures/Wallpapers/wallpaper.jpg)"
    fi
}

# No window buttons drawn by GTK apps (LibreWolf too, and apps installed later): the title bars on floating windows have
# them (.config/caelestia/user/titlebars.lua)
window_buttons() {
    gsettings set org.gnome.desktop.wm.preferences button-layout 'appmenu:' 2>/dev/null || true
}

# The default LibreWolf profile's folder (nothing if LibreWolf hasn't made one yet)
firefox_profile() {
    "$repo/.local/bin/firefox-bookmarks-export" --profile 2>/dev/null || true
}

# LibreWolf bookmarks and settings (Firefox Sync brings the extensions, not these).
# Bookmarks: .local/share/firefox/bookmarks.html when there (not in the AgrOS repo: your bookmarks are personal, and come
# back with the LibreWolf profile from your pen drive, agros-personal), read by LibreWolf at its next start (browser.places.importBookmarksHTML),
# which then turns that off itself. Settings: .local/share/firefox/settings.js, added once to the profile's prefs (not a
# user.js, so you can still change them in LibreWolf afterwards).
firefox_setup() {
    local file="$HOME/.local/share/firefox/bookmarks.html" settings="$HOME/.local/share/firefox/settings.js" prof pid
    command -v librewolf >/dev/null && [[ -f $settings ]] || return 0
    # The temporary policies file below, with its mark beside it ($LIBREWOLF_POLICIES: elsewhere, for the tests). One a
    # run cut off where nothing could take it away (a power cut) left: taken away now, else it replaced LibreWolf's
    # own policies for good
    local pol=${LIBREWOLF_POLICIES:-/etc/librewolf/policies/policies.json} temp=
    if [[ -e $pol.dotfiles-temporary ]] && sudo -n true 2>/dev/null; then
        sudo rm -f "$pol" "$pol.dotfiles-temporary" && sudo rmdir -p --ignore-fail-on-non-empty "${pol%/*}" 2>/dev/null || true
        echo "Took away the temporary LibreWolf policies file an earlier run left ($pol)."
    fi
    if pgrep -x librewolf >/dev/null; then
        echo "Close LibreWolf to import the bookmarks and settings (or run: ./setup.sh --only desktop)."
        return 0
    fi
    prof=$(firefox_profile)
    if [[ -z $prof ]]; then
        # The Lagoon theme (settings.js picks it) isn't part of LibreWolf: it comes from addons.mozilla.org when picked.
        # A new profile gets it installed by a policy, for this first start only: a policies file in /etc replaces
        # LibreWolf's own (telemetry off...), so it's theirs plus the install, and removed again after
        # (its mark first: cut off from here on, the next run finds it)
        if [[ ! -e $pol ]] && sudo -n true 2>/dev/null && sudo install -Dm644 /dev/null "$pol.dotfiles-temporary"; then
            python3 - /usr/lib/librewolf/distribution/policies.json <<'EOF' | sudo install -Dm644 /dev/stdin "$pol" && temp=1
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except (OSError, ValueError):
    d = {"policies": {}}
d["policies"].setdefault("Extensions", {}).setdefault("Install", []).append(
    "https://addons.mozilla.org/firefox/downloads/latest/nova-lagoon/latest.xpi")
print(json.dumps(d))
EOF
            # (not written: its mark taken away now, or a policies file put there later, yours or a package's, would
            # be taken for this one's and removed)
            [[ -n $temp ]] || sudo rm -f "$pol" "$pol.dotfiles-temporary" || true
        fi
        # Stopped meanwhile (Ctrl+C): the LibreWolf below ended too (in the background it doesn't get Ctrl+C, and left
        # running it kept the profile in use: "LibreWolf is already running"), and the file still taken away, or it would
        # replace LibreWolf's own policies for good. The same when the run ends any other way meanwhile (a command failing
        # under set -e, the terminal closed): on EXIT too, before setup's own EXIT trap (kept, and put back after)
        pid=
        local exit_trap exit_cmd
        exit_trap=$(trap -p EXIT)
        eval "set -- $exit_trap"
        exit_cmd=${3:-}
        lw_stop() { kill "$pid" 2>/dev/null; [[ -z $temp ]] || sudo rm -f "$pol" "$pol.dotfiles-temporary"; }
        trap 'lw_stop; exit 130' INT TERM HUP
        trap 'rc=$?; lw_stop; (exit $rc); eval "$exit_cmd"' EXIT
        # No profile yet: start LibreWolf once in the background so it creates one (and installs the theme)
        librewolf --headless about:blank >/dev/null 2>&1 &
        pid=$!
        for _ in $(seq 30); do
            sleep 1
            prof=$(firefox_profile)
            [[ -n $prof && -f $prof/prefs.js ]] || continue
            [[ -z $temp ]] || grep -q '"nova-lagoon@mozilla.org"' "$prof/extensions.json" 2>/dev/null && break
        done
        sleep 2
        kill "$pid" 2>/dev/null || true  # it may have closed already
        wait "$pid" 2>/dev/null || true
        trap - INT TERM HUP
        if [[ -n $exit_trap ]]; then eval "$exit_trap"; else trap - EXIT; fi
        if [[ -n $temp ]]; then
            sudo rm -f "$pol" "$pol.dotfiles-temporary" && sudo rmdir -p --ignore-fail-on-non-empty "${pol%/*}" 2>/dev/null
        fi
        grep -q '"nova-lagoon@mozilla.org"' "$prof/extensions.json" 2>/dev/null ||
            echo "The Lagoon theme didn't install (offline, or no sudo): pick it in LibreWolf's settings, Appearance."
    fi
    [[ -n $prof && -d $prof ]] || { echo "No LibreWolf profile; bookmarks and settings not imported."; return 0; }
    # Once per profile: a second run would put back settings you've changed since
    if [[ -e $prof/.dotfiles-imported ]]; then
        echo "LibreWolf settings were imported before; left as they are."
        # (a profile from before the bookmarks had their own mark: they were asked then. Not one --yes left to ask)
        [[ -e $prof/.dotfiles-bookmarks || -e $prof/.dotfiles-bookmarks-ask ]] || touch "$prof/.dotfiles-bookmarks"
    else
        [[ -f $settings ]] && grep '^user_pref' "$settings" >>"$prof/prefs.js" || true  # (none in it: not set -e's stop)
        # The new tab's background: the picture, under the id settings.js names it by
        local wallpaper="$HOME/.local/share/firefox/newtab-wallpaper.jpg" id
        id=$(grep -oP 'customWallpaper\.uuid", "\K[^"]+' "$settings" 2>/dev/null) || true
        if [[ -f $wallpaper && -n $id ]]; then
            mkdir -p "$prof/wallpaper/library" && cp "$wallpaper" "$prof/wallpaper/library/$id"
        fi
        touch "$prof/.dotfiles-imported"
        echo "LibreWolf settings applied."
    fi
    # No bookmarks file (the AgrOS repo has none: yours come back from your pen drive): nothing to import
    [[ -f $file ]] || return 0
    # The bookmarks in the repo are its owner's: asked once (someone else's install says no). Not with --yes (someone
    # running setup unattended would get the owner's bookmarks): left to ask on a later run
    [[ -e $prof/.dotfiles-bookmarks ]] && return 0
    if $yes; then
        echo "Bookmarks not imported (--yes doesn't): ./setup.sh --only desktop asks."
        touch "$prof/.dotfiles-bookmarks-ask"
        return 0
    fi
    if ask "Import the bookmarks saved in the repo into LibreWolf?"; then
        printf 'user_pref("browser.places.importBookmarksHTML", true);\nuser_pref("browser.bookmarks.file", "%s");\nuser_pref("browser.toolbars.bookmarks.visibility", "always");\n' \
            "$file" >>"$prof/prefs.js"
        echo "Bookmarks will be imported when LibreWolf opens."
    fi
    touch "$prof/.dotfiles-bookmarks"
    rm -f "$prof/.dotfiles-bookmarks-ask"
}

# Your VSCodium extensions (list in .config/VSCodium/extensions.txt, kept up to date by dotfiles-sync; open replacements
# for the Microsoft-only ones: basedpyright for Pylance, clangd for the C/C++ tools)
vscode_extensions() {
    local list="$repo/.config/VSCodium/extensions.txt" ext
    command -v codium >/dev/null && [[ -f $list ]] || return 0
    while read -r ext; do
        [[ -n $ext ]] || continue
        codium --install-extension "$ext" >/dev/null 2>&1 || echo "!! VSCodium extension failed: $ext"
    done <"$list"
    echo "VSCodium extensions installed."
}

# Claude Code comes with its VS Code extension (in extensions.txt); ~/.local/bin/claude runs its CLI
claude_plugins() {
    local claude="$HOME/.local/bin/claude" entry repo_m plugin
    "$claude" --version >/dev/null 2>&1 || { echo "Claude Code isn't installed: skipping its plugins"; return 0; }
    for entry in "${CLAUDE_PLUGINS[@]}"; do
        IFS='|' read -r repo_m plugin <<<"$entry"
        "$claude" plugin marketplace add "$repo_m" >/dev/null 2>&1 || true # already added is fine
        "$claude" plugin install "$plugin" --scope user >/dev/null 2>&1 || echo "!! Claude plugin failed: $plugin"
    done
    echo "Claude Code plugins installed."
    claude_notify_hook
}

# A notification when Claude Code finishes an answer: ~/.local/bin/claude-notify as its Stop hook, added to
# ~/.claude/settings.json beside what's there (your other settings and hooks kept; already there: left as it is). A file
# of another shape than Claude Code's (not an object, hooks or its Stop list odd) is left untouched, and said; never
# failing the step
claude_notify_hook() {
    local f="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json" cmd="$HOME/.local/bin/claude-notify" new
    mkdir -p "${f%/*}" || return 0
    [[ -s $f ]] || echo '{}' >"$f" || return 0
    if ! jq -e 'type == "object" and ((.hooks // {}) | type == "object" and ((.Stop // []) | type == "array"
            and all(.[]; type == "object" and ((.hooks // []) | type == "array" and all(.[]; type == "object")))))' \
            "$f" >/dev/null 2>&1; then
        echo "!! $f isn't in the shape Claude Code writes (hooks.Stop a list of {hooks: [...]}): its notification hook not added"
        return 0
    fi
    jq -e --arg c "$cmd" 'any(.hooks.Stop[]?.hooks[]?; .command == $c)' "$f" >/dev/null 2>&1 && return 0
    # (written in place: a link stays one)
    if new=$(jq --indent 2 --arg c "$cmd" '.hooks.Stop = (.hooks.Stop // []) + [{hooks: [{type: "command", command: $c}]}]' "$f") &&
        printf '%s\n' "$new" >"$f"; then
        echo "Claude Code's notification hook (claude-notify) added."
    else
        echo "!! Claude Code's notification hook couldn't be added to $f"
    fi
    return 0
}
