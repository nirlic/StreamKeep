# ============================================================
#  StreamKeep - StreamKeep-Watcher.ps1
#  YouTube Live Stream Auto-Archiver
#
#  Created by Nirlicnick
#  Powered by yt-dlp and ffmpeg
#  Configuration via channels.txt and sw_settings.json
# ============================================================

$ScriptDir    = Split-Path -Parent $MyInvocation.MyCommand.Path
$ChannelsFile = "$ScriptDir\channels.txt"
$SettingsFile = "$ScriptDir\sw_settings.json"

# ── Load channels.txt ─────────────────────────────────────────
if (Test-Path $ChannelsFile) {
    $Channels = Get-Content $ChannelsFile |
        Where-Object { $_.Trim() -ne "" -and -not $_.TrimStart().StartsWith("#") } |
        ForEach-Object { $_.Trim() }
} else {
    Write-Host "WARNING: channels.txt not found at $ChannelsFile" -ForegroundColor Yellow
    $Channels = @()
}

# ── Load sw_settings.json ─────────────────────────────────────
$OutputDir           = "$ScriptDir\StreamBackups"
$CheckInterval       = 60
$EnableNotifications = $true
$SaveMetadata        = $true
$MinFreeDiskGB       = 20
$AutoUpdate          = $true
$EmbedChat           = $true

if (Test-Path $SettingsFile) {
    try {
        $cfg = Get-Content $SettingsFile -Raw | ConvertFrom-Json
        if ($cfg.output_dir)              { $OutputDir           = $cfg.output_dir }
        if ($cfg.check_interval)          { $CheckInterval       = [int]$cfg.check_interval }
        if ($null -ne $cfg.notifications) { $EnableNotifications = [bool]$cfg.notifications }
        if ($null -ne $cfg.save_metadata) { $SaveMetadata        = [bool]$cfg.save_metadata }
        if ($cfg.min_free_disk_gb)        { $MinFreeDiskGB       = [int]$cfg.min_free_disk_gb }
        if ($null -ne $cfg.auto_update)   { $AutoUpdate          = [bool]$cfg.auto_update }
        if ($null -ne $cfg.embed_chat)    { $EmbedChat           = [bool]$cfg.embed_chat }
    } catch {
        Write-Host "WARNING: Could not parse sw_settings.json, using defaults." -ForegroundColor Yellow
    }
}

if ($Channels.Count -eq 0) {
    Write-Host "No channels configured. Add channels via the GUI or edit channels.txt." -ForegroundColor Yellow
    exit 0
}

$LogFile = "$OutputDir\streamkeep.log"

# ============================================================
#  FUNCTIONS
# ============================================================

function Write-Log {
    param([string]$msg, [string]$color = "White")
    $ts   = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] $msg"
    Write-Host $line -ForegroundColor $color
    try { Add-Content -Path $LogFile -Value $line -ErrorAction SilentlyContinue } catch {}
}

