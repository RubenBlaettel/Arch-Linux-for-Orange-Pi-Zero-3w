#!/bin/bash
# Mesa 26.3.0-rc2 mit apercel-Patch als Arch-Paket "mesa" bauen (getrennter Build-Chroot).
set -euo pipefail
B=/root/opi3w; R=$B/rootfs-mesa; OUT=$B/out; mkdir -p "$OUT"
exec > >(tee -a "$B/logs/mesa.log") 2>&1
date
if [ ! -f "$R/.ready" ]; then
  rm -rf "$R"; cp -a "$B/rootfs" "$R"
  rm -f "$R/.extracted"
  cat > "$R/root/deps.sh" <<'EOF'
set -e
pacman -Syu --noconfirm --needed base-devel meson ninja python-mako python-yaml python-packaging wayland wayland-protocols \
  clang llvm libclc spirv-llvm-translator spirv-tools glslang libdrm libx11 libxext libxfixes libxrandr libxcb libxshmfence \
  libxxf86vm xorgproto libglvnd expat zstd zlib libelf bison flex vulkan-headers vulkan-icd-loader libpciaccess
id builder >/dev/null 2>&1 || useradd -m builder
EOF
  arch-chroot "$R" bash /root/deps.sh
  touch "$R/.ready"
fi
W=$R/home/builder/mesa; mkdir -p "$W"
cp "$B/src/apercel/mesa/apercel-mesa-26.3.0-rc2.patch" "$W/apercel.patch"
sed -i 's/\r$//' "$W/apercel.patch"
cat > "$W/PKGBUILD" <<'EOF'
pkgname=mesa
epoch=2
pkgver=26.3.0rc2
_ver=26.3.0-rc2
pkgrel=1
pkgdesc="Mesa $_ver mit apercel-Patch: PowerVR-Vulkan und zink fuer Allwinner A733"
arch=(aarch64)
url="https://github.com/CheezeCS/apercel"
license=('MIT AND BSD-3-Clause AND SGI-B-2.0')
depends=(expat glibc libdrm libelf libgcc libglvnd libstdc++ libx11 libxcb libxext libxshmfence libxxf86vm llvm-libs spirv-tools wayland zlib zstd vulkan-icd-loader)
provides=("mesa-libgl=1:26.3.0" "libva-mesa-driver=1:26.3.0" libva-driver opengl-driver vulkan-driver vulkan-mesa-layers)
conflicts=(vulkan-swrast vulkan-mesa-layers)
options=(!lto !debug)
source=("https://archive.mesa3d.org/mesa-$_ver.tar.xz" apercel.patch)
sha256sums=(6b9154bc46ec73901555dbcb61600eb69607dc1da718a87e7a1c09a755bb1b6d SKIP)
prepare() {
  cd "mesa-$_ver"
  patch -p1 --forward < ../apercel.patch
  grep -rn 'PVR_I_WANT_A_BROKEN_VULKAN_DRIVER' src/imagination | head -5 || true
}
build() {
  meson setup "mesa-$_ver" build --prefix=/usr --libexecdir=lib --sbindir=bin --buildtype=release --wrap-mode=nodownload \
    -Dvulkan-drivers=imagination -Dgallium-drivers=zink \
    -Degl=enabled -Dgbm=enabled -Dglvnd=enabled -Dopengl=true \
    -Dgles1=disabled -Dgles2=enabled \
    -Dplatforms=x11,wayland -Dglx=dri -Dxlib-lease=disabled \
    -Dshader-cache=enabled -Dbuild-tests=false \
    -Dllvm=enabled -Dshared-llvm=enabled -Dmesa-clc=enabled \
    -Dvalgrind=disabled -Dlibunwind=disabled -Dlmsensors=disabled \
    -Dgallium-va=disabled -Dvideo-codecs=
  ninja -C build -j "${JOBS:-10}"
}
package() {
  DESTDIR="$pkgdir" meson install -C build --no-rebuild --quiet
  install -Dm644 "mesa-$_ver/docs/license.rst" "$pkgdir/usr/share/licenses/$pkgname/license.rst"
}
EOF
chown -R --reference="$R/home/builder" "$W" 2>/dev/null || true
cat > "$R/root/build.sh" <<'EOF'
set -e
chown -R builder: /home/builder/mesa
cd /home/builder/mesa
sudo -u builder env JOBS=10 PKGDEST=/home/builder/mesa makepkg -Cf --nodeps --noconfirm
ls -la /home/builder/mesa/*.pkg.tar.*
EOF
rm -f "$W"/mesa-*.pkg.tar.*
arch-chroot "$R" bash /root/build.sh
ls "$W"/mesa-*.pkg.tar.* >/dev/null || { echo "FEHLER: kein Mesa-Paket"; exit 1; }
cp "$W"/mesa-*.pkg.tar.* "$OUT/"
ls -la "$OUT"
date; echo FERTIG
