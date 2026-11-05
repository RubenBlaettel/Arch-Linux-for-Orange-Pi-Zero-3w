#!/bin/bash
# Legt alle eigenen Dateien des Systems im Rootfs ab. Aufruf: overlay.sh <rootfs>
set -euo pipefail
R=$1
install -d "$R/usr/local/sbin" "$R/usr/local/bin" "$R/etc/systemd/system" "$R/etc/systemd/network" \
  "$R/etc/sddm.conf.d" "$R/etc/NetworkManager/conf.d" "$R/etc/modules-load.d" "$R/etc/modprobe.d" \
  "$R/etc/udev/rules.d" "$R/etc/xdg/autostart" "$R/etc/ssh/sshd_config.d" "$R/opi3w-log" \
  "$R/etc/skel/.config" "$R/etc/systemd/system/serial-getty@ttyGS0.service.d" "$R/etc/ld.so.conf.d"

# --- USB-Testzugang: Netzwerk (NCM) + serielle Konsole (ACM) am Stromanschluss ---
cat > "$R/usr/local/sbin/opi3w-usb-gadget" <<'EOF'
#!/bin/bash
# Richtet das USB-Geraet am Stromanschluss (usbc0) ein. DWC3 gehoert dem USB-C-Monitoranschluss.
log() { echo "[usb-gadget] $*"; }
modprobe libcomposite 2>/dev/null
mountpoint -q /sys/kernel/config || mount -t configfs none /sys/kernel/config
G=/sys/kernel/config/usb_gadget/opi3w
udc=""
for _ in $(seq 1 60); do
	for u in /sys/class/udc/*; do
		[ -e "$u" ] || continue
		n=$(basename "$u")
		case "$n" in *dwc3*|*.usb3*) continue ;; esac
		udc=$n; break
	done
	[ -n "$udc" ] && break
	sleep 1
done
log "UDCs: $(ls /sys/class/udc 2>/dev/null | tr '\n' ' ') gewaehlt: ${udc:-keiner}"
[ -n "$udc" ] || exit 1
mkdir -p "$G/strings/0x409" "$G/configs/c.1/strings/0x409" "$G/functions/ncm.usb0" "$G/functions/acm.GS0"
echo 0x1d6b > "$G/idVendor"
echo 0x0104 > "$G/idProduct"
echo 0x0100 > "$G/bcdDevice"
echo 0x0200 > "$G/bcdUSB"
echo 0xEF > "$G/bDeviceClass"
echo 0x02 > "$G/bDeviceSubClass"
echo 0x01 > "$G/bDeviceProtocol"
echo "OrangePi" > "$G/strings/0x409/manufacturer"
echo "OPi Zero 3W Test" > "$G/strings/0x409/product"
tr -d '\0' < /proc/device-tree/serial-number 2>/dev/null > "$G/strings/0x409/serialnumber" || echo 0001 > "$G/strings/0x409/serialnumber"
echo "NCM+ACM" > "$G/configs/c.1/strings/0x409/configuration"
echo 250 > "$G/configs/c.1/MaxPower"
ln -sf "$G/functions/ncm.usb0" "$G/configs/c.1/"
ln -sf "$G/functions/acm.GS0" "$G/configs/c.1/"
echo "$udc" > "$G/UDC" || { log "UDC-Bindung fehlgeschlagen"; exit 1; }
log "aktiv auf $udc"
systemctl start --no-block serial-getty@ttyGS0.service
EOF
cat > "$R/etc/systemd/system/opi3w-usb-gadget.service" <<'EOF'
[Unit]
Description=USB-Testzugang (NCM + ACM) am Stromanschluss
After=systemd-modules-load.service sys-kernel-config.mount
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/opi3w-usb-gadget
[Install]
WantedBy=multi-user.target
EOF
cat > "$R/etc/systemd/network/50-usb0.network" <<'EOF'
[Match]
Name=usb0
[Network]
Address=10.55.0.1/24
DHCPServer=yes
LinkLocalAddressing=no
[DHCPServer]
PoolOffset=10
PoolSize=10
EmitDNS=no
EmitRouter=no
EOF
cat > "$R/etc/NetworkManager/conf.d/10-opi3w.conf" <<'EOF'
[keyfile]
unmanaged-devices=interface-name:usb0
EOF
cat > "$R/etc/ssh/sshd_config.d/10-opi3w.conf" <<'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin prohibit-password
EOF

# --- Protokolle auf die FAT-Partition (am Windows-PC lesbar) ---
cat > "$R/usr/local/sbin/opi3w-bootlog" <<'EOF'
#!/bin/bash
# Schreibt den Systemzustand nach /opi3w-log/boot-N. Aufruf: opi3w-bootlog snapshot|start
L=/opi3w-log
mountpoint -q "$L" || exit 0
N=$(cat "$L/.bootcount" 2>/dev/null || echo 0)
if [ "$1" = start ]; then
	N=$((N + 1)); echo "$N" > "$L/.bootcount"
	mkdir -p "$L/boot-$N"
	ls -d "$L"/boot-* 2>/dev/null | sort -t- -k2 -n | head -n -10 | xargs -r rm -rf
	sync; exit 0
fi
D=$L/boot-$N; mkdir -p "$D"
snap() { "${@:2}" > "$D/$1.txt" 2>&1; }
snap uptime uptime
snap kernel uname -a
snap dmesg dmesg -T
snap journal journalctl -b --no-pager
snap failed systemctl --failed --no-pager
snap units systemctl list-units --no-pager
snap lsmod lsmod
snap lsusb lsusb -t
snap ip ip -br addr
snap udc ls -la /sys/class/udc
snap typec bash -c 'for f in /sys/class/typec/*/*; do [ -f "$f" ] && echo "$f: $(cat "$f" 2>/dev/null)"; done'
snap dri ls -la /dev/dri /dev/vipcore
snap gpu /usr/local/bin/a733-gpu-check
snap thermal bash -c 'for z in /sys/class/thermal/thermal_zone*; do echo "$(cat $z/type) $(cat $z/temp)"; done'
snap drm bash -c 'for c in /sys/class/drm/card*-*; do echo "== $c status=$(cat $c/status) enabled=$(cat $c/enabled)"; cat $c/modes; done'
snap drm_info drm_info
for e in /sys/class/drm/card*-*/edid; do
	[ -s "$e" ] && cp "$e" "$D/edid-$(basename "$(dirname "$e")").bin"
