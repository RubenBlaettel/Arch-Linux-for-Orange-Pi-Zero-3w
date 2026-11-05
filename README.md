# Arch Linux für den Orange Pi Zero 3W

Arch Linux ARM mit KDE Plasma für den **Orange Pi Zero 3W** (Allwinner A733). Die GPU beschleunigt den Desktop, und **USB-C mit DisplayPort Alt Mode ist direkt beim Booten die Hauptausgabe**.

> **Status: experimentell.** Getestet ist nur ein Board mit 12 GB RAM an einem Philips Evnia 49M2C8900L. Die Grafik nutzt einen Vulkan-Treiber im Vorabstand und den Vendor-Kernel 6.6.

Das System ist Arch Linux ARM im CachyOS-Stil, **kein CachyOS**: Für CachyOS gibt es keinen ARM-Build. Übernommen sind Einstellungen, Hintergrundbild und Fish-Konfiguration, nicht der CachyOS-Kernel.

## Was funktioniert

| Funktion | Stand | Hinweis |
|---|---|---|
| USB-C mit DisplayPort | ✅ | Bild ab dem Kernel-Start, 2560×1440 bei 60 Hz |
| USB-Hub im Monitor | ✅ | Maus und Tastatur über den USB-C-Anschluss |
| HDMI | ✅ | Zweite Anzeige, Einstecken im Betrieb getestet |
| Ton | ✅ | USB-C und HDMI, USB-C ist Standard |
| KDE Plasma mit GPU | ✅ | KWin über zink, Qt Quick über Vulkan |
| OpenGL-Programme | ✅ | Über zink, `glmark2` schafft etwa 60 Bilder pro Sekunde bei 720p |
| NPU | ✅ | Testnetz läuft in 2,9 ms |
| WLAN | ⚠️ | Nur WPA2, siehe unten |
| Bluetooth | ⚠️ | Adapter findet Geräte, Kopplung ungetestet |
| Stiftleiste | ⚠️ | UART, I²C, SPI und PWM melden sich im System, elektrisch ungetestet |
| Firefox mit GPU | ❌ | Stürzt erzwungen im Treiber ab, läuft deshalb auf der CPU |
| Mehr als 4096 Pixel Breite | ❌ | Grenze der GPU, ein 5120×1440-Modus ist gesperrt |
| Hardware-Videodecoder | ❌ | Nicht eingebaut |

## Bekannte Probleme

- **WLAN-Passwort wird als falsch gemeldet:** Der Chip scheitert an WPA3. Das System stellt neue Profile für Netze mit WPA2 und WPA3 selbst auf WPA2 um, die erste Eingabe kann aber fehlschlagen. Gib das Passwort dann noch einmal ein. Reine WPA3-Netze funktionieren nicht.
- **Maus und Tastatur fehlen nach dem Start:** Der USB-Controller blieb einmal in sechs Starts hängen. Ein Dienst setzt ihn dann zurück. Beim allerersten Start kam der Monitor-Hub einmal erst, nachdem das USB-C-Kabel neu gesteckt war. Die Ursachen sind ungeklärt.
- **Hitze:** Unter Dauerlast erreicht der SoC trotz Lüfter 90 bis 93 °C und taktet stark herunter. Für längere Last braucht das Board bessere Kühlung.
- **Kein Bootloader-Bild über USB-C:** Das Bild beginnt erst mit dem Kernel.

## Installation

Dieses Repository enthält **kein fertiges Image**, du musst es selbst bauen (siehe unten). Das Ergebnis ist `opi3w-arch-plasma.img`, etwa 9,3 GB groß. Die SD-Karte sollte mindestens 16 GB haben, ihr Inhalt wird gelöscht.