function Show-Notification {
    param([string]$title, [string]$body)
    if (-not $EnableNotifications) { return }
    try {
        [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
        $template = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent(
            [Windows.UI.Notifications.ToastTemplateType]::ToastText02)
        $template.SelectSingleNode('//text[@id="1"]').InnerText = $title
        $template.SelectSingleNode('//text[@id="2"]').InnerText = $body
        $toast = [Windows.UI.Notifications.ToastNotification]::new($template)
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier("StreamKeep").Show($toast)
    } catch {}
}

function Test-DiskSpace {
    param([string]$path)
    try {
        $drive  = Split-Path -Qualifier $path
        $disk   = Get-PSDrive ($drive.TrimEnd(':'))
        $freeGB = [math]::Round($disk.Free / 1GB, 2)
        if ($freeGB -lt $MinFreeDiskGB) {
            Write-Log "LOW DISK SPACE: ${freeGB}GB free (minimum ${MinFreeDiskGB}GB required)" "Red"
            Show-Notification "StreamKeep - Low Disk!" "${freeGB}GB free. Download paused."
            return $false
        }
        return $true
    } catch {
        return $true
    }
}

function Test-AlreadyDownloading {
    param([string]$dir)
    $parts = Get-ChildItem $dir -Filter "*.part"       -ErrorAction SilentlyContinue
    $frags = Get-ChildItem $dir -Filter "*.json-Frag*" -ErrorAction SilentlyContinue
    return ($parts.Count -gt 0 -or $frags.Count -gt 0)
}

function Get-FileSizeReadable {
    param([string]$dir)
    $files = Get-ChildItem $dir -Recurse -File -ErrorAction SilentlyContinue
    $total = ($files | Measure-Object -Property Length -Sum).Sum
    if ($total -ge 1GB) { return "$([math]::Round($total/1GB,2)) GB" }
    if ($total -ge 1MB) { return "$([math]::Round($total/1MB,0)) MB" }
    return "$([math]::Round($total/1KB,0)) KB"
}

function Check-Dependencies {
    $missing = @()
    if (-not (Get-Command yt-dlp -ErrorAction SilentlyContinue)) { $missing += "yt-dlp" }
    if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) { $missing += "ffmpeg" }
    if ($missing.Count -gt 0) {
        Write-Log "Missing dependencies: $($missing -join ', ')" "Red"
        Write-Log "Run setup.ps1 or install: winget install $($missing -join ' ; winget install ')" "Yellow"
        exit 1
    }
    Write-Log "Dependencies OK (yt-dlp + ffmpeg)" "Green"
}

function Update-YtDlp {
    if (-not $AutoUpdate) { return }
    Write-Log "Checking for yt-dlp updates..." "Gray"
    try { & yt-dlp --update 2>&1 | Out-Null } catch {}
}

function Embed-Chat {
    param([string]$channelDir, [string]$channelName)
    if (-not $EmbedChat) { return }
    try {
        $mp4 = Get-ChildItem $channelDir -Filter "*.mp4" -ErrorAction SilentlyContinue |
               Where-Object { $_.Name -notlike "*_subtitled*" } |
               Sort-Object LastWriteTime -Descending |
               Select-Object -First 1

        $json = Get-ChildItem $channelDir -Filter "*.live_chat.json3" -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending |
                Select-Object -First 1

        if (-not $mp4 -or -not $json) {
            Write-Log "[$channelName] Skipping chat embed - mp4 or json3 not found." "Yellow"
            return
        }

        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($mp4.FullName)
        $srtPath  = "$channelDir\$baseName.srt"
        $outMp4   = "$channelDir\${baseName}_subtitled.mp4"

        Write-Log "[$channelName] Converting chat to .srt..." "Gray"
        & chat_downloader $json.FullName --output $srtPath --message-groups all 2>&1 | Out-Null

        if (-not (Test-Path $srtPath)) {
            Write-Log "[$channelName] chat-downloader failed - run: pip install chat-downloader" "Yellow"
            return
        }

        Write-Log "[$channelName] Embedding subtitles into mp4..." "Gray"
        & ffmpeg -i $mp4.FullName -i $srtPath -c copy -c:s mov_text -metadata:s:s:0 language=eng $outMp4 2>&1 | Out-Null

        if (Test-Path $outMp4) {
            Write-Log "[$channelName] Chat embedded: $([System.IO.Path]::GetFileName($outMp4))" "Green"
        } else {
            Write-Log "[$channelName] ffmpeg subtitle embedding failed." "Yellow"
        }
    } catch {
        Write-Log "[$channelName] Chat embed error: $_" "Yellow"
    }
}

# ============================================================
#  SINGLE CHANNEL WATCHER
# ============================================================

