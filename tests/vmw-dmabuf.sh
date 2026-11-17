#!/usr/bin/env bash
# agros-vmware's shim (packages/agros-vmware/vmw-dmabuf.c): builds as its PKGBUILD builds it, warnings as errors, and
# exports drmCloseBufferHandle. Preloaded into a program whose libdrm is a stand-in (the driver's name, the generic
# close's and the vmwgfx release's results set per run): a close that works, or fails for any reason but EINVAL, or on a
# driver that isn't vmwgfx, is the real one's, untouched (nothing released another way); EINVAL on vmwgfx releases the
# handle as a vmwgfx surface (its unref, that handle) and passes when that worked, else the real close's failure stands
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
if ! command -v gcc >/dev/null || ! pkg-config --exists libdrm; then
    skipped "no gcc or libdrm's headers: the shim not built"
    echo "ok vmw-dmabuf"
    exit 0
fi
cp "$here/packages/agros-vmware/vmw-dmabuf.c" "$t/"
# shellcheck disable=SC1091  # (the PKGBUILD's build(), run where its source is)
(cd "$t" && . "$here/packages/agros-vmware/PKGBUILD" && CFLAGS="-Wall -Werror" LDFLAGS='' build) >"$t/out" 2>&1 ||
    fail "doesn't build: $(tail -3 "$t/out")"
grep -qw drmCloseBufferHandle <<<"$(nm -D --defined-only "$t/vmw-dmabuf.so")" || fail "drmCloseBufferHandle not exported"

# The stand-in libdrm: $DRIVER the driver's name, $CLOSE the generic close's errno (0: it works), $UNREF the vmwgfx
# release's result; each call said on stdout
cat >"$t/fakedrm.c" <<'C'
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <xf86drm.h>
#include <libdrm/vmwgfx_drm.h>
int drmCloseBufferHandle(int fd, uint32_t handle) {
    int e = atoi(getenv("CLOSE"));
    printf("close %u\n", handle);
    (void)fd;
    if (!e) return 0;
    errno = e;
    return -1;
}
drmVersionPtr drmGetVersion(int fd) {
    drmVersionPtr v = calloc(1, sizeof *v);
    (void)fd;
    v->name = strdup(getenv("DRIVER"));
    v->name_len = strlen(v->name);
    return v;
}
void drmFreeVersion(drmVersionPtr v) { if (v) free(v->name), free(v); }
int drmCommandWrite(int fd, unsigned long index, void *data, unsigned long size) {
    struct drm_vmw_surface_arg *a = data;
    (void)fd;
    if (index == DRM_VMW_UNREF_SURFACE && size == sizeof *a && a->handle_type == DRM_VMW_HANDLE_LEGACY)
        printf("unref surface %d\n", a->sid);
    else
        printf("another command %lu\n", index);
    return atoi(getenv("UNREF"));
}
C
cat >"$t/main.c" <<'C'
#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <xf86drm.h>
int main(void) {
    int r = drmCloseBufferHandle(3, 42);
    printf("-> %d%s\n", r, r ? (errno == EINVAL ? " EINVAL" : " other") : "");
    return 0;
}
C
# shellcheck disable=SC2046  # (pkg-config's flags, split into words on purpose)
gcc -Wall -Werror -shared -fPIC -o "$t/libfakedrm.so" "$t/fakedrm.c" $(pkg-config --cflags libdrm) &&
    gcc -Wall -Werror -o "$t/main" "$t/main.c" $(pkg-config --cflags libdrm) -L"$t" -lfakedrm -Wl,-rpath,"$t" >"$t/out" 2>&1 ||
    fail "the stand-ins don't build: $(tail -3 "$t/out")"
call() { DRIVER=$1 CLOSE=$2 UNREF=$3 LD_PRELOAD=$t/vmw-dmabuf.so "$t/main"; }
unref='unref surface 42'
[[ $(call vmwgfx 0 0) == $'close 42\n-> 0' ]] || fail "a close that worked: $(call vmwgfx 0 0)"
[[ $(call vmwgfx 22 0) == $'close 42\n'"$unref"$'\n-> 0' ]] || fail "vmwgfx's EINVAL not released as a surface: $(call vmwgfx 22 0)"
[[ $(call vmwgfx 22 -22) == $'close 42\n'"$unref"$'\n-> -1 EINVAL' ]] || fail "vmwgfx's release failing: $(call vmwgfx 22 -22)"
[[ $(call i915 22 0) == $'close 42\n-> -1 EINVAL' ]] || fail "another driver's EINVAL touched: $(call i915 22 0)"
[[ $(call vmwgfx 9 0) == $'close 42\n-> -1 other' ]] || fail "another failure touched: $(call vmwgfx 9 0)"
echo "ok vmw-dmabuf"
