#!/bin/bash
# Arch-Linux-ARM-Basis herunterladen, pruefen und aktualisieren.
set -euo pipefail
B=/root/opi3w; R=$B/rootfs; DL=$B/dl; mkdir -p "$DL" "$B/logs"
exec > >(tee -a "$B/logs/rootfs-base.log") 2>&1
T=ArchLinuxARM-aarch64-latest.tar.gz
cd "$DL"
curl -fsSL --retry 3 -o "$T.md5" "http://os.archlinuxarm.org/os/$T.md5"
[ -f "$T" ] && md5sum -c "$T.md5" >/dev/null 2>&1 || curl -fsSL --retry 3 -o "$T" "http://os.archlinuxarm.org/os/$T"
md5sum -c "$T.md5"
ls -la "$T"

if [ ! -f "$R/.extracted" ]; then
  rm -rf "$R"; mkdir -p "$R"
  bsdtar -xpf "$T" -C "$R"
  touch "$R/.extracted"
fi

# Chroot-Eigenheiten: kein Landlock-Sandbox unter qemu, CheckSpace scheitert im Chroot.
sed -i 's/^CheckSpace/#CheckSpace/' "$R/etc/pacman.conf"
grep -q '^DisableSandbox' "$R/etc/pacman.conf" || sed -i '/^\[options\]/a DisableSandbox' "$R/etc/pacman.conf"
sed -i 's/^#\?ParallelDownloads.*/ParallelDownloads = 8/' "$R/etc/pacman.conf"
grep -n -E 'DisableSandbox|ParallelDownloads|CheckSpace|^Architecture' "$R/etc/pacman.conf"

cat > "$R/root/base-init.sh" <<'EOF'
#!/bin/bash
set -euo pipefail
uname -m
pacman-key --init
pacman-key --populate archlinuxarm
# Generischer Kernel und PC-Firmware werden auf diesem Board nicht gebraucht.
pacman -Qq | grep -E '^linux-(aarch64|firmware)' | xargs -r pacman -Rdd --noconfirm
pacman -Syyu --noconfirm --needed
echo "=== Versionen ==="
pacman -Si mesa libgbm vulkan-icd-loader libglvnd llvm clang libclc spirv-llvm-translator spirv-tools glslang \
  plasma-meta plasma-desktop kwin sddm plasma-login-manager networkmanager 2>/dev/null | grep -E '^(Repository|Name|Version|Provides|Depends On) ' | cut -c1-200
EOF
chmod +x "$R/root/base-init.sh"
arch-chroot "$R" /root/base-init.sh
du -sh "$R"
echo FERTIG
