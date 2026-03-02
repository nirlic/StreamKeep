# ============================================================
#  StreamKeep — StreamKeep-Watchdog.ps1
#  Monitors StreamKeep-Watcher.ps1 and restarts it if it crashes
#
#  Created by Nirlicnick
# ============================================================

$ScriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$ScriptPath  = "$ScriptDir\StreamKeep-Watcher.ps1"
$LogFile     = "$ScriptDir\StreamBackups\streamkeep.log"
$RestartDelay = 30

function Write-WatchdogLog($msg) {
    $ts   = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] [WATCHDOG] $msg"
    Write-Host $line -ForegroundColor Magenta
    try { Add-Content -Path $LogFile -Value $line -ErrorAction SilentlyContinue } catch {}
}

New-Item -ItemType Directory -Force -Path (Split-Path $LogFile) | Out-Null

Write-WatchdogLog "StreamKeep Watchdog started."
Write-WatchdogLog "Monitoring: $ScriptPath"

while ($true) {
    Write-WatchdogLog "Starting StreamKeep-Watcher..."
    try {
        $proc = Start-Process powershell -ArgumentList "-ExecutionPolicy Bypass -File `"$ScriptPath`"" -PassThru -NoNewWindow
        $proc.WaitForExit()
        Write-WatchdogLog "StreamKeep-Watcher exited (code $($proc.ExitCode)). Restarting in ${RestartDelay}s..."
    } catch {
        Write-WatchdogLog "Failed to start StreamKeep-Watcher: $_. Retrying in ${RestartDelay}s..."
    }
    Start-Sleep -Seconds $RestartDelay
}
