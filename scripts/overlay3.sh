#!/bin/bash
# Leistung: Lag-Spikes und Programmstarts, alle Werte am SBC gemessen.
# Aufruf: overlay3.sh <rootfs> (auch am laufenden System mit "/" nutzbar).
set -euo pipefail
R=${1%/}

install -d "$R/etc/sysctl.d" "$R/etc/environment.d" "$R/etc/NetworkManager/conf.d" \
  "$R/etc/systemd/user/plasma-kwin_wayland.service.d" \
  "$R/etc/systemd/system/opi3w-klog.service.d" "$R/etc/systemd/system/opi3w-bootlog.service.d" \
  "$R/etc/systemd/system/graphical.target.wants" "$R/etc/systemd/system/multi-user.target.wants" \
  "$R/usr/local/bin" "$R/usr/local/sbin" "$R/usr/lib/firefox/browser/defaults/preferences"

# Kernel:
# - Mit CONFIG_RT_GROUP_SCHED lehnt der Kernel Echtzeit in Cgroups ohne RT-Budget mit EPERM ab,
#   KWin lief dadurch als normale Aufgabe. Ohne globale RT-Bandbreite entfaellt diese Pruefung.
# - Jede Fehlermeldung ginge sonst mit 115200 Baud ueber die Konsole, bei gesperrten Interrupts.
cat > "$R/etc/sysctl.d/90-opi3w-perf.conf" <<'EOF'
kernel.sched_rt_runtime_us = -1
kernel.printk = 1 4 1 3
EOF

# powerdevil fragt ueber libddcutil alle I2C-Busse ab. Das erzeugt Fehlerstuerme auf den Bussen und
# fragt alle 27 s den Monitor ab. Helligkeit daher am Monitor einstellen.
echo 'POWERDEVIL_NO_DDCUTIL=1' > "$R/etc/environment.d/91-opi3w-perf.conf"

# KWin: Software-Helligkeit zwingt jeden Bildpunkt durch den Farbraum-Shader. Dessen viele Uniforms
# laedt der PowerVR-Compiler je Pixel aus dem Speicher: Vollbild 370 ms statt 47 ms.
# KWin liest die Einstellung nur beim Start und legt sie je Monitor an.
cat > "$R/usr/local/bin/opi3w-kwin-output-config" <<'EOF'
#!/bin/bash
J=${1:-$HOME/.config/kwinoutputconfig.json}
[ -f "$J" ] || exit 0
sed -i -E 's/("allowSdrSoftwareBrightness": *)true/\1false/; s/("brightness": *)[0-9.]+/\11/' "$J"
EOF
cat > "$R/etc/systemd/user/plasma-kwin_wayland.service.d/20-opi3w-perf.conf" <<'EOF'
[Service]
ExecStartPre=-/usr/local/bin/opi3w-kwin-output-config
EOF

# Die Datei entsteht erst in der ersten Sitzung: Danach die Sitzung einmal neu starten.
# Ein Neustart nur von KWin wuerde die Sitzung beenden und beim Anmeldebildschirm enden.
cat > "$R/usr/local/sbin/opi3w-kwin-first" <<'EOF'
#!/bin/bash
J=/home/orangepi/.config/kwinoutputconfig.json
for _ in $(seq 1 30); do [ -f "$J" ] && break; sleep 2; done
touch /var/lib/opi3w-kwin-first-done
grep -qE '"allowSdrSoftwareBrightness": *true' "$J" 2>/dev/null || exit 0
# Der Benutzer-Manager muss mit beendet werden, sonst stuerzt die neue Sitzung ab und es bleibt
# der Anmeldebildschirm.
systemctl stop sddm
sleep 2
systemctl stop user@1000.service
sleep 2
systemctl start sddm
EOF
cat > "$R/etc/systemd/system/opi3w-kwin-first.path" <<'EOF'
[Unit]
Description=Nach der ersten Anmeldung die KWin-Ausgabeeinstellung anwenden
ConditionPathExists=!/var/lib/opi3w-kwin-first-done
[Path]
PathExists=/home/orangepi/.local/state/opi3w-first-login
[Install]
WantedBy=multi-user.target
EOF
cat > "$R/etc/systemd/system/opi3w-kwin-first.service" <<'EOF'
[Unit]
Description=Sitzung einmalig mit angepasster KWin-Ausgabeeinstellung neu starten
ConditionPathExists=!/var/lib/opi3w-kwin-first-done
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/opi3w-kwin-first
EOF
ln -sf /etc/systemd/system/opi3w-kwin-first.path "$R/etc/systemd/system/multi-user.target.wants/opi3w-kwin-first.path"

