#!/bin/bash
# Prueft das fertige Rootfs vor dem Image-Bau.
B=/root/opi3w; R=$B/rootfs
for f in usr/bin/hciattach usr/bin/rfkill usr/bin/kscreen-doctor usr/bin/lookandfeeltool usr/bin/plasma-apply-wallpaperimage usr/bin/gpioinfo usr/bin/fish usr/bin/starship usr/bin/fastfetch usr/bin/resize2fs usr/bin/sfdisk usr/bin/partx usr/bin/lsusb usr/bin/vulkaninfo usr/bin/eglinfo; do
  [ -e "$R/$f" ] && echo "ok  $f" || echo "FEHLT $f"
done
ls "$R/usr/share/vulkan/icd.d/" "$R/usr/lib/gbm" "$R/usr/share/glvnd/egl_vendor.d" 2>&1
ls "$R/usr/share/wayland-sessions/" 2>&1
cat > "$R/root/c.sh" <<'EOF'
pacman -Q mesa kwin systemd
ldd /usr/lib/libgbm.so.1 | grep 'not found' || echo gbm-libs-ok
ldd /usr/bin/kwin_wayland | grep 'not found' || echo kwin-libs-ok
systemctl is-enabled sddm NetworkManager sshd systemd-networkd opi3w-usb-gadget opi3w-bootlog opi3w-klog opi3w-growroot gpu-cpu-perf aic8800-bluetooth a733-fan-control 2>&1 | paste -sd' '
systemd-analyze verify --no-pager opi3w-bootlog.service opi3w-klog.service opi3w-usb-gadget.service opi3w-growroot.service 2>&1 | head -10
modinfo -k 6.6.98-vendor-sun60iw2 apercel -F filename; modinfo -k 6.6.98-vendor-sun60iw2 vipcore -F filename
grep -c . /etc/fstab; cat /etc/fstab
id orangepi
EOF
arch-chroot "$R" bash /root/c.sh 2>&1 | grep -v 'is not a mountpoint'
rm -f "$R/root/c.sh"
