#!/usr/bin/env bash
# ci/artifact.sh: the repo handed between CI's jobs as one tar file. Packed and unpacked, every file as it was: a name
# with a ":" (a package with an epoch, which upload-artifact refuses), a space, a hidden one; a link packed as what it
# points at, a hard link as a copy. Unpacking what the repo job's AUR build scripts could have made instead (a link, a
# hard link, a pipe, a member out of the folder, by ".." or through a link): refused, said, the folder removed,
# nothing written outside it (a leading "/" taken off, kept in the folder)
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
a=$here/ci/artifact.sh
mkdir -p "$t/out/x86_64"
for f in 'foo-1:2.0-1-x86_64.pkg.tar.zst' 'odd name-1-1-any.pkg.tar.zst' .hidden agros.db.tar.gz; do echo "$f" >"$t/out/x86_64/$f"; done
ln -s agros.db.tar.gz "$t/out/x86_64/agros.db"
ln "$t/out/x86_64/agros.db.tar.gz" "$t/out/x86_64/agros.files"
"$a" pack "$t/out" "$t/out.tar" || fail "not packed"
o=$("$a" unpack "$t/out.tar" "$t/back" 2>&1) || fail "a packed repo not unpacked: $o"
diff -r "$t/out" "$t/back" >/dev/null || fail "not unpacked as it was: $(diff -r "$t/out" "$t/back")"
odd=$(find "$t/back" \( ! -type f ! -type d \) -o \( -type f -links +1 \))
[[ -z $odd ]] || fail "unpacked as other than plain files: $odd"
# Made otherwise (python's tarfile): each refused, the folder removed, nothing outside it
mkdir "$t/outside"
python3 - "$t/evil" "$t/outside" <<'PY'
import io, os, sys, tarfile
d, outside = sys.argv[1], sys.argv[2]
os.makedirs(d)
def tar(name, *members):
    with tarfile.open(os.path.join(d, name + ".tar"), "w") as tf:
        for m, data in members:
            tf.addfile(m, io.BytesIO(data) if data is not None else None)
def info(name, kind=tarfile.REGTYPE, data=b"x", link=""):
    m = tarfile.TarInfo(name); m.type = kind; m.linkname = link; m.mode = 0o644
    if kind == tarfile.REGTYPE: m.size = len(data)
    return m, (data if kind == tarfile.REGTYPE else None)
tar("dotdot", info("./x86_64/../../outside/evil"))
tar("absolute", info(outside + "/evil"))
tar("symlink", info("./x86_64/agros.db", tarfile.SYMTYPE, link="/etc/passwd"))
tar("through", info("./l", tarfile.SYMTYPE, link=outside), info("./l/evil"))
tar("hardlink", info("./a"), info("./b", tarfile.LNKTYPE, link="./a"))
tar("hardout", info("./b", tarfile.LNKTYPE, link=outside + "/kept"))
tar("fifo", info("./x86_64/p", tarfile.FIFOTYPE))
PY
echo kept >"$t/outside/kept"
for c in dotdot absolute symlink through hardlink hardout fifo; do
    rm -rf "$t/dest"
    # (a leading "/": GNU tar takes it off, the file kept in the folder)
    if [[ $c == absolute ]]; then
        o=$("$a" unpack "$t/evil/$c.tar" "$t/dest" 2>&1) && [[ -f $t/dest$t/outside/evil && ! -e $t/outside/evil ]] ||
            fail "absolute: not unpacked into the folder: $o"
        continue
    fi
    o=$("$a" unpack "$t/evil/$c.tar" "$t/dest" 2>&1) && fail "$c: unpacked: $o"
    [[ $o == *"!! "* ]] || fail "$c: not said: $o"
    [[ ! -e $t/dest ]] || fail "$c: the folder left: $(find "$t/dest")"
    [[ $(ls "$t/outside") == kept && $(cat "$t/outside/kept") == kept ]] || fail "$c: written outside the folder: $(ls -l "$t/outside")"
done
echo "ok ci-artifact"
