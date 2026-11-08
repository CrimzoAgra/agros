# shellcheck shell=bash
# How setup's system parts are written, in one place: setup (and the system/ scripts) write them with these, and
# dotfiles-check renders them the same way to compare with what's installed (an update to the repo since: re-run that
# step). Sourced, not run.

# render_hook <template.hook.in> <user> <home>: a pacman hook from its template (system/pacman-hooks/), as installed
# in /etc/pacman.d/hooks/<name>.hook
render_hook() { sed -e "s|@USER@|$2|g" -e "s|@HOME@|$3|g" "$1"; }

# heredoc <script> <target>: what a script writes with cat >TARGET <<'EOF' ... EOF (quoted: written as it stands)
heredoc() { awk -v t="cat >$2 <<'EOF'" '$0 == t { on = 1; next } on && $0 == "EOF" { exit } on' "$1"; }

# pacman_holders_of <repo> / lock_holder_of <repo>: dotfiles-check's list of what takes pacman's lock, and its
# lock_holder, as the boot's update gets them
pacman_holders_of() { sed -n "s/^pacman_holders='\([^']*\)'.*/\1/p" "$1/.local/bin/dotfiles-check"; }
lock_holder_of() { sed -n '/^lock_holder() {$/,/^}$/p' "$1/.local/bin/dotfiles-check"; }

# render_auto_update <repo> <user> <home>: /usr/local/bin/auto-update as system/auto-update-setup.sh writes it (its
# heredoc, with $user, $home, $holders and $holder_fn filled in)
render_auto_update() {
    { echo 'cat <<EOF'; sed -n '/^cat >\/usr\/local\/bin\/auto-update <<EOF$/,/^EOF$/p' "$1/system/auto-update-setup.sh" | sed '1d'; } |
        user=$2 home=$3 holders=$(pacman_holders_of "$1") holder_fn=$(lock_holder_of "$1") bash
}

# grub_quiet_hook: system/boot-menu.sh's pacman hook (/etc/pacman.d/hooks/grub-quiet.hook): GRUB's "Loading Linux..."
# lines out of its script again after each GRUB update
grub_quiet_strip="/^[[:space:]]*echo[[:space:]].*message/d"
grub_quiet_hook() {
    printf '%s\n' '[Trigger]' 'Operation = Install' 'Operation = Upgrade' 'Type = Package' 'Target = grub' '' '[Action]' \
        'Description = Hiding GRUB loading messages (dotfiles boot-menu.sh)' 'When = PostTransaction' \
        "Exec = /usr/bin/sed -i $grub_quiet_strip /etc/grub.d/10_linux"
}
