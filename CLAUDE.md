# Arch Linux ARM mit KDE Plasma für den Orange Pi Zero 3W

Langzeitspeicher für die Arbeit an diesem Projekt. Antworten auf Deutsch.

## Ziel

SD-Karten-Image für den **Orange Pi Zero 3W (Allwinner A733, 12 GB RAM)** mit KDE Plasma. **USB-C mit DisplayPort Alt Mode ist direkt beim Booten die Hauptausgabe.** Testmonitor: Philips Evnia 49M2C8900L an USB-C und HDMI, Maus und Tastatur hängen am Hub des Monitors.

Es ist **Arch Linux ARM im CachyOS-Stil**, nicht CachyOS: Für CachyOS gibt es keinen ARM-Build. Übernommen sind Einstellungen, Hintergrundbild und Fish-Konfiguration.

## Niemals ins Repository

Das Repository ist öffentlich. `.gitignore` arbeitet deshalb als Positivliste. Neue Pfade müssen dort bewusst freigegeben werden.

- `benutzerpasswort.txt`, `opi3w_ed25519` (privater SSH-Testschlüssel)
- `*.img`, `*.iso`: Sie enthalten den Passwort-Hash und den öffentlichen Testschlüssel; außerdem sind sie zu groß für Git und Releases
- `sd-schreiben.log`, WLAN-Namen und WLAN-Passwörter

Passwörter nicht im Chat ausgeben. Das WLAN-Passwort gibt der Benutzer selbst am SBC ein; Geheimnisse aus NetworkManager-Profilen nie anzeigen.

## Aufbau

| Ort | Inhalt |
|---|---|
| `scripts/` | Bauskripte, erwartet unter `/root/opi3w/scripts` in WSL (Ubuntu-24.04) |
| `patches/kernel/` | Kernel-Patches 0011 bis 0025 |
| `patches/dl/` | Vendor-Pull-Requests 137 und 139 als Patch |
| `patches/opi3w-mesa-no-render-node.patch` | Eigener Mesa-Patch |
| `sd-schreiben.ps1` | Schreibt das Image unter Windows auf die Karte und prüft es |

Nicht im Repository, nur in WSL unter `/root/opi3w`: `src/` (Quellen), `rootfs/`, `rootfs-mesa/`, `out/` (Image, Pakete, Schlüssel, Passwort), `logs/`.

WSL ist isoliert: `automount` und `interop` sind aus, der Standardbenutzer ist root. Dateien laufen über `\\wsl.localhost\Ubuntu-24.04\...`. Immer Skriptdateien ausführen (`wsl.exe -d Ubuntu-24.04 -u root --cd /root -- bash datei.sh`), denn PowerShell 5.1 zerstört doppelte Anführungszeichen in `bash -c` und in SSH-Befehlen. In PowerShell ist `rd` ein Alias von `Remove-Item`, also nie als Funktionsnamen verwenden.

## Bauablauf

1. `16-fetch.sh`: Firmware, NPU, CachyOS-Dateien
2. `10-kernel.sh`: Kernel und U-Boot über Armbian (`BRANCH=vendor`), Pakete in `src/armbian-build/output/debs`
3. `20-rootfs-base.sh`: Arch-Rootfs
4. `30-mesa.sh`, `31-mesa-patch.sh`: Mesa 26.3.0-rc2 mit Patches
5. `40-packages.sh`: Plasma und Anwendungen
6. `46-final.sh`: führt `41-integrate.sh`, `60-chroot-check.sh` und `50-image.sh` aus

Die Meldung `FEHLT usr/bin/lookandfeeltool` in `60-chroot-check` ist ein Fehlalarm (Symlink). Nach einem WSL-Neustart fehlt `binfmt` für qemu-aarch64; `46-final.sh` registriert es neu. `arch-chroot`-Exit-Codes sind unzuverlässig, also das Ergebnis prüfen.

Kernel-Patch ändern: Datei in `src/armbian-build/cache/sources/linux-kernel-worktree/6.6__sun60iw2__arm64` als Vorlage nehmen, Patch in `patches/kernel/` und `userpatches/kernel/archive/sun60iw2-opi-vendor/` ablegen, Armbian `./compile.sh kernel ...` ausführen. Dauert meist nur 1 bis 2 Minuten.

