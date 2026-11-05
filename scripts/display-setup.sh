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
echo "$o" | grep -q 'DP-1' || { echo 'DP-1 nicht gefunden'; exit 0; }
# Eintraege wie 1:2560x1440@59.95; kscreen-doctor nimmt krumme Bildraten nur ueber die Modus-Nummer an.
modes=$(echo "$o" | awk '/Output: .*DP-1/{f=1;next} /Output:/{f=0} f' | grep -oE '[0-9]+:[0-9]+x[0-9]+@[0-9.]+' | sort -u)
sel=""
for r in 3840x1080 2560x1440 2560x1080 1920x1080; do
	# Nur Modi um 60 Hz; 59,94 und 59,95 Hz zaehlen dazu.
	sel=$(echo "$modes" | awk -F'[:@]' -v r="$r" '$2==r && $3>=59 && $3<=61 {print $3, $1, $2}' | sort -nr | head -1)
	[ -n "$sel" ] && break
done
echo "gewaehlt: ${sel:-keine Vorgabe}"

apply() {
	local args=(output.DP-1.enable output.DP-1.priority.1 output.DP-1.scale.1 output.DP-1.position.0,0)
	[ -n "$sel" ] && args+=("output.DP-1.mode.$(echo "$sel" | cut -d' ' -f2)")
	# Eine weitere Anzeige kommt rechts daneben, sonst bleibt der Hauptschirm rechts liegen.
	if kscreen-doctor -o | strip | grep -q 'Output: .*HDMI-A-1'; then
		local w=2560
		[ -n "$sel" ] && w=$(echo "$sel" | cut -d' ' -f3 | cut -dx -f1)
		args+=("output.HDMI-A-1.position.$w,0")
	fi
	kscreen-doctor "${args[@]}"
}

# Plasma ordnet die Anzeigen kurz nach der Anmeldung noch selbst an: so lange nachziehen, bis es haelt.
stable=0
for _ in $(seq 1 24); do
	p=$(kscreen-doctor -o | strip | awk '/Output: .*DP-1/{f=1;next} /Output:/{f=0} f&&/priority/{print $2; exit}')
	g=$(kscreen-doctor -o | strip | awk '/Output: .*DP-1/{f=1;next} /Output:/{f=0} f&&/Geometry/{print $2; exit}')
	if [ "$p" = 1 ] && [ "$g" = 0,0 ]; then
		stable=$((stable + 1))
		[ "$stable" -ge 4 ] && { echo "haelt: Prioritaet $p, Position $g"; exit 0; }
	else
		stable=0
		apply
	fi
	sleep 5
done
echo "USB-C blieb nicht Hauptanzeige"