# Boot-Protokolle: Die FAT-Partition ist synchron eingehaengt, jede Kernelzeile wird also sofort
# geschrieben und bremst Lesezugriffe auf der Karte. Nur den Start protokollieren.
# Bei Bedarf live: systemctl start opi3w-klog
cat > "$R/etc/systemd/system/opi3w-klog.service.d/10-opi3w-perf.conf" <<'EOF'
[Service]
ExecStart=
ExecStart=/bin/bash -c 'exec timeout 120 dmesg -w -T >> "/opi3w-log/boot-$(cat /opi3w-log/.bootcount)/kmsg-live.txt"'
SuccessExitStatus=124
EOF
cat > "$R/etc/systemd/system/opi3w-bootlog.service.d/10-opi3w-perf.conf" <<'EOF'
[Service]
ExecStart=
ExecStart=/bin/bash -c 'for t in 5 15 30 60; do /usr/local/sbin/opi3w-bootlog snapshot; sleep $t; done; /usr/local/sbin/opi3w-bootlog snapshot'
EOF

# WLAN: Energiesparen erzeugt Latenzspitzen bis 221 ms (ohne: 9 ms).
printf '[connection]\nwifi.powersave=2\n' > "$R/etc/NetworkManager/conf.d/20-opi3w-wifi.conf"

