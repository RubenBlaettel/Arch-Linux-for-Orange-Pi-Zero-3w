#!/bin/bash
# Kernel, Treiber, Firmware, Mesa, CachyOS-Einstellungen und Konfiguration ins Rootfs bringen.
set -euo pipefail
B=/root/opi3w; S=$B/src; R=$B/rootfs; OUT=$B/out; A=$S/armbian-build; DEBS=$A/output/debs
exec > >(tee -a "$B/logs/integrate.log") 2>&1
date; mkdir -p "$OUT/uboot"
KV=6.6.98-vendor-sun60iw2
T=$(mktemp -d)

# --- Kernel, Module, DTBs, U-Boot ---
dpkg-deb -x "$(ls "$DEBS"/linux-image-*.deb)" "$T/img"
dpkg-deb -x "$(ls "$DEBS"/linux-dtb-*.deb)" "$T/dtb"
dpkg-deb -x "$(ls "$DEBS"/linux-u-boot-*.deb)" "$T/ub"
install -d "$R/boot/dtb" "$R/boot/overlay-user" "$R/usr/lib/modules"
install -m644 "$T/img/boot/vmlinuz-$KV" "$R/boot/Image"
install -m644 "$T/img/boot/config-$KV" "$R/boot/config-$KV"
rm -rf "$R/usr/lib/modules/$KV"; cp -a "$T/img/lib/modules/$KV" "$R/usr/lib/modules/$KV"
rm -rf "$R/boot/dtb"; cp -a "$T/dtb/boot/dtb-$KV" "$R/boot/dtb"
cp "$T"/ub/usr/lib/linux-u-boot-vendor-orangepizero3w/boot0_sdcard.fex "$T"/ub/usr/lib/linux-u-boot-vendor-orangepizero3w/boot_package.fex "$OUT/uboot/"
find "$R/usr/lib/modules/$KV" -name 'pvrsrvkm*' -delete

# --- Bootskript (Armbian-Rezept, ohne Initrd) ---
cat > "$R/boot/boot.cmd" <<'EOF'
# Orange Pi Zero 3W: Arch Linux ARM, Einstellungen in /boot/armbianEnv.txt
# Neu bauen: mkimage -C none -A arm -T script -d /boot/boot.cmd /boot/boot.scr
setenv kernel_addr_r "0x41000000"
setenv fdt_addr_r "0x4a000000"
setenv load_addr "0x4d000000"
setenv overlay_error "false"
setenv verbosity "7"
setenv console "both"
setenv rootfstype "ext4"
echo "Boot script loaded from ${devtype} ${devnum}"
if test -e ${devtype} ${devnum} ${prefix}armbianEnv.txt; then
	load ${devtype} ${devnum} ${load_addr} ${prefix}armbianEnv.txt
	env import -t ${load_addr} ${filesize}
fi
if test "${console}" = "display" || test "${console}" = "both"; then setenv consoleargs "console=tty1"; fi
if test "${console}" = "serial" || test "${console}" = "both"; then setenv consoleargs "console=ttyS0,115200 ${consoleargs}"; fi
part uuid ${devtype} ${devnum}:1 partuuid
if test -z "${rootdev}"; then rootdev=PARTUUID="${partuuid}"; fi
setenv bootargs "root=${rootdev} rootwait rw rootfstype=${rootfstype} ${consoleargs} consoleblank=0 loglevel=${verbosity} clk_ignore_unused swiotlb=65536 ${extraargs}"
load ${devtype} ${devnum} ${kernel_addr_r} ${prefix}Image
load ${devtype} ${devnum} ${fdt_addr_r} ${prefix}dtb/${fdtfile}
fdt addr ${fdt_addr_r}
fdt resize 65536
for overlay_file in ${overlays}; do
	if load ${devtype} ${devnum} ${load_addr} ${prefix}dtb/allwinner/overlay/${overlay_prefix}-${overlay_file}.dtbo; then
		echo "Applying DT overlay ${overlay_file}"
		fdt apply ${load_addr} || setenv overlay_error "true"
	fi
done
for overlay_file in ${user_overlays}; do
	if load ${devtype} ${devnum} ${load_addr} ${prefix}overlay-user/${overlay_file}.dtbo; then
		echo "Applying user DT overlay ${overlay_file}"
		fdt apply ${load_addr} || setenv overlay_error "true"
	fi
done
if test "${overlay_error}" = "true"; then
	echo "Error applying DT overlays, restoring original DT"
	load ${devtype} ${devnum} ${fdt_addr_r} ${prefix}dtb/${fdtfile}