done
sync
EOF
cat > "$R/etc/systemd/system/opi3w-bootlog.service" <<'EOF'
[Unit]
Description=Systemzustand regelmaessig auf die FAT-Partition schreiben
DefaultDependencies=no
RequiresMountsFor=/opi3w-log
Conflicts=shutdown.target
[Service]
Type=simple
ExecStartPre=/usr/local/sbin/opi3w-bootlog start
ExecStart=/bin/bash -c 'for t in 5 15 30 30 30 60 60 120 300 600; do /usr/local/sbin/opi3w-bootlog snapshot; sleep $t; done; /usr/local/sbin/opi3w-bootlog snapshot'
[Install]
WantedBy=multi-user.target
EOF
cat > "$R/etc/systemd/system/opi3w-klog.service" <<'EOF'
[Unit]
Description=Kernel-Meldungen live auf die FAT-Partition schreiben
DefaultDependencies=no
After=opi3w-bootlog.service
RequiresMountsFor=/opi3w-log
Conflicts=shutdown.target
[Service]
ExecStart=/bin/bash -c 'exec dmesg -w -T >> "/opi3w-log/boot-$(cat /opi3w-log/.bootcount)/kmsg-live.txt"'
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF

# --- Rootfs beim ersten Start auf die volle Kartengroesse erweitern ---
cat > "$R/usr/local/sbin/opi3w-growroot" <<'EOF'
#!/bin/bash
set -eu
src=$(findmnt -no SOURCE /)
disk=/dev/$(lsblk -no PKNAME "$src")
part=$(cat "/sys/class/block/$(basename "$src")/partition")
echo ", +" | sfdisk --no-reread --force -N "$part" "$disk"
partx -u "$disk" || true
resize2fs "$src"
systemctl disable opi3w-growroot.service
EOF
cat > "$R/etc/systemd/system/opi3w-growroot.service" <<'EOF'
[Unit]
Description=Rootfs auf volle Kartengroesse erweitern (einmalig)
After=local-fs.target
[Service]
Type=oneshot
ExecStart=/usr/local/sbin/opi3w-growroot
[Install]
WantedBy=multi-user.target
EOF