# Firefox: Erster Start 9,0 s, mit vorgeladenen Dateien 5,0 s.
cat > "$R/usr/local/sbin/opi3w-preload" <<'EOF'
#!/bin/bash
# Laedt Firefox nach dem Start im Hintergrund in den Seitencache.
F=/usr/lib/firefox
[ -f "$F/libxul.so" ] || exit 0
sleep 20
L=$(ldd "$F/libxul.so" 2>/dev/null | awk '/=> \//{print $3}' | sort -u)
exec nice -n 19 ionice -c 3 cat "$F"/*.so "$F/omni.ja" "$F/browser/omni.ja" "$F/firefox" "$F/firefox-bin" $L > /dev/null 2>&1
EOF
cat > "$R/etc/systemd/system/opi3w-preload.service" <<'EOF'
[Unit]
Description=Firefox im Hintergrund vorladen
After=graphical.target
[Service]
Type=exec
ExecStart=/usr/local/sbin/opi3w-preload
SuccessExitStatus=1
[Install]
WantedBy=graphical.target
EOF
ln -sf /etc/systemd/system/opi3w-preload.service "$R/etc/systemd/system/graphical.target.wants/opi3w-preload.service"

# Firefox: Keine Telemetrie und Werbekacheln, Cache im Speicher statt auf der Karte.
cat > "$R/usr/lib/firefox/browser/defaults/preferences/opi3w.js" <<'EOF'
pref("datareporting.healthreport.uploadEnabled", false);
pref("datareporting.policy.dataSubmissionEnabled", false);
pref("toolkit.telemetry.enabled", false);
pref("toolkit.telemetry.unified", false);
pref("toolkit.telemetry.archive.enabled", false);
pref("app.normandy.enabled", false);
pref("app.shield.optoutstudies.enabled", false);
pref("browser.newtabpage.activity-stream.feeds.telemetry", false);
pref("browser.newtabpage.activity-stream.telemetry", false);
pref("browser.newtabpage.activity-stream.feeds.section.topstories", false);
pref("browser.newtabpage.activity-stream.showSponsored", false);
pref("browser.newtabpage.activity-stream.showSponsoredTopSites", false);
pref("extensions.pocket.enabled", false);
pref("browser.cache.disk.enable", false);
pref("browser.cache.memory.capacity", 262144);
pref("browser.sessionstore.interval", 60000);
pref("dom.ipc.processCount", 4);
EOF

# Monitor-Hub: Haengen USB-C und HDMI am selben Monitor, kam der Hub in 5 von 5 Starts nicht an USB-C.
# Er ging auch rund 10 s nach dem Wiedereinschalten des Bildschirms verloren.
# 22 s nach dem Abschalten von HDMI war er wieder da und blieb auch mit HDMI an.
# Daher dauerhaft ueberwachen und HDMI nur abschalten, solange der Hub fehlt.
# Ein Monitor ohne Hub bekommt zwei Versuche, danach endet die Ueberwachung.
install -d "$R/etc/xdg/autostart"
cat > "$R/usr/local/bin/opi3w-usbc-hub" <<'EOF'
#!/bin/bash
S=${XDG_STATE_HOME:-$HOME/.local/state}; mkdir -p "$S"
M=$S/opi3w-usbc-hub-hdmi-aus
exec >> "$S/opi3w-usbc-hub.log" 2>&1
hub() { compgen -G '/sys/bus/platform/devices/xhci-hcd.*/usb*/[0-9]-[0-9]' > /dev/null; }
hdmi_an() { kscreen-doctor output.HDMI-A-1.enable > /dev/null; rm -f "$M"; }
aktiv() {
	local A o
	A=$(kscreen-doctor -o | sed 's/\x1b\[[0-9;]*m//g')
	for o in DP-1 HDMI-A-1; do
		echo "$A" | awk -v o="$o" '$1=="Output:"{f=($3==o)} f&&$1=="enabled"{e=1} END{exit !e}' || return 1
	done
}
echo "$(date) Start"
# Wurde die Sitzung im letzten Lauf unterbrochen, waere HDMI sonst dauerhaft aus.
[ -e "$M" ] && hdmi_an
fehlt=0 gesehen=0 versuche=0
while sleep 5; do
	if hub; then
		gesehen=1 fehlt=0 versuche=0
		continue
	fi
	fehlt=$((fehlt + 5))
	[ "$fehlt" -lt 15 ] && continue
	compgen -G '/sys/class/typec/port*-partner' > /dev/null || continue
	# Bei abgeschaltetem Bildschirm abwarten, das Einschalten aendert den Zustand ohnehin.
	kscreen-doctor --dpms show 2>&1 | grep -qi off && continue
	aktiv || continue
	echo "$(date) Hub fehlt, HDMI aus"
	touch "$M"
	kscreen-doctor output.HDMI-A-1.disable > /dev/null
	for i in $(seq 1 45); do hub && break; sleep 1; done
	hdmi_an
	fehlt=0
	if hub; then
		echo "$(date) Hub nach $i s"
		continue
	fi
	versuche=$((versuche + 1))
	echo "$(date) kein Hub nach 45 s, Versuch $versuche"
	[ "$versuche" -lt 2 ] && continue
	[ "$gesehen" = 0 ] && { echo "$(date) nie ein Hub gesehen, Ende"; exit 0; }
	sleep 600
	versuche=0
done
EOF
cat > "$R/etc/xdg/autostart/opi3w-usbc-hub.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Monitor-Hub an USB-C sicherstellen
Exec=/usr/local/bin/opi3w-usbc-hub
NoDisplay=true
EOF

# Tiefschlaf: Plasma schickt das System nach 15 min Leerlauf hinein, in 2 von 2 Faellen wachte es
# nicht mehr auf und wirkte abgestuerzt. Ohne Bereitschaft bleibt nur der Bildschirm im Leerlauf aus.
install -d "$R/etc/systemd/sleep.conf.d"
cat > "$R/etc/systemd/sleep.conf.d/90-opi3w.conf" <<'EOF'
[Sleep]
AllowSuspend=no
AllowHibernation=no
AllowSuspendThenHibernate=no
AllowHybridSleep=no
EOF

chmod 755 "$R/usr/local/bin/opi3w-kwin-output-config" "$R/usr/local/sbin/opi3w-kwin-first" "$R/usr/local/sbin/opi3w-preload" "$R/usr/local/bin/opi3w-usbc-hub"
sed -i 's/\r$//' "$R/usr/local/bin/opi3w-kwin-output-config" "$R/usr/local/sbin/opi3w-kwin-first" "$R/usr/local/sbin/opi3w-preload" "$R/usr/local/bin/opi3w-usbc-hub" "$R/etc/xdg/autostart/opi3w-usbc-hub.desktop"
