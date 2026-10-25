# Ein Godot-Headless-Lauf unter der Test-Sperre (test_output\.godot_lock oder .godot_lock2; Sperre > 20 min = verwaist).
# Aufruf: powershell -File tools\run_locked.ps1 -Name b020 -Log test_output\x.log -GodotArgs "--headless -- --mission=a1_blizzard --autoplay=test_a1"
param([string]$Name = "b020", [string]$Log, [string]$GodotArgs, [int]$TimeoutSec = 1800)
$proj = Split-Path $PSScriptRoot -Parent
$out = "$proj\test_output"
$slot = $null
while (-not $slot) {
  foreach ($l in @("$out\.godot_lock", "$out\.godot_lock2")) {
    if (Test-Path $l) {
      $age = ((Get-Date) - (Get-Item $l).LastWriteTime).TotalMinutes
      if ($age -lt 20) { continue }
    }
    Set-Content -Path $l -Value $Name
    Start-Sleep -Milliseconds 300
    if (((Get-Content $l -ErrorAction SilentlyContinue) -join "") -eq $Name) { $slot = $l; break }
  }
  if (-not $slot) { Start-Sleep -Seconds 10 }
}
"SLOT $slot"
$p = Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"`"$proj\tools\godot.cmd`" $GodotArgs > `"$Log`" 2>&1`"" -WorkingDirectory $proj -PassThru -WindowStyle Hidden
"PID $($p.Id)"
$t0 = Get-Date
while (-not $p.HasExited) {
  Start-Sleep -Seconds 30
  if (((Get-Date) - $t0).TotalSeconds -gt $TimeoutSec) { taskkill /PID $p.Id /T /F | Out-Null; "TIMEOUT" | Add-Content $Log; break }
  (Get-Item $slot).LastWriteTime = Get-Date   # Sperre frisch halten
}
if (((Get-Content $slot -ErrorAction SilentlyContinue) -join "") -eq $Name) { Remove-Item $slot -Force }
"EXIT $($p.ExitCode)"