**Schreiben unter Windows, eine dieser Möglichkeiten:**
- [balenaEtcher](https://etcher.balena.io/): Image und Karte auswählen, schreiben
- [Rufus](https://rufus.ie/): Falls es nach dem Modus fragt, **DD-Modus** wählen
- [`sd-schreiben.ps1`](sd-schreiben.ps1): Als Administrator ausführen, prüft die Karte nach dem Schreiben. Mit diesem Skript ist das Image getestet, Etcher und Rufus sind ungetestet.

Lehne ab, wenn Windows danach anbietet, ein Laufwerk zu formatieren.

**Erster Start:**
1. Karte einsetzen, Monitor an den USB-C-Anschluss für Daten stecken
2. Strom anschließen und etwa eine Minute warten, das System wächst dabei auf die ganze Karte
3. Anmeldung erfolgt automatisch als Benutzer `orangepi`; das Passwort, auch für `sudo`, erzeugt der Bau in `out/benutzerpasswort.txt`
4. WLAN über das Netzwerksymbol einrichten

## Selbst bauen

Gebaut wird unter Linux als root, entwickelt wurde in WSL2 mit Ubuntu 24.04. Die Skripte erwarten feste Pfade unter `/root/opi3w`. Du brauchst etwa 50 GB freien Platz und unter anderem `qemu-user-static`, `arch-install-scripts`, `libarchive-tools`, `u-boot-tools`, `device-tree-compiler`, `dosfstools` und `e2fsprogs`. Die Liste ist nicht vollständig geprüft.

> **Der Komplettbau aus einem frischen Klon ist nicht getestet.** Die Schritte liefen einzeln und inkrementell. Rechne mit Nacharbeit.

```bash
git clone https://github.com/RubenBlaettel/Arch-Linux-for-Orange-Pi-Zero-3w.git /root/opi3w
cd /root/opi3w && mkdir -p src logs out dl

# Verwendete Quellen auf den getesteten Ständen
git clone https://github.com/armbian/build.git src/armbian-build
git -C src/armbian-build checkout 33af1e67d5058be762d3797de4edcc91774ce866
git clone https://github.com/orangepi-xunlong/linux-orangepi.git src/linux
git -C src/linux checkout 2ac08e8c7cdc28abbdc5c9a9dd812f887ae9c79f
git clone https://github.com/CheezeCS/apercel.git src/apercel
git -C src/apercel checkout d03675d4a38e1aa8eb7c0e982e213893a8631baa
git clone https://github.com/CheezeCS/armbian-a733-gpu.git src/armbian-a733-gpu
git -C src/armbian-a733-gpu checkout 6960be5081795368f697a8da772f76d71a5203ff

cd scripts
bash 16-fetch.sh        # Firmware, NPU, CachyOS-Dateien
bash 10-kernel.sh       # Kernel und U-Boot über Armbian
bash 20-rootfs-base.sh  # Arch-Linux-ARM-Basis
bash 30-mesa.sh         # Mesa mit PowerVR-Vulkan und zink
bash 31-mesa-patch.sh   # Eigener Mesa-Patch
bash 40-packages.sh     # Plasma und Anwendungen
bash 46-final.sh        # Alles zusammenführen und Image bauen
```

Das Image liegt danach in `out/`.

## Sicherheit

**Für den normalen Einsatz:** Das Image enthält einen Testzugang. `41-integrate.sh` erzeugt beim Bau ein Schlüsselpaar in `out/opi3w_ed25519` und trägt es für `root` und `orangepi` ein. Das Benutzerpasswort entsteht ebenfalls beim Bau. Dein selbst gebautes Image gehört also nicht in fremde Hände, solange du diesen Zugang nicht entfernst.

SSH ist nur per Schlüssel erreichbar. Über den USB-C-Stromanschluss meldet sich der SBC als Netzwerkgerät unter `10.55.0.1`.

## Stiftleiste

Diese Funktionen sind ab Werk eingeschaltet und in `/boot/armbianEnv.txt` unter `overlays=` änderbar:

| Funktion | SoC-Pins | Gerät |
|---|---|---|
| UART2 | PB0, PB1 | `/dev/ttyS2` |
| I²C0 | PB2, PB3 | `/dev/i2c-0` |
| I²C1 | PB7, PB8 | `/dev/i2c-1` |
| SPI3 | PE0 bis PE4 | `/dev/spidev3.0`, `/dev/spidev3.1` |
| PWM | | `/sys/class/pwm/pwmchip0` |

Die Tabelle nennt SoC-Pins, nicht die Nummern der Stiftleiste. **Prüfe die Belegung vor dem Verkabeln im Pinout von Orange Pi.** Weitere Overlays liegen unter `/boot/dtb/allwinner/overlay`. Eingeschaltete Pins stehen nicht als normale GPIOs bereit.

## Aufbau des Repositorys

| Pfad | Inhalt |
|---|---|
| `scripts/` | Bauskripte und Systemdateien |
| `patches/kernel/` | Kernel-Patches 0011 bis 0025 |
| `patches/dl/` | Pull Requests 137 und 139 aus `linux-orangepi` |
| `patches/opi3w-mesa-no-render-node.patch` | Mesa-Patch für Compositoren ohne Render-Knoten |
| `sd-schreiben.ps1` | Schreibt das Image unter Windows und prüft es |
| `CLAUDE.md` | Technische Projektnotizen |

## Danksagung

Dieses Projekt baut auf der Arbeit anderer auf:

- [Armbian](https://github.com/armbian/build): Baukasten für Kernel und U-Boot
- [Orange Pi](https://github.com/orangepi-xunlong/linux-orangepi): Vendor-Kernel, einschließlich der Pull Requests 137 und 139 von jwalter613
- [armbian-a733-gpu](https://github.com/CheezeCS/armbian-a733-gpu) und [apercel](https://github.com/CheezeCS/apercel): Offener GPU-Treiber für den A733
- [Mesa](https://mesa3d.org/): PowerVR Vulkan und zink
- [Imagination](https://gitlab.freedesktop.org/imagination/linux-firmware): GPU-Firmware
- [CachyOS](https://github.com/CachyOS): Einstellungen, Hintergrundbilder und Fish-Konfiguration
- [Arch Linux ARM](https://archlinuxarm.org/): Basissystem

Die Patches und Komponenten stehen unter den Lizenzen ihrer Projekte. Dieses Repository selbst hat noch keine eigene Lizenz.
