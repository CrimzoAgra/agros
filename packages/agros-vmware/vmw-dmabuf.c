// Compositors (Hyprland, wlroots's cage) check each app's GPU buffer by importing its handle and closing it again,
// and refuse the buffer when the close fails. On VMware's vmwgfx, buffers drawn by Mesa's svga driver import as
// surface handles, which the generic GEM close refuses (EINVAL): every GPU app was refused. Released here the vmwgfx
// way instead (its surface unref), so the check passes and the handle isn't leaked.
//
// Built by agros-vmware's PKGBUILD into /usr/lib/agros/vmw-dmabuf.so; loaded into Hyprland and cage in VMware guests only
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <stdint.h>
#include <string.h>
#include <xf86drm.h>
#include <libdrm/vmwgfx_drm.h>

static int is_vmwgfx(int fd) {
    drmVersionPtr v = drmGetVersion(fd);
    int yes = v && v->name && strcmp(v->name, "vmwgfx") == 0;
    drmFreeVersion(v);
    return yes;
}

int drmCloseBufferHandle(int fd, uint32_t handle) {
    static int (*real)(int, uint32_t);
    if (!real)
        real = (int (*)(int, uint32_t))dlsym(RTLD_NEXT, "drmCloseBufferHandle");
    int r = real(fd, handle);
    if (r == 0 || errno != EINVAL || !is_vmwgfx(fd))
        return r;
    struct drm_vmw_surface_arg arg = { .sid = (int32_t)handle, .handle_type = DRM_VMW_HANDLE_LEGACY };
    return drmCommandWrite(fd, DRM_VMW_UNREF_SURFACE, &arg, sizeof arg) == 0 ? 0 : r;
}