function Watch-Channel {
    param([string]$channelUrl)

    $channelName = ($channelUrl -split "@")[-1].Split("/")[0]
    $liveUrl     = "$channelUrl/live"

    while ($true) {
        try {
            $dateFolder = Get-Date -Format "yyyyMMdd"
            $channelDir = "$OutputDir\$channelName\$dateFolder"

            Write-Log "[$channelName] Checking for live stream..." "Gray"
            $liveCheck = & yt-dlp --get-url --no-warnings -q $liveUrl 2>$null

            if ($liveCheck) {
                New-Item -ItemType Directory -Force -Path $channelDir | Out-Null

                if (Test-AlreadyDownloading -dir $channelDir) {
                    Write-Log "[$channelName] Download already in progress - skipping." "Yellow"
                    Start-Sleep -Seconds $CheckInterval
                    continue
                }

                if (-not (Test-DiskSpace -path $OutputDir)) {
                    Start-Sleep -Seconds 300
                    continue
                }

                Write-Log "[$channelName] LIVE! Starting download..." "Red"
                Show-Notification -title "StreamKeep" -body "$channelName is live! Archiving now..."

                $outputTemplate = "$channelDir\%(upload_date)s_%(title)s.%(ext)s"

                $ytArgsVideo = @(
                    "--output", $outputTemplate,
                    "--merge-output-format", "mp4",
                    "--live-from-start",
                    "--no-part",
                    "--retries", "10",
                    "--fragment-retries", "10",
                    "--retry-sleep", "5",
                    "--no-update"
                )

                if ($SaveMetadata) {
                    $ytArgsVideo += @("--write-thumbnail", "--write-description", "--write-info-json")
                }

                $ytArgsVideo += $liveUrl

                $ytArgsChat = @(
                    "--output", $outputTemplate,
                    "--skip-download",
                    "--write-subs",
                    "--sub-langs", "live_chat",
                    "--live-from-start",
                    "--no-update",
                    $liveUrl
                )

                $videoJob = Start-Job -ScriptBlock { param($a) & yt-dlp @a } -ArgumentList (,$ytArgsVideo)
                $chatJob  = Start-Job -ScriptBlock { param($a) & yt-dlp @a } -ArgumentList (,$ytArgsChat)

                while ($videoJob.State -eq "Running" -or $chatJob.State -eq "Running") {
                    Receive-Job $videoJob -ErrorAction SilentlyContinue | ForEach-Object {
                        Write-Log "[$channelName][video] $_" "Gray"
                    }
                    Receive-Job $chatJob -ErrorAction SilentlyContinue | ForEach-Object {
                        Write-Log "[$channelName][chat] $_" "Gray"
                    }
                    Start-Sleep -Seconds 5
                }

                Receive-Job $videoJob -ErrorAction SilentlyContinue | ForEach-Object {
                    Write-Log "[$channelName][video] $_" "Gray"
                }
                Receive-Job $chatJob -ErrorAction SilentlyContinue | ForEach-Object {
                    Write-Log "[$channelName][chat] $_" "Gray"
                }
                Remove-Job $videoJob, $chatJob -Force

                Embed-Chat -channelDir $channelDir -channelName $channelName

                $savedSize = Get-FileSizeReadable -dir $channelDir
                Write-Log "[$channelName] Stream saved! $savedSize" "Green"
                Show-Notification -title "StreamKeep" -body "$channelName stream ended. Saved: $savedSize"

                Write-Log "[$channelName] Waiting 30s before resuming watch..." "Gray"
                Start-Sleep -Seconds 30

            } else {
                Write-Log "[$channelName] Not live. Checking again in ${CheckInterval}s..." "Gray"
                Start-Sleep -Seconds $CheckInterval
            }

        } catch {
            Write-Log "[$channelName] Error: $_" "Yellow"
            Start-Sleep -Seconds $CheckInterval
        }
    }
}

# ============================================================
#  MAIN
# ============================================================

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

