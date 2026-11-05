#!/bin/bash
set -u
B=/root/opi3w; SC=$B/scripts; R=$B/rootfs
cd "$SC"
[ -e /proc/sys/fs/binfmt_misc/qemu-aarch64 ] || printf '%s' ':qemu-aarch64:M::\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\xb7\x00:\xff\xff\xff\xff\xff\xff\xff\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff:/usr/bin/qemu-aarch64-static:FC' > /proc/sys/fs/binfmt_misc/register
ls -la "$B/out/" | grep mesa | cut -c30-
: > "$B/logs/integrate.log"; : > "$B/logs/image.log"
bash 41-integrate.sh >/dev/null 2>&1; rc=$?; echo "integrate exit=$rc"
[ "$rc" = 0 ] || { tail -n 15 "$B/logs/integrate.log" | cut -c1-140; exit 1; }
chroot "$R" /usr/bin/pacman -Q mesa
strings "$R/usr/lib/libEGL_mesa.so.0.0.0" | grep -c 'failed to setup EGLDevice'
bash 60-chroot-check.sh 2>&1 | grep -E 'FEHLT|kwin-libs|gbm-libs' | cut -c1-100
bash 50-image.sh >/dev/null 2>&1; rc=$?; echo "image exit=$rc"
grep -cE '^FEHLT' "$B/logs/image.log"; grep -cE '^ok ' "$B/logs/image.log"
grep -E 'boot0-ok|boot_package-ok|bootloader-vor|Filesystem state' "$B/logs/image.log" | cut -c1-70
tail -n 4 "$B/logs/image.log" | cut -c1-110
exit "$rc"