**Stand:** Der Komplettbau aus einem frischen Klon ist nicht getestet. Die Schritte wurden einzeln und inkrementell ausgeführt.

## Testzugang zum SBC

USB-C-Stromanschluss zum PC: NCM-Netz, SBC unter `10.55.0.1`.

```powershell
ssh -i opi3w_ed25519 root@10.55.0.1 'bash /root/skript.sh'
```

Beim Benutzer-Kontext immer `XDG_RUNTIME_DIR=/run/user/1000` und `DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus` setzen, Wayland-Display ist `wayland-1`. Bildschirmfoto: `spectacle -b -n -f -o /tmp/x.png`.

**Nie `pipewire.socket` oder `pipewire` stoppen:** Das beendet die ganze Plasma-Sitzung.

Die SD-Karte nur nach ausdrücklicher Bestätigung überschreiben: WLAN-Profil und Handkorrekturen liegen dort. Windows-Angebote zum Formatieren immer ablehnen.

## Hardware und Treiber

**Boot:** Vendor-U-Boot 2018, `boot0` bei 8 KiB, `boot_package` bei 16400 KiB, kein initrd. MBR-ID `0x0a733a73`. p1 ext4 (bootfähig, physisch hinten, wächst beim ersten Start), p2 FAT32 `OPI3W-LOG` bei 32 MiB für Boot-Protokolle unter `/opi3w-log/boot-N`.

**Anzeige:** `sunxi-drm` ist `card0` (nur KMS, kein Render-Knoten), GPU ist `card1`/`renderD128`.
- USB-C-DP: FUSB302 auf i2c 14-0022, Pin Assignment D, 2 Lanes plus USB, Grenze etwa 8,64 Gbit/s.
- DE-0 (`vch0 vch1 uch0 uch2`) gehört fest USB-C, DE-1 (`vch2 uch1 uch3`) fest HDMI, siehe Patch 0023 und `chn_cfg_mode=2` in 0025. Mit Modus 0 hat DE-1 nur `uch3` und verliert unter Last Bildzeilen.
- Modi breiter als 4096 sind gesperrt (GPU `maxImageDimension2D`), 5120x1440 geht also nicht. Nutzbar ist 2560x1440@59,95.
- Der Bootloader richtet HDMI selbst ein. Patch 0024 ignoriert das, sonst lief HDMI mit 74 statt 60 Hz.
- Patch 0017 entfernt den Hotplug-Monitor des Treibers, der DE-0 von einem laufenden Compositor nahm.
- Prüfen: `/proc/sunxi-drm/status` zeigt `err:` (FIFO-Fehler) und `fps:` je DE. `err` muss unter Last bei 0 bleiben.

**Grafik:** Imagination BXM-4-64, BVNC 36.56.104.183, Treiber `apercel`, freie Firmware, Mesa 26.3.0-rc2. KWin rendert GLES 3.1 über zink, Qt Quick über Vulkan (`QSG_RHI_BACKEND=vulkan`), `PVR_I_WANT_A_BROKEN_VULKAN_DRIVER=1` ist Pflicht. Der eigene Mesa-Patch erlaubt EGL unter Wayland ohne Render-Knoten des Compositors. `GALLIUM_DRIVER=zink` nicht setzen: Das ergab einen schwarzen Bildschirm. `apercel.ko` muss bei jedem Kernelbau neu gelinkt werden, sonst lehnt der Kernel das Modul wegen BTF ab und KWin stürzt in Schleife ab.