Write-Host ""
Write-Host "  +======================================+" -ForegroundColor Cyan
Write-Host "  |   S T R E A M K E E P               |" -ForegroundColor Cyan
Write-Host "  |   by Nirlicnick                     |" -ForegroundColor Cyan
Write-Host "  +======================================+" -ForegroundColor Cyan
foreach ($ch in $Channels) {
    $name = ($ch -split "@")[-1].Split("/")[0]
    Write-Host "  |  * $($name.PadRight(34))|" -ForegroundColor Cyan
}
Write-Host "  +======================================+" -ForegroundColor Cyan
Write-Host "  |  Output: $($OutputDir.PadRight(29))|" -ForegroundColor Cyan
Write-Host "  +======================================+" -ForegroundColor Cyan
Write-Host ""

Write-Log "StreamKeep started." "Cyan"
Check-Dependencies
Update-YtDlp
Write-Log "Watching $($Channels.Count) channel(s)..." "Cyan"

# ── Single channel ────────────────────────────────────────────
if ($Channels.Count -eq 1) {
    Watch-Channel -channelUrl $Channels[0]
}

# ── Multiple channels: parallel jobs ─────────────────────────
else {
    $jobs = @()

    foreach ($channel in $Channels) {
        $jobs += Start-Job -ScriptBlock {
            param(
                [string]$url,
                [string]$outDir,
                [int]$interval,
                [bool]$metadata,
                [int]$minDiskGB,
                [bool]$embedChat
            )

            $channelName = ($url -split "@")[-1].Split("/")[0]
            $liveUrl     = "$url/live"

            function JobLog {
                param([string]$m)
                Write-Output "[$(Get-Date -Format 'HH:mm:ss')] [$channelName] $m"
            }

            while ($true) {
                try {
                    $dateFolder = Get-Date -Format "yyyyMMdd"
                    $channelDir = "$outDir\$channelName\$dateFolder"
                    $liveCheck  = & yt-dlp --get-url --no-warnings -q $liveUrl 2>$null

                    if ($liveCheck) {
                        New-Item -ItemType Directory -Force -Path $channelDir | Out-Null

                        $parts = Get-ChildItem $channelDir -Filter "*.part" -ErrorAction SilentlyContinue
                        if ($parts.Count -gt 0) {
                            JobLog "Already downloading - skipping."
                            Start-Sleep -Seconds $interval
                            continue
                        }

                        try {
                            $drive  = Split-Path -Qualifier $outDir
                            $disk   = Get-PSDrive ($drive.TrimEnd(':'))
                            $freeGB = [math]::Round($disk.Free / 1GB, 2)
                            if ($freeGB -lt $minDiskGB) {
                                JobLog "LOW DISK: ${freeGB}GB free"
                                Start-Sleep -Seconds 300
                                continue
                            }
                        } catch {}

                        JobLog "LIVE! Starting download..."

                        $tmpl  = "$channelDir\%(upload_date)s_%(title)s.%(ext)s"

                        $vArgs = @(
                            "--output", $tmpl,
                            "--merge-output-format", "mp4",
                            "--live-from-start",
                            "--no-part",
                            "--retries", "10",
                            "--fragment-retries", "10",
                            "--retry-sleep", "5",
                            "--no-update"
                        )

                        if ($metadata) {
                            $vArgs += @("--write-thumbnail", "--write-description", "--write-info-json")
                        }

                        $vArgs += $liveUrl

                        $cArgs = @(
                            "--output", $tmpl,
                            "--skip-download",
                            "--write-subs",
                            "--sub-langs", "live_chat",
                            "--live-from-start",
                            "--no-update",
                            $liveUrl
                        )

                        $vJob = Start-Job -ScriptBlock { param($a) & yt-dlp @a } -ArgumentList (,$vArgs)
                        $cJob = Start-Job -ScriptBlock { param($a) & yt-dlp @a } -ArgumentList (,$cArgs)

                        while ($vJob.State -eq "Running" -or $cJob.State -eq "Running") {
                            Start-Sleep -Seconds 5
                        }

                        Remove-Job $vJob, $cJob -Force

                        if ($embedChat) {
                            try {
                                $mp4 = Get-ChildItem $channelDir -Filter "*.mp4" -ErrorAction SilentlyContinue |
                                       Where-Object { $_.Name -notlike "*_subtitled*" } |
                                       Sort-Object LastWriteTime -Descending |
                                       Select-Object -First 1

                                $json = Get-ChildItem $channelDir -Filter "*.live_chat.json3" -ErrorAction SilentlyContinue |
                                        Sort-Object LastWriteTime -Descending |
                                        Select-Object -First 1

                                if ($mp4 -and $json) {
                                    $base   = [System.IO.Path]::GetFileNameWithoutExtension($mp4.FullName)
                                    $srt    = "$channelDir\$base.srt"
                                    $outMp4 = "$channelDir\${base}_subtitled.mp4"
                                    & chat_downloader $json.FullName --output $srt --message-groups all 2>&1 | Out-Null
                                    if (Test-Path $srt) {
                                        & ffmpeg -i $mp4.FullName -i $srt -c copy -c:s mov_text -metadata:s:s:0 language=eng $outMp4 2>&1 | Out-Null
                                    }
                                }
                            } catch {}
                        }

                        $files = Get-ChildItem $channelDir -Recurse -File -ErrorAction SilentlyContinue
                        $total = ($files | Measure-Object -Property Length -Sum).Sum
                        $size  = if ($total -ge 1GB) { "$([math]::Round($total/1GB,2)) GB" } else { "$([math]::Round($total/1MB,0)) MB" }
                        JobLog "Stream saved! $size"

                        Start-Sleep -Seconds 30

                    } else {
                        JobLog "Not live. Checking in ${interval}s..."
                        Start-Sleep -Seconds $interval
                    }

                } catch {
                    JobLog "Error: $_"
                    Start-Sleep -Seconds $interval
                }
            }

        } -ArgumentList $channel, $OutputDir, $CheckInterval, $SaveMetadata, $MinFreeDiskGB, $EmbedChat
    }

    # Relay all job output to console and log file
    while ($true) {
        foreach ($job in $jobs) {
            $out = Receive-Job -Job $job -ErrorAction SilentlyContinue
            if ($out) {
                $out | ForEach-Object {
                    $ts   = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                    $line = "[$ts] $_"
                    Write-Host $line -ForegroundColor White
                    try { Add-Content -Path $LogFile -Value $line -ErrorAction SilentlyContinue } catch {}
                }
            }
        }
        Start-Sleep -Seconds 5
    }
}