# --- Treiber laden ---
cat > "$R/etc/modules-load.d/opi3w.conf" <<'EOF'
aic8800_bsp
aic8800_fdrv
aic8800_btlpm
apercel
vipcore
EOF
cat > "$R/etc/udev/rules.d/99-sun60iw2-permissions.rules" <<'EOF'
KERNEL=="system", SUBSYSTEM=="dma_heap", GROUP="video", MODE="0660"
KERNEL=="reserved", SUBSYSTEM=="dma_heap", GROUP="video", MODE="0660"
KERNEL=="sunxi_soc_info", GROUP="video", MODE="0660"
KERNEL=="renderD128", SUBSYSTEM=="drm", GROUP="render", MODE="0660"
KERNEL=="cedar_dev", GROUP="video", MODE="0660"
KERNEL=="cedar_dev_ve2", GROUP="video", MODE="0660"
KERNEL=="g2d", GROUP="video", MODE="0660"
KERNEL=="vipcore", GROUP="video", MODE="0660"
KERNEL=="gpiochip*", GROUP="gpio", MODE="0660"
KERNEL=="i2c-[0-9]*", GROUP="gpio", MODE="0660"
KERNEL=="spidev*", GROUP="gpio", MODE="0660"
EOF

# --- Plasma: USB-C als Standardausgabe, schonende Voreinstellungen ---
cat > "$R/etc/sddm.conf.d/10-opi3w.conf" <<'EOF'
[General]
DisplayServer=wayland
GreeterEnvironment=KWIN_FORCE_SW_CURSOR=1,PVR_I_WANT_A_BROKEN_VULKAN_DRIVER=1
[Autologin]
User=orangepi
Session=plasma
[Wayland]
CompositorCommand=kwin_wayland --drm --no-lockscreen --no-global-shortcuts --locale1
EOF
grep -q KWIN_FORCE_SW_CURSOR "$R/etc/environment" 2>/dev/null || echo 'KWIN_FORCE_SW_CURSOR=1' >> "$R/etc/environment"
# Der Mesa-PowerVR-Treiber laeuft auf nicht offiziell konformer Hardware nur mit dieser Freigabe.
grep -q PVR_I_WANT "$R/etc/environment" 2>/dev/null || echo 'PVR_I_WANT_A_BROKEN_VULKAN_DRIVER=1' >> "$R/etc/environment"
install -d "$R/etc/environment.d"
printf 'KWIN_FORCE_SW_CURSOR=1\nPVR_I_WANT_A_BROKEN_VULKAN_DRIVER=1\n' > "$R/etc/environment.d/90-opi3w.conf"
cat > "$R/usr/local/bin/opi3w-display-setup" <<'EOF'
#!/bin/bash
# USB-C (DP-1) als primaere Ausgabe mit der groessten Aufloesung, die die GPU noch beschleunigen kann.
LOG=${XDG_STATE_HOME:-$HOME/.local/state}/opi3w-display.log; mkdir -p "$(dirname "$LOG")"
exec >> "$LOG" 2>&1
date
strip() { sed 's/\x1b\[[0-9;]*m//g'; }
for _ in $(seq 1 30); do
	o=$(kscreen-doctor -o | strip)
	echo "$o" | grep -q 'DP-1' && break
	sleep 2
