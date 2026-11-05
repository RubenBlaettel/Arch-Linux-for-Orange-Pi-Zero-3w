#!/bin/bash
# Kernel + U-Boot mit dem Armbian-Framework bauen (Rezept fuer orangepizero3w, Branch vendor).
set -euo pipefail
B=/root/opi3w; S=$B/src; A=$S/armbian-build; UP=$A/userpatches; DL=$B/patches/dl
KP=$UP/kernel/archive/sun60iw2-opi-vendor
mkdir -p "$KP" "$UP/extensions" "$B/logs"
exec > >(tee -a "$B/logs/kernel.log") 2>&1

# --- Kernel-Patches ---
cp "$S/armbian-a733-gpu/armbian/userpatches/kernel/archive/sun60iw2-opi-vendor/"*.patch "$KP/"
cp "$DL/vendor-pr137.patch" "$KP/0013-usbc-dp-hpd-defer-and-generic-fbdev.patch"
cp "$DL/vendor-pr139.patch" "$KP/0014-combophy-enable-cmn-pll1-on-dp-usb-path.patch"
# DisplayPort-Ton, HDMI-Korrekturen und Kanalaufteilung.
cp "$B/patches/kernel/"00{17..25}-*.patch "$KP/"

# Stromanschluss (usbc0, USB 2.0) fest als USB-Geraet: Testzugang zum PC.
cd "$S/linux"
D=arch/arm64/boot/dts/allwinner/sun60i-a733-orangepi-zero3w.dts
git checkout -q -- "$D"
python3 - "$D" <<'PY'
import re,sys
p=sys.argv[1]; s=open(p,encoding='utf-8',errors='surrogateescape').read()
s2,n=re.subn(r'(&usbc0 \{\n\tdevice_type = "usbc0";\n\tusb_port_type = )<0x2>;', r'\1<0x0>;', s)
assert n==1, "usbc0-Block nicht gefunden"
open(p,'w',encoding='utf-8',errors='surrogateescape').write(s2)
PY
{ cat <<'EOF'
From 0000000000000000000000000000000000000000 Mon Sep 17 00:00:00 2001
From: opi3w build <build@localhost>
Date: Wed, 4 Nov 2026 20:00:00 +0100
Subject: [PATCH] orangepizero3w: usbc0 as USB device for PC test access

---
EOF
git diff -- "$D"; } > "$KP/0015-orangepizero3w-usbc0-device-mode.patch"
git checkout -q -- "$D"
grep -c '^[-+]\s*usb_port_type' "$KP/0015-orangepizero3w-usbc0-device-mode.patch"

# GPU-Texturen enden bei 4096 Pixeln: breitere Modi wuerden den Compositor scheitern lassen.
E=bsp/drivers/drm/sunxi_drm_edp.c
git checkout -q -- "$E"
python3 - "$E" <<'PY'
import sys
p=sys.argv[1]; s=open(p,encoding='utf-8',errors='surrogateescape').read()
a="""	drm_mode_to_sunxi_video_timings((struct drm_display_mode *)mode, &timings);

	/* abandon the resolution can't be handle by display engine */"""
b="""	/* the GPU cannot composite wider surfaces (maxImageDimension2D = 4096) */
	if (mode->hdisplay > 4096)
		return MODE_BAD;

"""+a
assert s.count(a)==1, "Stelle in mode_valid nicht eindeutig"
open(p,'w',encoding='utf-8',errors='surrogateescape').write(s.replace(a,b))
PY
{ cat <<'EOF'
From 0000000000000000000000000000000000000000 Mon Sep 17 00:00:00 2001
From: opi3w build <build@localhost>
Date: Wed, 4 Nov 2026 20:00:00 +0100
Subject: [PATCH] sunxi-drm: edp: reject modes wider than the GPU can composite

---
EOF
git diff -- "$E"; } > "$KP/0016-sunxi-edp-limit-width-to-gpu-texture-size.patch"
git checkout -q -- "$E"
grep -c 'hdisplay > 4096' "$KP/0016-sunxi-edp-limit-width-to-gpu-texture-size.patch"

# --- apercel + Extensions ---
AP_REV=$(git -C "$S/apercel" rev-parse HEAD)
git -C "$S/apercel" status --short | head -3
sed "s/@APERCEL_REVISION@/$AP_REV/" "$S/armbian-a733-gpu/armbian/userpatches/extensions/apercel-a733.sh" > "$UP/extensions/apercel-a733.sh"
# Ein altes apercel.ko behaelt die BTF des vorigen Kernels und laesst sich dann nicht laden.
python3 - "$UP/extensions/apercel-a733.sh" <<'PY2'
import sys
p=sys.argv[1]; s=open(p).read()
a='\tdisplay_alert "Building apercel GPU module" "${kernel_version_family}" "info"\n'
assert s.count(a)==1
s=s.replace(a,a+'\t# opi3w: stale apercel.ko keeps the BTF of the previous vmlinux and then fails to load.\n\trun_host_command_logged rm -f "${APERCEL_DIR}/driver/apercel.ko" "${APERCEL_DIR}/driver/apercel.mod.o"\n')
open(p,'w').write(s)
PY2
rm -rf "$UP/apercel" "$UP/a733-opengpu"
rsync -a --exclude .git "$S/apercel/" "$UP/apercel/"
cp -r "$S/armbian-a733-gpu/files" "$UP/a733-opengpu"

cat > "$UP/extensions/opi3w-desktop.sh" <<'EOF'
# Kernel-Optionen fuer Arch Linux ARM mit systemd und KDE Plasma.
function custom_kernel_config__opi3w_desktop() {
	opts_y+=(FHANDLE SECCOMP SECCOMP_FILTER PSI SCHED_AUTOGROUP TCP_CONG_ADVANCED TCP_CONG_BBR ZSWAP CRYPTO_ZSTD BLK_DEV_INITRD RD_GZIP RD_ZSTD)
	opts_y+=(USB_CONFIGFS USB_CONFIGFS_ACM USB_CONFIGFS_NCM USB_CONFIGFS_SERIAL)
	opts_y+=(SND_SOC_SUNXI_CODEC_AV)
	opts_m+=(INPUT_UINPUT ZRAM)
}
EOF
find "$UP" -type f \( -name '*.sh' -o -name '*.patch' \) -exec sed -i 's/\r$//' {} +
ls -1 "$KP"

cd "$A"
args=(BOARD=orangepizero3w BRANCH=vendor RELEASE=trixie KERNEL_CONFIGURE=no BUILD_MINIMAL=no BUILD_DESKTOP=no
      ENABLE_EXTENSIONS=apercel-a733,opi3w-desktop PREFER_DOCKER=no SHARE_LOGS=no SKIP_LOG_ARCHIVE=yes
      A733_DESKTOP=none A733_AUTOLOGIN=no EXPERT=yes)
echo "=== KERNEL $(date) ==="; ./compile.sh kernel "${args[@]}"
echo "=== UBOOT $(date) ===";  ./compile.sh uboot  "${args[@]}"
echo "=== FERTIG $(date) ==="; ls -la output/debs/ | tail -20