**Leistung (`scripts/overlay3.sh`, läuft auch am Live-System mit `/`):**
- Hauptursache der Lag-Spikes war KWins Software-Helligkeit: Sie zwingt jeden Bildpunkt durch den Farbraum-Shader, und der PowerVR-Compiler lädt Uniforms je Pixel aus dem Speicher (etwa 5 bis 8 ms je Uniform-Wert bei 2560x1440). Ein Vollbild-Job dauerte 370 ms statt 47 ms. Abhilfe: `allowSdrSoftwareBrightness=false` in `kwinoutputconfig.json`, gesetzt per `ExecStartPre` von KWin. Einmalig nach der ersten Anmeldung startet `opi3w-kwin-first` die Sitzung neu.
- `CONFIG_RT_GROUP_SCHED=y` verweigert KWin die Echtzeit-Priorität mit `EPERM`. Abhilfe: `kernel.sched_rt_runtime_us=-1`.
- `POWERDEVIL_NO_DDCUTIL=1`: libddcutil fragt sonst alle I2C-Busse ab und erzeugt Fehlerstürme auf der Konsole. Helligkeit daher am Monitor einstellen.
- Sitzung neu starten: `systemctl stop sddm`, dann `systemctl stop user@1000.service`, dann `systemctl start sddm`. Ein `restart sddm` allein oder ein Neustart von `plasma-kwin_wayland` endet am Anmeldebildschirm.
- Boot-Protokolle laufen nur noch rund 2 Minuten nach dem Start. Dauerhaft live: `systemctl start opi3w-klog`.
- Geprüft und ohne Nutzen: `read_ahead_kb=1024`, `power/control=on` für die GPU (`no_autosuspend=1` lässt die GPU trotz des Namens im Leerlauf aus, das Aufwachen kostet aber nur 1 bis 2 ms), `KWIN_DRM_PREFER_COLOR_DEPTH=24` (bleibt `AB30`).
- Messen: ftrace-Ereignisse `gpu_scheduler`, `dma_fence`, `drm_vblank_event_delivered` für Job-Dauern und Bildlücken. FW-Trace über `echo 0xffff > /sys/kernel/debug/dri/1/pvr_params/fw_trace_mask` und `pvr_fw/trace_0` (2247 Ticks je ms, danach wieder `0`). Vor Messungen `kscreen-doctor --dpms on` und `kde-inhibit`, sonst schaltet der Leerlauf den Bildschirm ab und es gibt keine Bilder.
- DSU: `cpu_dsu` steht fest auf 780 MHz, weil `CONFIG_AW_SUNXI_DSUFREQ` aus ist. Dadurch fehlt auch `set_dsufreq_cb` im Kernel, der Herstellertreiber geht also nur mit neuem Kernel. Dieser Chip hat `26m-vf0400`, der DSU hängt an der A55-Versorgung `dcdc5`, bei 1,0 V sind laut Tabelle 1274 MHz zulässig. Getestet mit einem eigenen Modul zur Laufzeit, 1274 gegen 780 MHz: Hauptspeicher 160 statt 173 ns, L3-Bereich 19 statt 26 ns, `xz` 4 % schneller, Firefox-Start 3,95 s statt 4,17 s (fast in der Streuung), unter Dauerlast kein klarer Unterschied (18 gegen 17 bis 18 `xz`-Läufe in 4 min). Nicht eingebaut, weil der Nutzen klein ist und das Drosseln bei Hitze ungetestet blieb (höchstens 70 °C im Test).
- Noch ungenutzt: Der PCO-Compiler hebt Uniforms nicht in Shared Registers.

**Ton:** I2S3 versorgt HDMI, I2S4 versorgt DisplayPort (Karte `allwinner-dp`). Der Codec-Treiber ist `snd_sunxi_codec_av`, I2S4 läuft mit `pll-fs=1`, `mclk-fs=0`: Die vom Hersteller kommentierten Werte 4/512 ergeben einen falschen Takt und verzerrten Ton. Der Umschalter `EDP_I2S_SEL` (`0x0300023c`) liest sich immer als 0, die Herkunft der Adresse ist unbelegt. WirePlumber-Regeln in `scripts/60-opi3w-audio.conf`.

**USB:** `usbc0` ist der Stromanschluss, Gerätemodus (USB 2.0), NCM und ACM. `usbc2` ist der Monitor-Anschluss (dwc3 mit xHCI). Bei `HC died` setzt `opi3w-usb-recover` den Controller über dwc3 `unbind`/`bind` zurück. Das Zurücksetzen eines gesunden Controllers kann den Hub verlieren. **Ein Neustart nach diesem Zurücksetzen bleibt am Ende hängen** (3 von 3, einmal gezielt ausgelöst, Journal endet bei `Journal stopped`), nur Stromtrennen hilft. `RebootWatchdogSec=15s` löste das nicht auf. Das Skript startet deshalb nicht mehr selbst neu. Im Hängerzustand meldet Windows das USB-Netz als `Up`, aber Ping und ARP bleiben aus, und COM3 hängt beim Öffnen; der Monitor kann weiter ein Bild zeigen.