# SIG # Begin signature block
# MIIFWwYJKoZIhvcNAQcCoIIFTDCCBUgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQU/kRV107m5ph4ZVr+L7DXnqN6
# s0KgggL8MIIC+DCCAeCgAwIBAgIQV7lfZEh404FHUXcDiKMZfDANBgkqhkiG9w0B
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
# BAGCNwIBFTAjBgkqhkiG9w0BCQQxFgQU+dk3L0mD7j7B0b7inS/NqqVB1+kwDQYJ
# KoZIhvcNAQEBBQAEggEAlBht/vFM6g+bOieRnsgpHGS5c+yKhv+Y24XFLdEa/nii
# A5TTtaA+rl5CjcbOnJkG4orl6c4QQYGX4b2IjlQYZUNJuSpxVj+3AMT8SsDw/7yL
# 68PTrowMxXS3lhjBw7GHIkYYOQ1PNgWlpPzX4dsN3rlGfaEKk3h8wwnmtunohotc
# 7HtYRWoznmXZ3/PR1/7NkQiAXSWwS3o+z3MrK+gTuUntnvwO4f/rbp0czVYlNt8p
# B70SRzuenavnNK+pZu4p13Aq9q9N0MPS4BgT5Pc0LAwHlapHjPIXN/pWiCUGNb9g
# 5ykpeF5p9keLXdXl/vQW/fGdkXkTrmUfLILeWaUj7g==
# SIG # End signature block
