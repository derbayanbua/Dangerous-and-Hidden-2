# Gemeinsame Test-Sperre und Suite-Lauf (B-025, O-014/O-015/O-016). Per Dot-Sourcing einbinden:
#   . "$PSScriptRoot\test_lock.ps1"
# Slots: test_output\.godot_lock und .godot_lock2 (wie run_locked.ps1; Sperre älter als 20 min = verwaist).
# Mehrspieler-Suiten belegen beide Slots, Einzelsuiten einen.

function Get-TestSlots {
  param([string]$Proj, [string]$Name, [int]$Count = 1)
  $out = "$Proj\test_output"
  $all = @("$out\.godot_lock", "$out\.godot_lock2")
  $tag = "$Name#$PID"
  while ($true) {
    $free = @($all | Where-Object {
      -not (Test-Path $_) -or (((Get-Date) - (Get-Item $_).LastWriteTime).TotalMinutes -ge 20) })
    if ($free.Count -ge $Count) {
      $got = @()
      foreach ($l in ($free | Select-Object -First $Count)) {
        Set-Content -Path $l -Value $tag
        Start-Sleep -Milliseconds 300
        if (((Get-Content $l -ErrorAction SilentlyContinue) -join "") -eq $tag) { $got += $l } else { break }
      }
      if ($got.Count -eq $Count) { return ,$got }
      Release-TestSlots -Slots $got -Name $Name   # Wettlauf verloren: zurückgeben, neu versuchen
    }
    Start-Sleep -Seconds 10
  }
}

function Release-TestSlots {
  param([string[]]$Slots, [string]$Name)
  foreach ($l in $Slots) {
    if (((Get-Content $l -ErrorAction SilentlyContinue) -join "") -eq "$Name#$PID") { Remove-Item $l -Force -ErrorAction SilentlyContinue }
  }
}

# Startet einen Godot-Lauf (oder die exportierte EXE), wartet höchstens $TimeoutSec und beendet bei Zeitüberschreitung
# nur den eigenen Prozessbaum (taskkill /PID /T). Rückgabe: @{ code; timeout; seconds }
function Invoke-GodotSuite {
  param([string]$Proj, [string]$GodotArgs, [string]$Log, [int]$TimeoutSec = 900, [string[]]$Slots = @(), [string]$Exe = "")
  $runner = if ($Exe) { $Exe } else { "$Proj\tools\godot.cmd" }
  $p = Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"`"$runner`" $GodotArgs > `"$Log`" 2>&1`"" `
    -WorkingDirectory $Proj -PassThru -WindowStyle Hidden
  $null = $p.Handle   # sonst liefert ExitCode nach dem Ende $null
  $t0 = Get-Date
  $timedOut = $false
  while (-not $p.WaitForExit(2000)) {
    foreach ($l in $Slots) { if (Test-Path $l) { (Get-Item $l).LastWriteTime = Get-Date } }   # Sperre frisch halten
    if (((Get-Date) - $t0).TotalSeconds -gt $TimeoutSec) {
      taskkill /PID $p.Id /T /F 2>&1 | Out-Null
      $p.WaitForExit(10000) | Out-Null
      $timedOut = $true
      "TIMEOUT nach $TimeoutSec s (B-025)" | Add-Content $Log -Encoding UTF8
      break
    }
  }
  $code = if ($timedOut) { -1 } else { $p.ExitCode }
  return @{ code = $code; timeout = $timedOut; seconds = [int]((Get-Date) - $t0).TotalSeconds }
}

# Wertet ein Suite-Log aus (O-016): bestanden nur mit Exit 0 UND einer ERGEBNIS-Zeile mit 0 Fehlschlaegen.
# Rückgabe: @{ ok; fails; summary; reason }
function Read-SuiteResult {
  param([string]$Log, [int]$Code, [bool]$TimedOut)
  $lines = @()
  if (Test-Path $Log) { $lines = @(Get-Content $Log -Encoding UTF8) }
  $summary = $lines | Where-Object { $_ -match '^\s*ERGEBNIS' } | Select-Object -Last 1
  $fails = $null
  if ($summary) {
    if ($summary -match '(\d+)\s+(fehlgeschlagen|fehlerhaft|mit Fehlern|Fehler\b)') { $fails = [int]$Matches[1] }
    elseif ($summary -match '(\d+)\s*/\s*(\d+)') { $fails = [int]$Matches[2] - [int]$Matches[1] }
  }
  $failLines = @($lines | Where-Object { $_ -match '^FAIL' }).Count
  $reason = ""
  if ($TimedOut) { $reason = "Zeitlimit" }
  elseif (-not $summary) { $reason = "keine ERGEBNIS-Zeile" }
  elseif ($null -eq $fails) { $reason = "ERGEBNIS unlesbar" }
  elseif ($fails -gt 0) { $reason = "$fails Fehlschlaege" }
  elseif ($Code -ne 0) { $reason = "Exit $Code" }
  if ($null -eq $fails) { $fails = [math]::Max(1, $failLines) }
  return @{ ok = ($reason -eq ""); fails = $fails; summary = $summary; reason = $reason }
}

