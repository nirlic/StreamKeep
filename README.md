# StreamKeep
### YouTube Live Stream Auto-Archiver
**Created by Nirlicnick** · Powered by yt-dlp, ffmpeg, and Python

---

## What is StreamKeep?

StreamKeep automatically monitors YouTube channels and archives their live streams the moment they go live — video, chat, thumbnails, and all. No manual clicking. Just set it up and walk away.

**Features:**
- Monitors multiple channels simultaneously
- Downloads video + live chat in parallel
- Organizes recordings by channel and date
- Embeds chat as subtitle track in the video
- Chat viewer HTML for replaying chat in sync with video
- Dark minimal GUI with live status, progress, and stats
- Crash recovery via watchdog process

---

## Quick Start (Non-Technical)

1. Double-click **`START HERE.bat`**
2. Setup runs automatically (installs everything needed)
3. The GUI opens — add your channels and click **START**

That's it.

---

## Quick Start (Technical)

```powershell
# 1. Run setup (once)
powershell -ExecutionPolicy Bypass -File setup.ps1

# 2. Add channels to channels.txt (one URL per line)
notepad channels.txt

# 3. Launch GUI
python StreamKeep.py

# 4. Or run headless via watchdog
powershell -ExecutionPolicy Bypass -File StreamKeep-Watchdog.ps1
```

---

## File Structure

```
StreamKeep/
  START HERE.bat        ← Double-click to launch
  StreamKeep.py         ← GUI application
  StreamKeep-Watcher.ps1    ← Core downloader script
  StreamKeep-Watchdog.ps1          ← Crash recovery / auto-restart
  setup.ps1             ← First-time dependency installer
  channels.txt          ← One channel URL per line
  chat-viewer.html      ← Chat replay viewer
  StreamBackups/        ← All downloaded streams go here
    ChannelName/
      20260301/
        video.mp4
        video_subtitled.mp4
        video.live_chat.json3
        video.srt
```

---

## Adding Channels

**Via GUI:** Open StreamKeep, paste a YouTube URL in the input at the bottom of the Channels panel, click **+ ADD**.

**Via channels.txt:** Open `channels.txt` in any text editor. Add one URL per line:
```
https://www.youtube.com/@SomeChannel
https://www.youtube.com/@AnotherChannel
```
Restart StreamKeep for changes to take effect.

---

## Chat Viewer

Open `chat-viewer.html` in any browser. Load a `.live_chat.json3` file, enter the video timestamp, and enable **Auto-sync** to watch chat scroll in real time alongside your video.

---

## Requirements

| Tool | Install |
|------|---------|
| Python 3.8+ | `winget install Python.Python.3` |
| yt-dlp | `winget install yt-dlp` |
| ffmpeg | `winget install ffmpeg` |
| customtkinter | `pip install customtkinter psutil` |
| chat-downloader | `pip install chat-downloader` (optional, for subtitle embedding) |

`setup.ps1` installs all of these automatically.

---

## Running in the Background

**Hidden (no window):**
```powershell
Start-Process powershell -ArgumentList "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$PWD\StreamKeep-Watchdog.ps1`"" -WindowStyle Hidden
```

**Auto-start on boot (Task Scheduler):**
1. Open Task Scheduler
2. Create Basic Task → Name: StreamKeep
3. Trigger: When computer starts
4. Action: Start a program
   - Program: `powershell.exe`
   - Arguments: `-WindowStyle Hidden -ExecutionPolicy Bypass -File "C:\StreamKeep\StreamKeep-Watchdog.ps1"`

---

## Re-signing Scripts (after edits)

```powershell
$cert = Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert
Set-AuthenticodeSignature -FilePath "StreamKeep-Watcher.ps1" -Certificate $cert
Set-AuthenticodeSignature -FilePath "StreamKeep-Watchdog.ps1" -Certificate $cert
Set-AuthenticodeSignature -FilePath "setup.ps1" -Certificate $cert
```

---

## Credits

Built by **Nirlicnick**  
Powered by [yt-dlp](https://github.com/yt-dlp/yt-dlp), [ffmpeg](https://ffmpeg.org), and [Python](https://python.org)
