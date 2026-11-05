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

**Ton:** I2S3 versorgt HDMI, I2S4 versorgt DisplayPort (Karte `allwinner-dp`). Der Codec-Treiber ist `snd_sunxi_codec_av`, I2S4 läuft mit `pll-fs=1`, `mclk-fs=0`: Die vom Hersteller kommentierten Werte 4/512 ergeben einen falschen Takt und verzerrten Ton. Der Umschalter `EDP_I2S_SEL` (`0x0300023c`) liest sich immer als 0, die Herkunft der Adresse ist unbelegt. WirePlumber-Regeln in `scripts/60-opi3w-audio.conf`.

**USB:** `usbc0` ist der Stromanschluss, Gerätemodus (USB 2.0), NCM und ACM. `usbc2` ist der Monitor-Anschluss (dwc3 mit xHCI). Bei `HC died` setzt `opi3w-usb-recover` den Controller über dwc3 `unbind`/`bind` zurück. Das Zurücksetzen eines gesunden Controllers kann den Hub verlieren.

**WLAN:** AIC8800D80 über SDIO. SAE/WPA3 wird beim Verbinden abgelehnt (Status 53). `opi3w-wifi-wpa2.path` stellt neue WPA3-Profile von Mischnetzen auf `wpa-psk` mit `pmf=disable` um. **Bluetooth:** UART über `aic8800-bluetooth.service`.

**NPU:** Modul `vipcore`, Bibliotheken nur in `/usr/lib/sun60iw2-npu`, Start über `opi3w-npu-run`. Nicht in den globalen Bibliothekspfad legen: Sie überdecken sonst libjpeg und libpng.

**Stiftleiste:** Standard ist `overlays=uart2 i2c0 i2c1 pwm0 spi3-cs0-cs1-spidev` in `/boot/armbianEnv.txt`.

## Stand

Am SBC bestätigt: Booten vom Image auf der Karte, Kaltstart, USB-C als Hauptanzeige, Bild auf HDMI, Hotplug, Ton über USB-C, Maus und Tastatur, WLAN (WPA2), GPU, NPU-Testnetz.

Offen und bekannt:
- Firefox rechnet auf der CPU; erzwungene GPU-Nutzung stürzt in `libvulkan_powervr_mesa.so` ab
- Beim allerersten Start kam der Monitor-Hub einmal erst nach dem Umstecken des Kabels, Ursache ungeklärt
- Sporadischer `HC died` beim Start (einmal in sechs Starts), Ursache ungeklärt
- Bluetooth-Kopplung und elektrischer Stiftleisten-Test stehen aus, die Pinbelegung ist nicht abgeglichen
- Unter Dauerlast 90 bis 93 °C mit starkem Heruntertakten
- Kein Bild vom Bootloader über USB-C, das Bild beginnt mit dem Kernel
- Der SSH-Testschlüssel ist noch im Image
- `mesa` und `linux-aarch64` sind in `IgnorePkg` festgehalten
