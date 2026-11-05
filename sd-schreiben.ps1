# Schreibt das Orange-Pi-Image auf die SD-Karte. In einem Terminal als Administrator ausfuehren.
# Die gewaehlte Karte wird dabei vollstaendig ueberschrieben.
param([int]$DiskNumber = -1, [string]$ExpectedName = '', [string]$LogFile = '')
$ErrorActionPreference = 'Stop'
if ($LogFile) { Start-Transcript -Path $LogFile -Force | Out-Null }
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$img = Join-Path $here 'opi3w-arch-plasma.img'
$rootStart = 589824L * 512
$fatStart = 65536L * 512
$bs = 4MB

$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) { throw 'Bitte das Terminal als Administrator starten.' }
if (-not (Test-Path $img)) { throw "Image nicht gefunden: $img" }

$imgLen = (Get-Item $img).Length
$cand = @(Get-Disk | Where-Object { $_.BusType -eq 'USB' -and $_.Size -ge 8GB -and $_.Size -le 2TB -and -not $_.IsBoot -and -not $_.IsSystem -and $_.Size -gt $imgLen })
if ($cand.Count -eq 0) { throw 'Keine passende SD-Karte gefunden.' }
$cand | Select-Object Number, FriendlyName, BusType, PartitionStyle, @{n='GB';e={[math]::Round($_.Size/1GB,1)}} | Format-Table -AutoSize
Get-Partition -ErrorAction SilentlyContinue | Where-Object { $cand.Number -contains $_.DiskNumber } | Select-Object DiskNumber, DriveLetter, @{n='GB';e={[math]::Round($_.Size/1GB,1)}} | Format-Table -AutoSize

if ($DiskNumber -ge 0) {
	# Aufruf ohne Rueckfrage: Nummer und Name muessen beide zur bereits bestaetigten Karte passen.
	$disk = $cand | Where-Object { $_.Number -eq $DiskNumber -and $_.FriendlyName -eq $ExpectedName }
	if (-not $disk) { throw "Datentraeger $DiskNumber mit dem Namen '$ExpectedName' steht nicht zur Auswahl." }
} else {
	$n = Read-Host 'Nummer der SD-Karte eingeben (alles darauf wird geloescht), Abbruch mit Enter'
	if ([string]::IsNullOrWhiteSpace($n)) { Write-Host 'Abgebrochen.'; exit 1 }
	$disk = $cand | Where-Object { $_.Number -eq [int]$n }
	if (-not $disk) { throw "Datentraeger $n steht nicht zur Auswahl." }
	$c = Read-Host "Wirklich '$($disk.FriendlyName)' mit $([math]::Round($disk.Size/1GB,1)) GB ueberschreiben? Zum Bestaetigen JA eingeben"
	if ($c -cne 'JA') { Write-Host 'Abgebrochen.'; exit 1 }
}

if ($disk.PartitionStyle -ne 'RAW') { Clear-Disk -Number $disk.Number -RemoveData -RemoveOEM -Confirm:$false }
Start-Sleep -Seconds 2

$path = "\\.\PhysicalDrive$($disk.Number)"
$src = [IO.File]::OpenRead($img)
$dst = New-Object IO.FileStream($path, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::ReadWrite, 4096, [IO.FileOptions]::WriteThrough)
$buf = New-Object byte[] $bs
$sw = [Diagnostics.Stopwatch]::StartNew()
try {
	# Der erste Block mit der Partitionstabelle kommt zuletzt, damit Windows vorher nichts einbindet.
	$first = New-Object byte[] $bs
	[void]$src.Read($first, 0, $bs)
	$dst.Position = $bs
	$done = [long]$bs
	while (($r = $src.Read($buf, 0, $bs)) -gt 0) {
		$dst.Write($buf, 0, $r)
		$done += $r
		if ($done % 512MB -eq 0) { Write-Host ("{0:N1} von {1:N1} GB, {2:N0} MB/s" -f ($done/1GB), ($imgLen/1GB), ($done/1MB/$sw.Elapsed.TotalSeconds)) }
	}
	$dst.Flush($true)
	$dst.Position = 0
	$dst.Write($first, 0, $bs)
	$dst.Flush($true)
	Write-Host ("Geschrieben: {0:N1} GB in {1:N0} s" -f ($imgLen/1GB), $sw.Elapsed.TotalSeconds)

	# Bootloader und Linux-Partition vergleichen. Die FAT-Partition darf Windows inzwischen veraendert haben.
	Write-Host 'Pruefe die Karte ...'
	$sha = [Security.Cryptography.SHA256]::Create()
	$b1 = New-Object byte[] $bs
	$b2 = New-Object byte[] $bs
	foreach ($range in @(@(0L, $fatStart), @($rootStart, $imgLen))) {
		$pos = $range[0]
		$src.Position = $pos
		$dst.Position = $pos
		while ($pos -lt $range[1]) {
			$len = [int][math]::Min([long]$bs, $range[1] - $pos)
			$got = 0
			while ($got -lt $len) { $x = $src.Read($b1, $got, $len - $got); if ($x -le 0) { throw 'Lesefehler im Image' }; $got += $x }
			$got = 0
			while ($got -lt $len) { $x = $dst.Read($b2, $got, $len - $got); if ($x -le 0) { throw 'Lesefehler auf der Karte' }; $got += $x }
			$h1 = [BitConverter]::ToString($sha.ComputeHash($b1, 0, $len))
			$h2 = [BitConverter]::ToString($sha.ComputeHash($b2, 0, $len))
			if ($h1 -ne $h2) { throw "Pruefung fehlgeschlagen bei Byte $pos. Die Karte ist nicht zuverlaessig beschrieben." }
			$pos += $len
		}
	}
	Write-Host 'Pruefung bestanden. Die SD-Karte ist fertig.' -ForegroundColor Green
} finally {
	$dst.Close()
	$src.Close()
}
Update-Disk -Number $disk.Number -ErrorAction SilentlyContinue
Write-Host 'Falls Windows anbietet, ein Laufwerk zu formatieren: bitte ablehnen.'
if ($LogFile) { Stop-Transcript | Out-Null }