**Monitor-Hub:** Der Hub fehlte am Testmonitor bei 5 von 5 Starts (Port `not attached`), Maus und Tastatur also auch. Später kam er auch von selbst, und einmal ging er rund 10 s nach `--dpms on` verloren (1 von 3). `verbosity` ist nicht die Ursache: Der Fehler blieb mit `verbosity=7`. dwc3 `unbind`/`bind` half nicht. 22 s nach dem Abschalten von HDMI kam der Hub jedes Mal und blieb auch mit wieder eingeschaltetem HDMI. Vermutet, aber nicht belegt: Der Monitor koppelt den USB-Anschluss an den angezeigten Eingang. Warum es vor Bootrunde 6 ohne Eingriff ging, ist ungeklärt. `opi3w-usbc-hub` (Autostart, `scripts/overlay3.sh`) überwacht den Hub dauerhaft und schaltet HDMI nur ab, solange er 15 s fehlt, Protokoll in `~/.local/state/opi3w-usbc-hub.log`. Fehlt er, sind Maus und Tastatur erst rund 67 s nach dem Start da, und HDMI bleibt 22 s dunkel. Ein Monitor ohne Hub bekommt zwei Versuche, danach endet die Überwachung.

**Tiefschlaf:** Plasma schickte das System nach rund 15 min Leerlauf in `deep`, und es wachte in 2 von 2 Fällen nicht mehr auf (Journal endet bei `PM: suspend entry`). Das sah wie ein Absturz aus. `AllowSuspend=no` in `/etc/systemd/sleep.conf.d/90-opi3w.conf` schaltet es ab, `overlay3.sh` setzt das. Lange Messungen liefen vorher mitten im Test in diese Falle.

**WLAN:** AIC8800D80 über SDIO. SAE/WPA3 wird beim Verbinden abgelehnt (Status 53). `opi3w-wifi-wpa2.path` stellt neue WPA3-Profile von Mischnetzen auf `wpa-psk` mit `pmf=disable` um. **Bluetooth:** UART über `aic8800-bluetooth.service`.

**NPU:** Modul `vipcore`, Bibliotheken nur in `/usr/lib/sun60iw2-npu`, Start über `opi3w-npu-run`. Nicht in den globalen Bibliothekspfad legen: Sie überdecken sonst libjpeg und libpng.

**Stiftleiste:** Standard ist `overlays=uart2 i2c0 i2c1 pwm0 spi3-cs0-cs1-spidev` in `/boot/armbianEnv.txt`.

## Stand

Am SBC bestätigt: Booten vom Image auf der Karte, Kaltstart, USB-C als Hauptanzeige, Bild auf HDMI, Hotplug, Ton über USB-C, Maus und Tastatur, WLAN (WPA2), GPU, NPU-Testnetz.

Offen und bekannt:
- Firefox rechnet auf der CPU; erzwungene GPU-Nutzung stürzt in `libvulkan_powervr_mesa.so` ab
- `overlay3.sh` ist am SBC angewendet und dort getestet, das Image auf der Festplatte enthält es noch nicht
- `opi3w-usbc-hub` ist in Neustarts und einem Kaltstart getestet, nicht an einem Monitor ohne Hub (dort wäre HDMI bei jedem Start bis zu 90 s aus). Der Verlust nach `--dpms on` trat beim Test der Überwachung nicht mehr auf, die Rückholung dabei ist nur im laufenden Betrieb ohne Bildschirmwechsel belegt
- Die 90 s Wartezeit in `opi3w-usb-recover` sind ungetestet, weil sich `HC died` nicht gezielt auslösen lässt
- Beim allerersten Start kam der Monitor-Hub einmal erst nach dem Umstecken des Kabels, möglicherweise dieselbe Ursache wie unter „Monitor-Hub“
- Sporadischer `HC died` beim Start (einmal in sechs Starts), Ursache ungeklärt
- Bluetooth-Kopplung und elektrischer Stiftleisten-Test stehen aus, die Pinbelegung ist nicht abgeglichen
- Unter Dauerlast 90 bis 93 °C mit starkem Heruntertakten
- Kein Bild vom Bootloader über USB-C, das Bild beginnt mit dem Kernel
- Der SSH-Testschlüssel ist noch im Image
- `mesa` und `linux-aarch64` sind in `IgnorePkg` festgehalten
