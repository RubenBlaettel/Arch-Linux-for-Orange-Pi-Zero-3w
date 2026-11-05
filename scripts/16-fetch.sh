#!/bin/bash
# Zusatzquellen: Firmware, NPU, CachyOS-Einstellungen.
B=/root/opi3w; S=$B/src; cd $S
FW=$B/dl/fw; mkdir -p $FW
C=8a58f81883f7be458daa34e418cc4079f995b279; H=1db1c399c17401d1f79d46c880db81c724d748c784d4639433b076aba2f9c0d2
F=$FW/rogue_36.56.104.183_v1.fw
[ -f $F ] || curl -fsSL --retry 3 -o $F "https://gitlab.freedesktop.org/imagination/linux-firmware/-/raw/$C/powervr/rogue_36.56.104.183_v1.fw"
echo "$H  $F" | sha256sum -c -
if [ ! -d armbian-firmware/.git ]; then
  git clone -q --depth 1 --filter=blob:none --sparse https://github.com/armbian/firmware.git armbian-firmware
  git -C armbian-firmware sparse-checkout set aic8800 lib/firmware/aic8800
fi
find armbian-firmware -path '*aic8800*' -maxdepth 4 -type d | head; du -sh armbian-firmware/aic8800* armbian-firmware/lib/firmware/aic8800* 2>/dev/null
find armbian-firmware -ipath '*aic8800D80*' -type f | head -30
R=7b6d78d4f5eaefd5456777fbea5057a0876e8f4d
if [ ! -d npu-pkgs/.git ]; then
  git init -q npu-pkgs; git -C npu-pkgs remote add origin https://github.com/orangepi-xunlong/rk-rootfs-build.git
  git -C npu-pkgs config core.sparseCheckout true; echo 'npu/*' > npu-pkgs/.git/info/sparse-checkout
  git -C npu-pkgs fetch -q --depth 1 --filter=blob:none origin $R && git -C npu-pkgs checkout -q FETCH_HEAD
fi
du -sh npu-pkgs/npu; find npu-pkgs/npu -maxdepth 3 | head -30
find npu-pkgs/npu -name '*.so*' | head -12
for r in CachyOS-Settings cachyos-wallpapers cachyos-fish-config; do
  [ -d $r/.git ] || git clone -q --depth 1 https://github.com/CachyOS/$r.git $r
  echo "== $r"; (cd $r; git log -1 --format='%h %cs'; find . -path ./.git -prune -o -type f -print | head -60)
done
du -sh cachyos-wallpapers
