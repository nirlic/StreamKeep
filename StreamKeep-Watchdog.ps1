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

# SIG # Begin signature block
# MIIFWwYJKoZIhvcNAQcCoIIFTDCCBUgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUgr5KvOqrJ0ch6zHz4bon+5Ga
# YhOgggL8MIIC+DCCAeCgAwIBAgIQV7lfZEh404FHUXcDiKMZfDANBgkqhkiG9w0B
# AQsFADAUMRIwEAYDVQQDDAlNeVNjcmlwdHMwHhcNMjYwMjI3MTAwMDExWhcNMjcw
# MjI3MTAyMDExWjAUMRIwEAYDVQQDDAlNeVNjcmlwdHMwggEiMA0GCSqGSIb3DQEB
# AQUAA4IBDwAwggEKAoIBAQCn0h5Nv2CgYoA0enFsHmUQyG906Onm1l43lwvf2Jsh
# PO/G9mb2AiwtuCY6FdDYW9rLYptzZiliYFsR/ungroJnPwXxhgRW/WPsXyHc78zd
# 0Xu7u3GIkBspexs0K6XtEgKixbevAaijlSsTWHl9TcH9xWfw5Vkb9mgUaXX4iKb2
# hpPJTWtJlc9Gka6jpoifYvl/HTGKjuz0OKVxFjMxifGSj03j/7ubrcU7pYbhUuCO
# nWUzYvhjAjxF8S+LjB9UA+WBtASIkfY1kiN0SBqy+OGLNv9/DM+QgTBknPKjmH1d
# skGjBxRdV2/pW2TLk5HmHz9szE+NI29Oa+mek9gwdcCZAgMBAAGjRjBEMA4GA1Ud
# DwEB/wQEAwIHgDATBgNVHSUEDDAKBggrBgEFBQcDAzAdBgNVHQ4EFgQUpQFVtmCE
# RH7Oic7nPtBlT1PJQQswDQYJKoZIhvcNAQELBQADggEBABASkBKb8E8/7cai7602
# Uq0xB8ReOdsqdXeOeHUvbH1gHAGhK8gpltaL3mGhAq7i2h6SFHrZaXt27N6/Ex7o
# LtU/kcaT6ddbL1YKNnedxmLh8znLhdNydu8GQnnkbnOLixT73HbNdNz9pz3XyGQ5
# yTExvbT4QxNt2nCGookTVSoURCD/X+u+/xI1ASM6GEJrJIrgR8Ya7bu7pBUmyZ22
# 3r3kprx7ktHRyJvOIcmhsHHO6pJ/x5gHjOupMn+PeXd1X1ac4BhajYlqkDzzTL9T
# 5jUQS4KEFrYkSXdVRlJ9DfE6LN7q4dfneYi5EiDtEu2SwQQWZjZvw0u9z0o01QgK
# xzAxggHJMIIBxQIBATAoMBQxEjAQBgNVBAMMCU15U2NyaXB0cwIQV7lfZEh404FH
# UXcDiKMZfDAJBgUrDgMCGgUAoHgwGAYKKwYBBAGCNwIBDDEKMAigAoAAoQKAADAZ
# BgkqhkiG9w0BCQMxDAYKKwYBBAGCNwIBBDAcBgorBgEEAYI3AgELMQ4wDAYKKwYB
# BAGCNwIBFTAjBgkqhkiG9w0BCQQxFgQUzq6e4Y6nMHjJSa1RGOg8RD4JaLgwDQYJ
# KoZIhvcNAQEBBQAEggEAKOCyvJP6vNHScIKO1FJlfXn642ievwa0wFZSZrKANeBY
# pV4cz6yP/VDmyIjLwfmiRFvp1FgczaiaBIKz4kfYFulGMEOjrzBColkrRp4zTNfY
# lTGxKxlVEckqvQh/36rtp/rsrgADetiCwqlfE1n4JHvS+P115blyZmvQpzzqRn0z
# jF8iJ4REsX3rMRggQ8L9w7jlDoJ2IX2k5f8Gr8/UEhOgHjQz9IoCmDCWwHj2+kU6
# 3PP7cB6HByWH2xVi6h3RvFNKDjekYkO4Xcspxw/sQMQjnR9180WXD6fpYbYMfXO2
# kATJvZmTaDma1JEMfL1CitZK1maC++4MTaVBR2AjQg==
# SIG # End signature block
