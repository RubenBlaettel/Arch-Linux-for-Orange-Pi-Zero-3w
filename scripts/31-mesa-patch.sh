#!/bin/bash
# Mesa-Patch: Wayland-Kompositor ohne Render-Knoten (sunxi-drm) mit zink/kopper zulassen.
set -euo pipefail
B=/root/opi3w; R=$B/rootfs-mesa; W=$R/home/builder/mesa; OUT=$B/out
exec > >(tee -a "$B/logs/mesa.log") 2>&1
date
[ -e /proc/sys/fs/binfmt_misc/qemu-aarch64 ] || printf '%s' ':qemu-aarch64:M::\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\xb7\x00:\xff\xff\xff\xff\xff\xff\xff\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff:/usr/bin/qemu-aarch64-static:FC' > /proc/sys/fs/binfmt_misc/register
S=$W/src/mesa-26.3.0-rc2; P=$S/src/egl/drivers/dri2/platform_wayland.c
n=$(grep -n '^dri2_initialize_wayland_drm(' "$P" | cut -d: -f1)
echo "--- Nachfolgender Code"; sed -n "$((n+66)),$((n+125))p" "$P" | cut -c1-92
python3 - "$P" <<'PY'
import sys
p=sys.argv[1]; s=open(p).read()
a="""   if (!dri2_setup_device(disp, false)) {
      _eglError(EGL_NOT_INITIALIZED, "DRI2: failed to setup EGLDevice");
      goto cleanup;
   }

   dri2_setup_screen(disp);

   dri2_wl_setup_swap_interval(disp);

   if (dri2_dpy->wl_drm) {"""
if "opi3w" in s:
    print("Patch schon drin")
else:
    b="""   /* opi3w: Scanout-only compositor device (e.g. sunxi-drm) has no render node,
    * so fd_render_gpu stays -1. zink renders and presents through its own Vulkan
    * device and WSI, so it does not need that fd; use the fd-less EGLDevice. */
   if (!dri2_setup_device(disp, dri2_dpy->kopper && dri2_dpy->fd_render_gpu < 0)) {
      _eglError(EGL_NOT_INITIALIZED, "DRI2: failed to setup EGLDevice");
      goto cleanup;
   }
"""
    k="""   if (!dri2_setup_device(disp, false)) {
      _eglError(EGL_NOT_INITIALIZED, "DRI2: failed to setup EGLDevice");
      goto cleanup;
   }
"""
    i=s.index("dri2_initialize_wayland_drm(_EGLDisplay *disp)")
    j=s.index(k,i)
    s=s[:j]+b+s[j+len(k):]
    open(p,'w').write(s); print("Patch angewendet")
PY
grep -n -A3 'opi3w' "$P" | cut -c1-90
# Fuer spaetere Neubauten festhalten.
O=$(mktemp -d); tar -xf "$W/mesa-26.3.0-rc2.tar.xz" -C "$O" mesa-26.3.0-rc2/src/egl/drivers/dri2/platform_wayland.c
(cd "$O/mesa-26.3.0-rc2" && patch -s -p1 --forward < "$W/apercel.patch" >/dev/null 2>&1 || true)
cp "$O/mesa-26.3.0-rc2/src/egl/drivers/dri2/platform_wayland.c" /tmp/pw.orig; rm -rf "$O"
(cd /tmp; diff -u --label a/src/egl/drivers/dri2/platform_wayland.c --label b/src/egl/drivers/dri2/platform_wayland.c pw.orig "$P" > "$B/patches/opi3w-mesa-no-render-node.patch" || true)
wc -l "$B/patches/opi3w-mesa-no-render-node.patch"
cp "$B/patches/opi3w-mesa-no-render-node.patch" "$W/opi3w-no-render-node.patch"
grep -q 'opi3w-no-render-node' "$W/PKGBUILD" || sed -i \
  -e 's/^pkgrel=1/pkgrel=2/' \
  -e 's/^source=(\(.*\) apercel.patch)/source=(\1 apercel.patch opi3w-no-render-node.patch)/' \
  -e 's/^sha256sums=(\(.*\) SKIP)/sha256sums=(\1 SKIP SKIP)/' \
  -e 's/^  patch -p1 --forward < ..\/apercel.patch$/&\n  patch -p1 --forward < ..\/opi3w-no-render-node.patch/' "$W/PKGBUILD"
grep -nE '^(pkgrel|source|sha256sums)|opi3w' "$W/PKGBUILD" | cut -c1-110
cat > "$R/root/build2.sh" <<'EOF'
set -e
chown -R builder: /home/builder/mesa
cd /home/builder/mesa
rm -f /home/builder/mesa/mesa-*.pkg.tar.*
# -e: vorhandenen Build weiterverwenden, nur die geaenderten Dateien werden neu uebersetzt.
sudo -u builder env JOBS=10 PKGDEST=/home/builder/mesa makepkg -ef --nodeps --noconfirm --skipchecksums
ls -la /home/builder/mesa/*.pkg.tar.*
EOF
arch-chroot "$R" bash /root/build2.sh
ls "$W"/mesa-*.pkg.tar.* >/dev/null || { echo "FEHLER: kein Paket"; exit 1; }
rm -f "$OUT"/mesa-*.pkg.tar.*; cp "$W"/mesa-*.pkg.tar.* "$OUT/"
ls -la "$OUT" | grep mesa
date; echo FERTIG
