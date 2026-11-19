#!/usr/bin/env bash
# artifact.sh: the repo handed between CI's jobs as one tar file (ci.yml: the repo job's built repo to the test and
# release jobs, the release's to the sign job). upload-artifact refuses a file whose name has a ":", and a package with
# an epoch has one (foo-1:2.0-1-x86_64.pkg.tar.zst): the day an AUR package AgrOS carries took one, every run failed at
# the upload and nothing went out. A tar keeps any name
#   ci/artifact.sh pack <dir> <file>      <dir>'s files and folders into <file>, a link as what it points at (as
#                                         upload-artifact took it)
#   ci/artifact.sh unpack <file> <dir>    back into <dir> (made if needed), as plain files and folders alone: a link, a
#                                         hard link, a device or a pipe (the repo job runs AUR build scripts as root, and
#                                         could make its tar so) refuses it, said, <dir> removed. GNU tar takes no
#                                         member name with "..", nor a leading "/"
set -euo pipefail
usage="usage: artifact.sh pack <dir> <file> | artifact.sh unpack <file> <dir>"
case ${1:-} in
    pack) tar -cf "${3:?$usage}" --dereference --hard-dereference -C "${2:?$usage}" . ;;
    unpack)
        file=${2:?$usage} dir=${3:?$usage}
        mkdir -p "$dir"
        tar -xf "$file" -C "$dir" --no-same-owner --no-same-permissions ||
            { echo "!! $file couldn't be unpacked"; rm -rf "$dir"; exit 1; }
        odd=$(find "$dir" \( \( ! -type f ! -type d \) -o \( -type f -links +1 \) \) -print -quit)
        [[ -z $odd ]] || { echo "!! not a plain file or a folder: $odd: refused"; rm -rf "$dir"; exit 1; }
        ;;
    *) echo "$usage" >&2; exit 2 ;;
esac
