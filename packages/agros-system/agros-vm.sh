# Virtual GPUs (VMware's at least) can't take Qt's GPU buffers: OpenGL apps (Caelestia too) drawn on the CPU there (Mesa's llvmpipe)
systemd-detect-virt -q --vm && export LIBGL_ALWAYS_SOFTWARE=1
