#!/bin/bash
# Bootfaehiges SD-Image bauen. Partition 1 = Rootfs (physisch hinten, waechst beim ersten Start),
# Partition 2 = FAT fuer Protokolle (am Windows-PC lesbar). Bootloader-Offsets wie im Armbian-Rezept.
set -euo pipefail
B=/root/opi3w; R=$B/rootfs; OUT=$B/out; I=$OUT/opi3w-arch-plasma.img
exec > >(tee -a "$B/logs/image.log") 2>&1
date
command -v mcopy >/dev/null || apt-get install -y -qq mtools >/dev/null
FAT_START=65536; FAT_SECT=524288; ROOT_START=$((FAT_START + FAT_SECT))
USED=$(du -sxm "$R" | cut -f1); ROOT_MB=$((USED * 125 / 100 + 1024)); ROOT_SECT=$((ROOT_MB * 2048))
TOTAL=$((ROOT_START + ROOT_SECT))
echo "Rootfs ${USED} MiB, Partition ${ROOT_MB} MiB, Image $((TOTAL / 2048)) MiB"
rm -f "$I" "$OUT/root.ext4" "$OUT/log.vfat"
truncate -s $((TOTAL * 512)) "$I"
sfdisk "$I" <<EOF
label: dos
label-id: 0x0a733a73
unit: sectors
1 : start=$ROOT_START, size=$ROOT_SECT, type=83, bootable
2 : start=$FAT_START, size=$FAT_SECT, type=c
EOF
sfdisk -d "$I"

# Ext4 ohne Features, die der Vendor-U-Boot 2018 nicht lesen kann.
truncate -s $((ROOT_SECT * 512)) "$OUT/root.ext4"
mke2fs -q -t ext4 -L opi3w-root -m 2 -O '^64bit,^metadata_csum,^metadata_csum_seed,^orphan_file' -E root_owner=0:0 -d "$R" "$OUT/root.ext4"
e2fsck -fn "$OUT/root.ext4"
dd if="$OUT/root.ext4" of="$I" bs=4M seek=$((ROOT_START * 512)) oflag=seek_bytes conv=notrunc,sparse status=none
rm -f "$OUT/root.ext4"

mkfs.vfat -F 32 -n OPI3W-LOG -C "$OUT/log.vfat" $((FAT_SECT / 2)) >/dev/null
cat > /tmp/LIESMICH.txt <<'EOF'
Orange Pi Zero 3W: Protokolle
Das System legt hier bei jedem Start einen Ordner boot-N mit Protokollen an.
Windows darf diese Partition lesen. Die Linux-Partition auf dieser Karte bitte NICHT formatieren,
auch wenn Windows das anbietet.
EOF
sed -i 's/$/\r/' /tmp/LIESMICH.txt
mcopy -i "$OUT/log.vfat" /tmp/LIESMICH.txt ::LIESMICH.txt
dd if="$OUT/log.vfat" of="$I" bs=4M seek=$((FAT_START * 512)) oflag=seek_bytes conv=notrunc status=none
rm -f "$OUT/log.vfat"

dd if="$OUT/uboot/boot0_sdcard.fex" of="$I" bs=1k seek=8 conv=notrunc status=none
dd if="$OUT/uboot/boot_package.fex" of="$I" bs=1k seek=16400 conv=notrunc status=none

echo "--- Pruefung"
sfdisk -l "$I"
cmp -n "$(stat -c%s "$OUT/uboot/boot0_sdcard.fex")" -i 8192:0 "$I" "$OUT/uboot/boot0_sdcard.fex" && echo boot0-ok
cmp -n "$(stat -c%s "$OUT/uboot/boot_package.fex")" -i $((16400 * 1024)):0 "$I" "$OUT/uboot/boot_package.fex" && echo boot_package-ok
[ $(( (16400 * 1024 + $(stat -c%s "$OUT/uboot/boot_package.fex")) / 512 )) -lt $FAT_START ] && echo bootloader-vor-partitionen-ok
dd if="$I" bs=512 skip=$ROOT_START count=$ROOT_SECT status=none of=/tmp/rootcheck.ext4 conv=sparse
for f in /boot/boot.scr /boot/Image /boot/armbianEnv.txt /boot/dtb/allwinner/sun60i-a733-orangepi-zero3w.dtb /boot/overlay-user/a733-fan.dtbo \
  /usr/lib/firmware/apercel/rogue_36.56.104.183_v1.fw /usr/lib/firmware/aic8800/SDIO/aic8800D80/fmacfw_8800d80_u02.bin /usr/lib/modules/6.6.98-vendor-sun60iw2/extra/apercel.ko \
  /usr/lib/libgbm.so.1 /usr/bin/kwin_wayland /usr/bin/sddm /usr/lib/sun60iw2-npu/libVIPhal.so; do
  debugfs -R "stat $f" /tmp/rootcheck.ext4 2>/dev/null | grep -q '^Inode' && echo "ok  $f" || echo "FEHLT $f"
done
dumpe2fs -h /tmp/rootcheck.ext4 2>/dev/null | grep -E 'features|UUID|Filesystem state'
rm -f /tmp/rootcheck.ext4
sha256sum "$I" | tee "$I.sha256"
ls -las "$I"
date; echo FERTIG