fi
booti ${kernel_addr_r} - ${fdt_addr_r}
EOF
mkimage -C none -A arm -T script -d "$R/boot/boot.cmd" "$R/boot/boot.scr" | head -3
cat > "$R/boot/armbianEnv.txt" <<'EOF'
verbosity=7
console=both
fdtfile=allwinner/sun60i-a733-orangepi-zero3w.dtb
overlay_prefix=sun60i-a733
overlays=uart2 i2c0 i2c1 pwm0 spi3-cs0-cs1-spidev
user_overlays=a733-fan
extraargs=coherent_pool=2M cma=512M no_console_suspend fsck.fix=yes fsck.repair=yes
EOF

# --- GPU: apercel, offene Firmware, Hilfsdienste ---
F=$S/armbian-a733-gpu/files
install -Dm644 "$B/dl/fw/rogue_36.56.104.183_v1.fw" "$R/usr/lib/firmware/apercel/rogue_36.56.104.183_v1.fw"
install -Dm644 "$S/apercel/conf/99-apercel.conf" "$R/etc/modprobe.d/99-apercel.conf"
install -Dm755 "$F/sbin/apercel-boot-tune" "$R/usr/local/sbin/apercel-boot-tune"
install -Dm644 "$F/systemd/gpu-cpu-perf.service" "$R/etc/systemd/system/gpu-cpu-perf.service"
install -Dm755 "$F/tools/a733-gpu-check" "$R/usr/local/bin/a733-gpu-check"
install -Dm755 "$F/fan/a733-fan-control" "$R/usr/local/sbin/a733-fan-control"
install -Dm644 "$F/fan/a733-fan-control.service" "$R/etc/systemd/system/a733-fan-control.service"
dtc -@ -q -I dts -O dtb -o "$R/boot/overlay-user/a733-fan.dtbo" "$F/overlay/a733-fan.dts"
sed -i 's/\r$//' "$R/usr/local/sbin/apercel-boot-tune" "$R/usr/local/sbin/a733-fan-control" "$R/usr/local/bin/a733-gpu-check" \
  "$R/etc/systemd/system/gpu-cpu-perf.service" "$R/etc/systemd/system/a733-fan-control.service"

# --- WLAN/Bluetooth-Firmware ---
install -d "$R/usr/lib/firmware/aic8800/SDIO"
rm -rf "$R/usr/lib/firmware/aic8800/SDIO/aic8800D80"
cp -a "$S/armbian-firmware/aic8800/SDIO/aic8800D80" "$R/usr/lib/firmware/aic8800/SDIO/"
ln -sfn aic8800/SDIO/aic8800D80 "$R/usr/lib/firmware/aic8800d80"
install -Dm644 "$A/packages/bsp/sunxi/aic8800-bluetooth.service" "$R/etc/systemd/system/aic8800-bluetooth.service"
sed -i 's#/usr/sbin/rfkill#/usr/bin/rfkill#' "$R/etc/systemd/system/aic8800-bluetooth.service"

# --- NPU-Laufzeit ---
install -d "$R/usr/lib/sun60iw2-npu" "$R/opt"
cp -a "$S"/npu-pkgs/npu/usr/lib/. "$R/usr/lib/sun60iw2-npu/"
cp -a "$S"/npu-pkgs/npu/usr/include/. "$R/usr/include/"
cp -a "$S"/npu-pkgs/npu/opt/. "$R/opt/"
install -d "$R/etc/ld.so.conf.d"

# --- CachyOS-Einstellungen: nur was auf ARM sinnvoll ist ---
C=$S/CachyOS-Settings/usr
install -Dm644 "$C/lib/sysctl.d/70-cachyos-settings.conf" "$R/usr/lib/sysctl.d/70-cachyos-settings.conf"
install -Dm644 "$C/lib/systemd/zram-generator.conf" "$R/usr/lib/systemd/zram-generator.conf"
install -Dm644 "$C/lib/udev/rules.d/30-zram.rules" "$R/usr/lib/udev/rules.d/30-zram.rules"
install -Dm644 "$C/lib/udev/rules.d/60-ioschedulers.rules" "$R/usr/lib/udev/rules.d/60-ioschedulers.rules"
install -Dm644 "$C/lib/systemd/system.conf.d/10-limits.conf" "$R/usr/lib/systemd/system.conf.d/10-limits.conf"
install -Dm644 "$C/lib/systemd/user.conf.d/10-limits.conf" "$R/usr/lib/systemd/user.conf.d/10-limits.conf"
install -Dm644 "$C/lib/systemd/journald.conf.d/00-journal-size.conf" "$R/usr/lib/systemd/journald.conf.d/00-journal-size.conf"
install -Dm644 "$C/lib/tmpfiles.d/thp.conf" "$R/usr/lib/tmpfiles.d/thp.conf"
install -Dm755 "$C/bin/topmem" "$R/usr/local/bin/topmem"
install -d "$R/usr/share/wallpapers/cachyos-wallpapers"
cp "$S"/cachyos-wallpapers/usr/share/wallpapers/cachyos-wallpapers/Cachy_Topography*.jpg \
   "$S"/cachyos-wallpapers/usr/share/wallpapers/cachyos-wallpapers/CachyOS_Moon.jpg \
   "$R/usr/share/wallpapers/cachyos-wallpapers/"