done
echo "$o"
echo "$o" | grep -q 'DP-1' || exit 0
modes=$(echo "$o" | awk '/Output: .*DP-1/{f=1;next} /Output:/{f=0} f' | grep -oE '[0-9]+x[0-9]+@[0-9]+' | sort -u)
sel=""
for w in 3840x1080@60 2560x1440@60 2560x1080@60 1920x1080@60; do
	echo "$modes" | grep -qx "$w" && { sel=$w; break; }
done
echo "gewaehlt: ${sel:-keine Vorgabe}"
args=(output.DP-1.enable output.DP-1.priority.1 output.DP-1.scale.1)
[ -n "$sel" ] && args+=("output.DP-1.mode.$sel")
kscreen-doctor "${args[@]}"
EOF
cat > "$R/etc/xdg/autostart/opi3w-display-setup.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=USB-C als Hauptanzeige
Exec=/usr/local/bin/opi3w-display-setup
X-KDE-autostart-phase=1
NoDisplay=true
EOF
cat > "$R/usr/local/bin/opi3w-first-login" <<'EOF'
#!/bin/bash
# Einmalig pro Benutzer: dunkles Design und Hintergrundbild im CachyOS-Stil.
S=${XDG_STATE_HOME:-$HOME/.local/state}/opi3w-first-login; [ -e "$S" ] && exit 0
sleep 8
lookandfeeltool -a org.kde.breezedark.desktop
plasma-apply-wallpaperimage /usr/share/wallpapers/cachyos-wallpapers/Cachy_Topography.jpg
mkdir -p "$(dirname "$S")"; touch "$S"
EOF
cat > "$R/etc/xdg/autostart/opi3w-first-login.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Ersteinrichtung
Exec=/usr/local/bin/opi3w-first-login
NoDisplay=true
EOF
cat > "$R/etc/skel/.config/kwinrc" <<'EOF'
[Plugins]
shakecursorEnabled=false
blurEnabled=false
contrastEnabled=false
slidingpopupsEnabled=false
EOF
cat > "$R/etc/skel/.config/kdeglobals" <<'EOF'
[KDE]
AnimationDurationFactor=0
LookAndFeelPackage=org.kde.breezedark.desktop
EOF
cat > "$R/etc/skel/.config/baloofilerc" <<'EOF'
[Basic Settings]
Indexing-Enabled=false
EOF
cat > "$R/etc/skel/.config/kscreenlockerrc" <<'EOF'
[Daemon]
Autolock=false
EOF

# --- GPIO-/Bus-Hilfe ---
cat > "$R/usr/local/bin/opi3w-pins" <<'EOF'
#!/bin/bash
# Stiftleiste: Overlays anzeigen und in /boot/armbianEnv.txt aktivieren.
E=/boot/armbianEnv.txt; O=/boot/dtb/allwinner/overlay
case "${1:-}" in
list) ls "$O" | sed -n 's/^sun60i-a733-\(.*\)\.dtbo$/\1/p'; echo "--- aktiv:"; grep '^overlays=' "$E" ;;
enable) shift; cur=$(sed -n 's/^overlays=//p' "$E"); sed -i '/^overlays=/d' "$E"; echo "overlays=$cur $*" >> "$E"; echo "Neustart noetig." ;;
disable) shift; cur=$(sed -n 's/^overlays=//p' "$E"); for x in "$@"; do cur=$(echo " $cur " | sed "s/ $x / /"); done; sed -i '/^overlays=/d' "$E"; echo "overlays=$cur" >> "$E"; echo "Neustart noetig." ;;
*) echo "Aufruf: opi3w-pins list | enable <name..> | disable <name..>  (GPIO direkt: gpioinfo, gpioset, gpioget)" ;;
esac
EOF
chmod 755 "$R"/usr/local/sbin/opi3w-* "$R"/usr/local/bin/opi3w-*
sed -i 's/\r$//' "$R"/usr/local/sbin/opi3w-* "$R"/usr/local/bin/opi3w-*
