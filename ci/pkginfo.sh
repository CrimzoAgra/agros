# shellcheck shell=bash
# Sourced by own-check.sh and repo-db.sh: a package's .PKGINFO checked before pacman's repo-add reads it. repo-add
# (pacman's scripts/repo-add.sh.in, db_write_entry) splits each line at its first spaces and "=" and runs
# declare "$key=$value": a key such as x[$(cmd)] is a command bash runs (an array's index), a key such as PATH changes
# what it runs next, and "pkgname=x", with no spaces, is read too, the last one winning. An AUR build script, root in
# the repo job, can write any .PKGINFO; so only what makepkg writes (scripts/makepkg.sh.in, write_pkginfo) passes:
# "<field> = <value>" lines of its fields alone and comments, one pkgname and one pkgver in pacman's characters (no
# "/": repo-add makes a folder of them), and the file named after them (one with a newline added lines to the database)
pkginfo_fields='pkgname|pkgbase|xdata|pkgver|pkgdesc|url|builddate|packager|size|arch|license|replaces|group|conflict|provides|backup|depend|optdepend|makedepend|checkdepend'
# pkginfo <package file>: its name and version in $pkgname and $pkgver; when it isn't one makepkg would write: 1, said
pkginfo() {
    # (C's characters: a-z only those 26 letters, and a byte that isn't text one that isn't a control character)
    local f=$1 base=${1##*/} info all && local -x LC_ALL=C
    pkgname='' pkgver=''
    # (the first .PKGINFO in it, as repo-add reads it (-q); a second one, which pacman reads too: refused)
    info=$(bsdtar -xOqf "$f" .PKGINFO 2>/dev/null) || info=
    all=$(bsdtar -xOf "$f" .PKGINFO 2>/dev/null) || all=
    [[ -n $info && $info == "$all" ]] || { echo "!! $base: no .PKGINFO, or more than one: refused"; return 1; }
    if grep -Evx -e '#.*' -e "($pkginfo_fields) = [^[:cntrl:]]*" <<<"$info" >/dev/null; then
        echo "!! $base: its .PKGINFO has a line makepkg doesn't write (repo-add would run it as code): refused"
        return 1
    fi
    pkgname=$(sed -n 's/^pkgname = //p' <<<"$info") pkgver=$(sed -n 's/^pkgver = //p' <<<"$info")
    # (two lines of either: two lines here, which the patterns refuse)
    [[ $pkgname =~ ^[a-z0-9@_+][a-z0-9@._+-]*$ && $pkgver =~ ^[A-Za-z0-9._+:~-]+$ ]] ||
        { echo "!! $base: its pkgname or pkgver isn't one (none, two, or characters pacman doesn't allow): refused"; return 1; }
    # (<name>-<version>-<arch>.pkg.tar..., as makepkg names it: its arch without a "-")
    [[ $base =~ ^[A-Za-z0-9@._+:~-]+$ && $base == "$pkgname-$pkgver-"*.pkg.tar* && ${base#"$pkgname-$pkgver-"} != *-* ]] ||
        { echo "!! $base: not named after its .PKGINFO ($pkgname $pkgver): refused"; return 1; }
}
