#!/bin/bash
# KDE Plasma und Anwendungen ins Ziel-Rootfs installieren.
set -euo pipefail
B=/root/opi3w; R=$B/rootfs
exec > >(tee -a "$B/logs/packages.log") 2>&1
date
cat > "$R/root/pkgs.sh" <<'EOF'
set -e
W="plasma-meta sddm konsole dolphin kate ark spectacle gwenview okular kcalc partitionmanager
firefox firefox-i18n-de networkmanager plasma-nm bluez bluez-utils bluez-deprecated-tools
pipewire pipewire-alsa pipewire-pulse wireplumber xorg-xwayland kscreen
fish starship fastfetch htop btop sudo openssh usbutils pciutils i2c-tools libgpiod iw wireless-regdb rfkill util-linux
zram-generator noto-fonts noto-fonts-emoji ttf-dejavu ttf-fira-code hunspell-de
vulkan-tools mesa-utils rsync git nano vim parted dosfstools e2fsprogs wget curl python base-devel lsof"
ok=""
for p in $W; do
  if pacman -Si "$p" >/dev/null 2>&1 || pacman -Sg "$p" >/dev/null 2>&1; then ok="$ok $p"; else echo "NICHT VERFUEGBAR: $p"; fi
done
pacman -Syu --noconfirm --needed $ok
pacman -Qq | wc -l
pacman -Q mesa kwin plasma-desktop sddm plasma-login-manager 2>&1
EOF
arch-chroot "$R" bash /root/pkgs.sh
du -sh "$R"
date; echo FERTIG
