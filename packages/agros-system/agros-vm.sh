# Virtual GPUs (VMware's at least) can't take Qt's GPU buffers: Caelestia and the other Quickshell parts draw in software there
systemd-detect-virt -q --vm && export QT_QUICK_BACKEND=software
