#!/bin/bash
# Korrekturen aus dem Hardware-Test. Aufruf: overlay2.sh <rootfs>
set -euo pipefail
R=$1
S=$(dirname "$(readlink -f "$0")")

# USB-C als Hauptanzeige mit Modusauswahl ueber die Nummer.
install -m755 "$S/display-setup.sh" "$R/usr/local/bin/opi3w-display-setup"

# Design und Hintergrund erst setzen, wenn plasmashell laeuft.
cat > "$R/usr/local/bin/opi3w-first-login" <<'EOF'
#!/bin/bash
# Einmalig pro Benutzer: dunkles Design und Hintergrundbild im CachyOS-Stil.
S=${XDG_STATE_HOME:-$HOME/.local/state}/opi3w-first-login; [ -e "$S" ] && exit 0
for _ in $(seq 1 60); do
	systemctl --user is-active -q plasma-plasmashell && busctl --user status org.kde.plasmashell >/dev/null 2>&1 && break
	sleep 2
done
sleep 5
lookandfeeltool -a org.kde.breezedark.desktop
plasma-apply-wallpaperimage /usr/share/wallpapers/cachyos-wallpapers/Cachy_Topography.jpg || exit 1
mkdir -p "$(dirname "$S")"; touch "$S"
EOF
chmod 755 "$R/usr/local/bin/opi3w-first-login"

# Grafik: Qt Quick direkt ueber Vulkan. OpenGL ueber zink bleibt in Wayland-Fenstern schwarz,
# ohne GALLIUM_DRIVER=zink fallen OpenGL-Programme dagegen sauber auf Software zurueck.
sed -i '/^GALLIUM_DRIVER=/d; /^KWIN_FORCE_SW_CURSOR=/d; /^QSG_RHI_BACKEND=/d' "$R/etc/environment"
echo 'QSG_RHI_BACKEND=vulkan' >> "$R/etc/environment"
grep -q '^PVR_I_WANT' "$R/etc/environment" || echo 'PVR_I_WANT_A_BROKEN_VULKAN_DRIVER=1' >> "$R/etc/environment"
printf 'PVR_I_WANT_A_BROKEN_VULKAN_DRIVER=1\nQSG_RHI_BACKEND=vulkan\n' > "$R/etc/environment.d/90-opi3w.conf"
sed -i 's/^GreeterEnvironment=.*/GreeterEnvironment=PVR_I_WANT_A_BROKEN_VULKAN_DRIVER=1,QSG_RHI_BACKEND=vulkan/' "$R/etc/sddm.conf.d/10-opi3w.conf"
# KWin rendert selbst ueber OpenGL ES und nutzt Qt Quick intern: dort kein Vulkan erzwingen.
install -d "$R/etc/systemd/user/plasma-kwin_wayland.service.d"
printf '[Service]\nUnsetEnvironment=QSG_RHI_BACKEND GALLIUM_DRIVER\n' > "$R/etc/systemd/user/plasma-kwin_wayland.service.d/10-opi3w.conf"
# Der Startbildschirm scheitert sonst als erster Grafik-Client an der GPU.
printf '[KSplash]\nEngine=none\nTheme=None\n' > "$R/etc/xdg/ksplashrc"
install -m644 "$R/etc/xdg/ksplashrc" "$R/etc/skel/.config/ksplashrc"

# Deutsche Tastatur auch in Plasma.
install -d "$R/etc/X11/xorg.conf.d"
cat > "$R/etc/X11/xorg.conf.d/00-keyboard.conf" <<'EOF'
Section "InputClass"
	Identifier "system-keyboard"
	MatchIsKeyboard "on"
	Option "XkbLayout" "de"
EndSection
EOF
printf '[Layout]\nLayoutList=de\nUse=true\n' > "$R/etc/skel/.config/kxkbrc"

# WLAN-Land: cfg80211 ist fest im Kernel und findet die Datenbank beim Booten noch nicht.
cat > "$R/etc/systemd/system/opi3w-regdom.service" <<'EOF'
[Unit]
Description=WLAN-Land auf Deutschland setzen
After=sys-subsystem-net-devices-wlan0.device network-pre.target
Wants=network-pre.target
[Service]
Type=oneshot
ExecStartPre=-/usr/bin/iw reg reload
ExecStart=/usr/bin/iw reg set DE
[Install]
WantedBy=multi-user.target
EOF

# NPU-Bibliotheken nur fuer NPU-Programme: Sie wuerden sonst libjpeg und libpng des Systems ueberdecken.
rm -f "$R/etc/ld.so.conf.d/zz-sun60iw2-npu.conf"
ln -sf sun60iw2-npu/libVIPhal.so "$R/usr/lib/libVIPhal.so"
ln -sf sun60iw2-npu/libNBGlinker.so "$R/usr/lib/libNBGlinker.so"
cat > "$R/usr/local/bin/opi3w-npu-run" <<'EOF'
#!/bin/bash
# Startet ein NPU-Programm mit den mitgelieferten Bibliotheken, ohne das System zu beeinflussen.
export LD_LIBRARY_PATH=/usr/lib/sun60iw2-npu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
exec "$@"
EOF
chmod 755 "$R/usr/local/bin/opi3w-npu-run"

# Ein schon im Rootfs angelegtes Benutzerkonto bekommt dieselben Voreinstellungen.
if [ -d "$R/home/orangepi/.config" ]; then
	for f in ksplashrc kxkbrc; do install -m644 -o 1000 -g 1000 "$R/etc/skel/.config/$f" "$R/home/orangepi/.config/$f"; done
fi

# Testzugang: Anmeldung ueber USB nur noch mit Passwort oder SSH-Schluessel.
rm -rf "$R/etc/systemd/system/serial-getty@ttyGS0.service.d"

# Ton: USB-C/DisplayPort zuerst, HDMI danach, kein leerer Aufnahmeeingang.
install -d "$R/etc/wireplumber/wireplumber.conf.d"
install -m644 "$S/60-opi3w-audio.conf" "$R/etc/wireplumber/wireplumber.conf.d/60-opi3w-audio.conf"

# USB-C-Controller nach einem Haenger zuruecksetzen, sonst fehlen Maus und Tastatur.
install -m755 "$S/opi3w-usb-recover" "$R/usr/local/bin/opi3w-usb-recover"
install -m644 "$S/opi3w-usb-recover.service" "$R/etc/systemd/system/opi3w-usb-recover.service"
install -d "$R/etc/systemd/system/multi-user.target.wants"
ln -sf ../opi3w-usb-recover.service "$R/etc/systemd/system/multi-user.target.wants/opi3w-usb-recover.service"

# WLAN: Der Chip scheitert an WPA3, Plasma legt fuer Mischnetze aber WPA3-Profile an.
install -m755 "$S/opi3w-wifi-wpa2" "$R/usr/local/bin/opi3w-wifi-wpa2"
install -m644 "$S/opi3w-wifi-wpa2.service" "$S/opi3w-wifi-wpa2.path" "$R/etc/systemd/system/"
ln -sf ../opi3w-wifi-wpa2.path "$R/etc/systemd/system/multi-user.target.wants/opi3w-wifi-wpa2.path"