install -d "$R/usr/share/cachyos-fish-config/conf.d" "$R/etc/skel/.config/fish"
cp "$S/cachyos-fish-config/cachyos-config.fish" "$R/usr/share/cachyos-fish-config/"
cp "$S/cachyos-fish-config/conf.d/done.fish" "$R/usr/share/cachyos-fish-config/conf.d/"
cp "$S/cachyos-fish-config/config.fish" "$R/etc/skel/.config/fish/config.fish"

# --- Eigene Dateien ---
bash "$B/scripts/overlay.sh" "$R"
bash "$B/scripts/overlay2.sh" "$R"

# --- Zugangsdaten ---
if [ ! -f "$OUT/opi3w_ed25519" ]; then ssh-keygen -q -t ed25519 -N '' -C opi3w-test -f "$OUT/opi3w_ed25519"; fi
if [ ! -f "$OUT/benutzerpasswort.txt" ]; then
  (umask 077; openssl rand -base64 12 | tr -d '/+=' > "$OUT/benutzerpasswort.txt")
fi
PWH=$(openssl passwd -6 -stdin < "$OUT/benutzerpasswort.txt")
install -d -m700 "$R/root/.ssh"; install -m600 "$OUT/opi3w_ed25519.pub" "$R/root/.ssh/authorized_keys"
cp "$OUT"/mesa-*.pkg.tar.* "$R/root/"

# --- Im Chroot abschliessen ---
cat > "$R/root/finish.sh" <<EOF
set -e
sed -i 's/^CheckSpace/#CheckSpace/' /etc/pacman.conf
pacman -U --noconfirm /root/mesa-*.pkg.tar.*
pacman -Sy --noconfirm --needed alsa-utils
rm -f /root/mesa-*.pkg.tar.*
sed -i 's/^#\?IgnorePkg.*/IgnorePkg = mesa linux-aarch64/' /etc/pacman.conf
sed -i 's/^#CheckSpace/CheckSpace/' /etc/pacman.conf
echo orangepi-zero3w > /etc/hostname
ln -sf /usr/share/zoneinfo/Europe/Berlin /etc/localtime
sed -i 's/^#\(de_DE.UTF-8\)/\1/; s/^#\(en_US.UTF-8\)/\1/' /etc/locale.gen
locale-gen
echo LANG=de_DE.UTF-8 > /etc/locale.conf
printf 'KEYMAP=de-latin1\n' > /etc/vconsole.conf
printf 'PARTUUID=0a733a73-01 / ext4 rw,noatime 0 1\nPARTUUID=0a733a73-02 /opi3w-log vfat defaults,noatime,sync,umask=000,nofail,x-systemd.device-timeout=15 0 0\n' > /etc/fstab
rm -f /etc/systemd/network/eth* /etc/systemd/network/en* /etc/systemd/network/wl*
getent group gpio >/dev/null || groupadd -r gpio
id alarm >/dev/null 2>&1 && userdel -r alarm || true
id orangepi >/dev/null 2>&1 || useradd -m -G wheel,video,render,input,audio,gpio -s /usr/bin/fish orangepi
usermod -p '$PWH' orangepi
# Root ohne Passwort-Login, aber nicht gesperrt: SSH-Schluessel bleibt nutzbar.
usermod -p '*' root
install -d -m700 -o orangepi -g orangepi /home/orangepi/.ssh
install -m600 -o orangepi -g orangepi /root/.ssh/authorized_keys /home/orangepi/.ssh/authorized_keys
echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/10-wheel; chmod 440 /etc/sudoers.d/10-wheel
systemctl enable sddm NetworkManager bluetooth sshd systemd-networkd systemd-resolved systemd-timesyncd \
  aic8800-bluetooth gpu-cpu-perf a733-fan-control opi3w-usb-gadget opi3w-bootlog opi3w-klog opi3w-growroot opi3w-regdom
systemctl disable dhcpcd plasmalogin 2>/dev/null || true
systemctl mask systemd-networkd-wait-online.service NetworkManager-wait-online.service
ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
systemctl set-default graphical.target
depmod $KV
ldconfig
pacman -Scc --noconfirm >/dev/null
rm -f /etc/machine-id; touch /etc/machine-id
rm -f /root/*.sh
EOF
arch-chroot "$R" bash /root/finish.sh
rm -rf "$T"
du -sh "$R"
date; echo FERTIG
