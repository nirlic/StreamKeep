"""
StreamKeep GUI
Dark minimal Windows GUI for monitoring and controlling the YouTube stream watcher.
Channels are stored in channels.txt — one URL per line.
Requirements: pip install customtkinter psutil
Build exe:    pyinstaller --onefile --windowed --name StreamKeep streamkeep_gui.py
"""

import customtkinter as ctk
import subprocess
import threading
import psutil
import os
import re
import time
import json
from datetime import datetime
from pathlib import Path
from tkinter import filedialog, messagebox

# ── PATHS ──────────────────────────────────────────────────────
BASE_DIR      = os.path.dirname(os.path.abspath(__file__))
SETTINGS_FILE = os.path.join(BASE_DIR, "sw_settings.json")
CHANNELS_FILE = os.path.join(BASE_DIR, "channels.txt")

APP_NAME    = "StreamKeep"
APP_VERSION = "1.0.0"
APP_AUTHOR  = "Nirlicnick"

CHECK_INTERVAL = 60

# ── SETTINGS ───────────────────────────────────────────────────
def load_settings():
    defaults = {
        "watchdog_path": os.path.join(BASE_DIR, "StreamKeep-Watchdog.ps1"),
        "output_dir":    os.path.join(BASE_DIR, "StreamBackups"),
        "log_file":      os.path.join(BASE_DIR, "StreamBackups", "streamkeep.log"),
    }
    try:
        if os.path.exists(SETTINGS_FILE):
            with open(SETTINGS_FILE, "r") as f:
                defaults.update(json.load(f))
    except Exception:
        pass
    return defaults

def save_settings(data):
    try:
        with open(SETTINGS_FILE, "w") as f:
            json.dump(data, f, indent=2)
    except Exception:
        pass

# ── CHANNELS FILE ──────────────────────────────────────────────
def load_channels():
    if not os.path.exists(CHANNELS_FILE):
        return []
    channels = []
    with open(CHANNELS_FILE, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#"):
                channels.append(line)
    return channels

def save_channels(channels):
    with open(CHANNELS_FILE, "w", encoding="utf-8") as f:
        f.write("# StreamKeep — channels to monitor\n")
        f.write("# One YouTube channel URL per line\n")
        f.write("# Lines starting with # are ignored\n\n")
        for ch in channels:
            f.write(ch + "\n")

# ── THEME ──────────────────────────────────────────────────────
ctk.set_appearance_mode("dark")
ctk.set_default_color_theme("dark-blue")

BG      = "#0d0f12"
SURFACE = "#151820"
BORDER  = "#232733"
ACCENT  = "#00e5ff"
ACCENT2 = "#ff4d6d"
TEXT    = "#e2e8f0"
MUTED   = "#5a6380"
GREEN   = "#22c55e"
YELLOW  = "#f59e0b"


class StreamKeepApp(ctk.CTk):
    def __init__(self):
        super().__init__()
        self.title(f"{APP_NAME} v{APP_VERSION}")
        self.geometry("940x780")
        self.minsize(820, 660)
        self.configure(fg_color=BG)

        self.watcher_process  = None
        self.channel_frames   = {}   # url -> {dot, status, last_seen, row_frame}
        self.running          = False
        self.log_lines        = []
        self.session_start    = None
        self.channels         = load_channels()

        s = load_settings()
        self.cfg_watchdog = s["watchdog_path"]
        self.cfg_output   = s["output_dir"]
        self.cfg_log      = s["log_file"]

        self._build_ui()
        self._start_log_watcher()
        self._start_status_checker()
        self._refresh_stats()
        self._tick_uptime()

    # ─────────────────────────────────────────────────────────────
    #  UI BUILD
    # ─────────────────────────────────────────────────────────────
    def _build_ui(self):
        self._build_header()
        self._build_content()

    def _build_header(self):
        header = ctk.CTkFrame(self, fg_color=SURFACE, corner_radius=0, height=56)
        header.pack(fill="x", side="top")
        header.pack_propagate(False)

        tframe = ctk.CTkFrame(header, fg_color="transparent")
        tframe.pack(side="left", padx=20, fill="y")
        self.dot = ctk.CTkLabel(tframe, text="●", font=("Courier New", 12), text_color=MUTED)
        self.dot.pack(side="left", padx=(0, 8))
        ctk.CTkLabel(tframe, text="STREAMKEEP", font=("Courier New", 13, "bold"), text_color=ACCENT).pack(side="left")
        ctk.CTkLabel(tframe, text=f"v{APP_VERSION}", font=("Courier New", 10), text_color=MUTED).pack(side="left", padx=(6, 0))

        # About button
        ctk.CTkButton(
            tframe, text="by Nirlicnick", width=90, height=24,
            fg_color="transparent", text_color=MUTED, hover_color=SURFACE,
            font=("Courier New", 10), corner_radius=4,
            command=self._show_about
        ).pack(side="left", padx=(12, 0))

        self.status_label = ctk.CTkLabel(header, text="IDLE", font=("Courier New", 11), text_color=MUTED)
        self.status_label.pack(side="right", padx=(0, 16))

        bframe = ctk.CTkFrame(header, fg_color="transparent")
        bframe.pack(side="right", padx=20, pady=10)

        self.start_btn = ctk.CTkButton(
            bframe, text="START", width=90, height=34,
            fg_color=ACCENT, text_color="#000", hover_color="#00c4da",
            font=("Courier New", 12, "bold"), corner_radius=4,
            command=self.start_watcher
        )
        self.start_btn.pack(side="left", padx=(0, 8))

        self.stop_btn = ctk.CTkButton(
            bframe, text="STOP", width=90, height=34,
            fg_color=SURFACE, text_color=ACCENT2, hover_color="#2a1520",
            border_color=ACCENT2, border_width=1,
            font=("Courier New", 12, "bold"), corner_radius=4,
            command=self.stop_watcher, state="disabled"
        )
        self.stop_btn.pack(side="left")

    def _build_content(self):
        self.outer = ctk.CTkScrollableFrame(self, fg_color=BG, scrollbar_button_color=BORDER)
        self.outer.pack(fill="both", expand=True, padx=16, pady=12)

        # ── CHANNELS ──
        self._section_label(self.outer, "CHANNELS")
        self.ch_panel = ctk.CTkFrame(self.outer, fg_color=SURFACE, corner_radius=8)
        self.ch_panel.pack(fill="x", pady=(4, 0))

        # Rebuild channel rows
        self._rebuild_channel_rows()

        # Add channel row
        add_row = ctk.CTkFrame(self.outer, fg_color=SURFACE, corner_radius=8)
        add_row.pack(fill="x", pady=(2, 12))

        self.add_entry = ctk.CTkEntry(
            add_row, placeholder_text="https://www.youtube.com/@ChannelName",
            font=("Courier New", 11), fg_color=BG, border_color=BORDER,
            text_color=TEXT, height=34
        )
        self.add_entry.pack(side="left", fill="x", expand=True, padx=(12, 8), pady=8)

        ctk.CTkButton(
            add_row, text="+ ADD", width=80, height=34,
            fg_color=ACCENT, text_color="#000", hover_color="#00c4da",
            font=("Courier New", 11, "bold"), corner_radius=4,
            command=self._add_channel
        ).pack(side="left", padx=(0, 12), pady=8)

        # ── DOWNLOAD PROGRESS ──
        self._section_label(self.outer, "DOWNLOAD PROGRESS")
        prog_frame = ctk.CTkFrame(self.outer, fg_color=SURFACE, corner_radius=8)
        prog_frame.pack(fill="x", pady=(4, 12))

        self.progress_label = ctk.CTkLabel(prog_frame, text="No active downloads", font=("Courier New", 11), text_color=MUTED)
        self.progress_label.pack(pady=(10, 4), padx=16, anchor="w")

        self.progress_bar = ctk.CTkProgressBar(prog_frame, fg_color=BORDER, progress_color=ACCENT, corner_radius=2, height=6)
        self.progress_bar.pack(fill="x", padx=16, pady=(0, 4))
        self.progress_bar.set(0)

        self.progress_detail = ctk.CTkLabel(prog_frame, text="", font=("Courier New", 10), text_color=MUTED)
        self.progress_detail.pack(padx=16, pady=(0, 10), anchor="w")

        # ── ARCHIVE STATS ──
        self._section_label(self.outer, "ARCHIVE STATS")
        stats_frame = ctk.CTkFrame(self.outer, fg_color=SURFACE, corner_radius=8)
        stats_frame.pack(fill="x", pady=(4, 12))
        stats_inner = ctk.CTkFrame(stats_frame, fg_color="transparent")
        stats_inner.pack(fill="x", padx=16, pady=14)

        self.total_size_label    = self._stat_col(stats_inner, "TOTAL ARCHIVE SIZE")
        self._divider(stats_inner)
        self.total_streams_label = self._stat_col(stats_inner, "STREAMS CAPTURED")
        self._divider(stats_inner)
        self.total_msgs_label    = self._stat_col(stats_inner, "CHAT FILES SAVED")
        self._divider(stats_inner)
        self.uptime_label        = self._stat_col(stats_inner, "SESSION UPTIME")
        self.uptime_label.configure(text="--:--:--", text_color=MUTED)

        # ── SETTINGS ──
        self._section_label(self.outer, "SETTINGS")
        settings_frame = ctk.CTkFrame(self.outer, fg_color=SURFACE, corner_radius=8)
        settings_frame.pack(fill="x", pady=(4, 12))

        def path_row(parent, label, get_val, file_mode=False):
            row = ctk.CTkFrame(parent, fg_color="transparent")
            row.pack(fill="x", padx=16, pady=6)
            ctk.CTkLabel(row, text=label, font=("Courier New", 10), text_color=MUTED, width=140, anchor="w").pack(side="left")
            entry = ctk.CTkEntry(row, font=("Courier New", 11), fg_color=BG, border_color=BORDER, text_color=TEXT, height=30)
            entry.insert(0, get_val())
            entry.pack(side="left", fill="x", expand=True, padx=(8, 8))

            def browse():
                if file_mode:
                    chosen = filedialog.askopenfilename(title=f"Select {label}", filetypes=[("PowerShell", "*.ps1"), ("All", "*.*")])
                else:
                    chosen = filedialog.askdirectory(title=f"Select {label}")
                if chosen:
                    entry.delete(0, "end")
                    entry.insert(0, chosen.replace("/", "\\"))

            ctk.CTkButton(
                row, text="BROWSE", width=72, height=30,
                fg_color=BORDER, text_color=TEXT, hover_color="#2e3347",
                font=("Courier New", 10, "bold"), corner_radius=4,
                command=browse
            ).pack(side="left")
            return entry

        self.entry_output   = path_row(settings_frame, "OUTPUT DIRECTORY", lambda: self.cfg_output)
        self.entry_watchdog = path_row(settings_frame, "WATCHDOG SCRIPT",  lambda: self.cfg_watchdog, file_mode=True)
        self.entry_log      = path_row(settings_frame, "LOG FILE",         lambda: self.cfg_log)

        save_row = ctk.CTkFrame(settings_frame, fg_color="transparent")
        save_row.pack(fill="x", padx=16, pady=(4, 12))
        self.save_status = ctk.CTkLabel(save_row, text="", font=("Courier New", 10), text_color=GREEN)
        self.save_status.pack(side="right", padx=(0, 8))
        ctk.CTkButton(
            save_row, text="SAVE SETTINGS", width=130, height=30,
            fg_color=ACCENT, text_color="#000", hover_color="#00c4da",
            font=("Courier New", 10, "bold"), corner_radius=4,
            command=self._save_settings
        ).pack(side="right")

        # ── ACTIVITY LOG ──
        self._section_label(self.outer, "ACTIVITY LOG")
        log_frame = ctk.CTkFrame(self.outer, fg_color=SURFACE, corner_radius=8)
        log_frame.pack(fill="x", pady=(4, 12))

        self.log_box = ctk.CTkTextbox(
            log_frame, fg_color=SURFACE, text_color=TEXT,
            font=("Courier New", 11), corner_radius=8,
            border_width=0, wrap="word", state="disabled", height=220
        )
        self.log_box.pack(fill="x", padx=4, pady=4)

    # ─────────────────────────────────────────────────────────────
    #  CHANNEL MANAGEMENT
    # ─────────────────────────────────────────────────────────────
    def _rebuild_channel_rows(self):
        """Clear and redraw all channel rows from self.channels."""
        for widget in self.ch_panel.winfo_children():
            widget.destroy()
        self.channel_frames = {}

        if not self.channels:
            ctk.CTkLabel(
                self.ch_panel, text="No channels added yet.",
                font=("Courier New", 11), text_color=MUTED
            ).pack(pady=14, padx=16, anchor="w")
            return

        for i, ch in enumerate(self.channels):
            self._build_channel_row(self.ch_panel, ch, i)

    def _build_channel_row(self, parent, channel_url, index):
        name = channel_url.split("@")[-1].split("/")[0] if "@" in channel_url else channel_url

        row = ctk.CTkFrame(parent, fg_color="transparent")
        row.pack(fill="x", padx=12, pady=6)

        # Status dot
        dot = ctk.CTkLabel(row, text="●", font=("Courier New", 14), text_color=MUTED, width=20)
        dot.pack(side="left", padx=(0, 8))

        # Channel name
        ctk.CTkLabel(row, text=name, font=("Courier New", 12, "bold"), text_color=TEXT, width=160, anchor="w").pack(side="left")

        # Remove button
        def make_remover(url):
            def remove():
                self._remove_channel(url)
            return remove

        ctk.CTkButton(
            row, text="✕", width=28, height=24,
            fg_color="transparent", text_color=MUTED, hover_color="#2a1520",
            font=("Courier New", 11), corner_radius=4,
            command=make_remover(channel_url)
        ).pack(side="right", padx=(0, 4))

        # Last seen / status
        last_seen = ctk.CTkLabel(row, text="", font=("Courier New", 10), text_color=MUTED)
        last_seen.pack(side="right", padx=(0, 8))

        # Status label
        status = ctk.CTkLabel(row, text="CHECKING...", font=("Courier New", 11), text_color=MUTED, width=120, anchor="w")
        status.pack(side="left", padx=(8, 0))

        self.channel_frames[channel_url] = {"dot": dot, "status": status, "last_seen": last_seen}

        if index < len(self.channels) - 1:
            ctk.CTkFrame(parent, fg_color=BORDER, height=1).pack(fill="x", padx=12)

    def _add_channel(self):
        url = self.add_entry.get().strip().rstrip("/")
        if not url:
            return
        if not url.startswith("http"):
            url = "https://www.youtube.com/@" + url.lstrip("@")
        if url in self.channels:
            self.add_entry.delete(0, "end")
            return
        self.channels.append(url)
        save_channels(self.channels)
        self.add_entry.delete(0, "end")
        self._rebuild_channel_rows()
        self._add_log(f"Channel added: {url}", "accent")
        # Kick off a status check for the new channel
        threading.Thread(target=self._check_channel_status, args=(url,), daemon=True).start()

    def _remove_channel(self, url):
        if url in self.channels:
            self.channels.remove(url)
            save_channels(self.channels)
            self._rebuild_channel_rows()
            self._add_log(f"Channel removed: {url}", "muted")

    # ─────────────────────────────────────────────────────────────
    #  SETTINGS
    # ─────────────────────────────────────────────────────────────
    def _save_settings(self):
        self.cfg_output   = self.entry_output.get().strip()
        self.cfg_watchdog = self.entry_watchdog.get().strip()
        self.cfg_log      = self.entry_log.get().strip()
        save_settings({
            "watchdog_path": self.cfg_watchdog,
            "output_dir":    self.cfg_output,
            "log_file":      self.cfg_log,
        })
        self.save_status.configure(text="Saved!")
        self.after(3000, lambda: self.save_status.configure(text=""))

    # ─────────────────────────────────────────────────────────────
    #  WATCHER CONTROL
    # ─────────────────────────────────────────────────────────────
    def start_watcher(self):
        if self.running:
            return
        if not self.channels:
            messagebox.showwarning("No Channels", "Add at least one channel before starting.")
            return
        self.running       = True
        self.session_start = datetime.now()
        self.start_btn.configure(state="disabled")
        self.stop_btn.configure(state="normal")
        self.status_label.configure(text="RUNNING", text_color=GREEN)
        self._animate_dot(True)

        def run():
            self.watcher_process = subprocess.Popen(
                ["powershell.exe", "-ExecutionPolicy", "Bypass", "-File", self.cfg_watchdog],
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                text=True, creationflags=subprocess.CREATE_NO_WINDOW
            )
            self._add_log("Watchdog started.", "accent")
            for line in self.watcher_process.stdout:
                line = line.strip()
                if line:
                    self._add_log(line)
                    self._parse_progress(line)
            self._add_log("Watchdog stopped.", "muted")
            self.running = False
            self.after(0, self._on_stopped)

        threading.Thread(target=run, daemon=True).start()

    def stop_watcher(self):
        self._add_log("Stopping watcher...", "yellow")
        for proc in psutil.process_iter(['name', 'pid']):
            try:
                if proc.info['name'] and 'yt-dlp' in proc.info['name'].lower():
                    proc.kill()
                    self._add_log(f"Stopped yt-dlp (PID {proc.info['pid']})", "muted")
            except Exception:
                pass
        if self.watcher_process:
            try:
                parent = psutil.Process(self.watcher_process.pid)
                for child in parent.children(recursive=True):
                    child.kill()
                parent.kill()
            except Exception:
                pass
            self.watcher_process = None
        self.running = False
        self._on_stopped()

    def _on_stopped(self):
        self.start_btn.configure(state="normal")
        self.stop_btn.configure(state="disabled")
        self.status_label.configure(text="STOPPED", text_color=ACCENT2)
        self._animate_dot(False)
        self.progress_label.configure(text="No active downloads", text_color=MUTED)
        self.progress_bar.set(0)
        self.progress_detail.configure(text="")

    # ─────────────────────────────────────────────────────────────
    #  CHANNEL STATUS CHECKER
    # ─────────────────────────────────────────────────────────────
    def _start_status_checker(self):
        def check_all():
            for ch in list(self.channels):
                self._check_channel_status(ch)

        threading.Thread(target=check_all, daemon=True).start()

        def loop():
            while True:
                time.sleep(CHECK_INTERVAL)
                check_all()

        threading.Thread(target=loop, daemon=True).start()

    def _check_channel_status(self, channel_url):
        try:
            result = subprocess.run(
                ["yt-dlp", "--get-url", "--no-warnings", "-q", f"{channel_url}/live"],
                capture_output=True, text=True, timeout=30,
                creationflags=subprocess.CREATE_NO_WINDOW
            )
            is_live = bool(result.stdout.strip())
            self.after(0, self._update_channel_ui, channel_url, is_live)
        except Exception:
            self.after(0, self._update_channel_ui, channel_url, None)

    def _update_channel_ui(self, channel_url, is_live):
        frame = self.channel_frames.get(channel_url)
        if not frame:
            return
        now = datetime.now().strftime("%H:%M:%S")
        if is_live is True:
            frame["dot"].configure(text_color=ACCENT2)
            frame["status"].configure(text="LIVE", text_color=ACCENT2)
            frame["last_seen"].configure(text=f"detected {now}", text_color=ACCENT2)
        elif is_live is False:
            frame["dot"].configure(text_color=MUTED)
            frame["status"].configure(text="OFFLINE", text_color=MUTED)
            frame["last_seen"].configure(text=f"checked {now}", text_color=MUTED)
        else:
            frame["dot"].configure(text_color=YELLOW)
            frame["status"].configure(text="ERROR", text_color=YELLOW)
            frame["last_seen"].configure(text=f"failed {now}", text_color=YELLOW)

    # ─────────────────────────────────────────────────────────────
    #  LOG WATCHER
    # ─────────────────────────────────────────────────────────────
    def _start_log_watcher(self):
        def tail():
            last_size = 0
            while True:
                try:
                    if os.path.exists(self.cfg_log):
                        size = os.path.getsize(self.cfg_log)
                        if size != last_size:
                            with open(self.cfg_log, "r", encoding="utf-8", errors="replace") as f:
                                lines = f.readlines()
                            for line in lines[len(self.log_lines):]:
                                line = line.strip()
                                if line:
                                    self.log_lines.append(line)
                                    self.after(0, self._add_log, line)
                                    self.after(0, self._parse_progress, line)
                            last_size = size
                except Exception:
                    pass
                time.sleep(1)

        threading.Thread(target=tail, daemon=True).start()

    def _add_log(self, text, color="normal"):
        tl = text.lower()
        if "live" in tl and "not live" not in tl:   color = "red"
        elif "saved" in tl or "all good" in tl:     color = "green"
        elif "error" in tl or "failed" in tl:       color = "red"
        elif "warning" in tl or "low disk" in tl:   color = "yellow"
        elif "not live" in tl or "checking" in tl:  color = "muted"
        elif "watchdog" in tl or "started" in tl:   color = "accent"

        tag_colors = {"normal": TEXT, "accent": ACCENT, "muted": MUTED, "yellow": YELLOW, "red": ACCENT2, "green": GREEN}
        self.log_box.configure(state="normal")
        self.log_box.insert("end", text + "\n", color)
        for tag, clr in tag_colors.items():
            self.log_box.tag_config(tag, foreground=clr)
        self.log_box.see("end")
        self.log_box.configure(state="disabled")

    # ─────────────────────────────────────────────────────────────
    #  PROGRESS
    # ─────────────────────────────────────────────────────────────
    def _parse_progress(self, line):
        match = re.search(r'\[download\]\s+([\d.]+)%\s+of\s+(\S+)\s+at\s+(\S+)\s+ETA\s+(\S+)', line)
        if match:
            self.after(0, self._update_progress, float(match.group(1)), match.group(2), match.group(3), match.group(4))
            return
        frag = re.search(r'fragment\s+(\d+)', line)
        if frag:
            self.after(0, self.progress_label.configure, {"text": f"Downloading... fragment {frag.group(1)} captured", "text_color": ACCENT})

    def _update_progress(self, pct, size, speed, eta):
        self.progress_bar.set(pct / 100)
        self.progress_label.configure(text=f"Downloading  {pct:.1f}%  of  {size}", text_color=ACCENT)
        self.progress_detail.configure(text=f"Speed: {speed}   ETA: {eta}", text_color=MUTED)

    # ─────────────────────────────────────────────────────────────
    #  STATS
    # ─────────────────────────────────────────────────────────────
    def _refresh_stats(self):
        def scan():
            total_bytes = 0
            total_mp4   = 0
            total_chat  = 0
            try:
                base = Path(self.cfg_output)
                if base.exists():
                    for f in base.rglob("*.mp4"):
                        try:
                            total_bytes += f.stat().st_size
                            total_mp4   += 1
                        except Exception:
                            pass
                    for _ in base.rglob("*.json3"):
                        total_chat += 1
            except Exception:
                pass

            if total_bytes >= 1_073_741_824:
                size_str = f"{total_bytes / 1_073_741_824:.2f} GB"
            elif total_bytes >= 1_048_576:
                size_str = f"{total_bytes / 1_048_576:.0f} MB"
            else:
                size_str = f"{total_bytes / 1024:.0f} KB"

            self.after(0, self.total_size_label.configure,    {"text": size_str,       "text_color": ACCENT})
            self.after(0, self.total_streams_label.configure, {"text": str(total_mp4), "text_color": ACCENT})
            self.after(0, self.total_msgs_label.configure,    {"text": str(total_chat),"text_color": ACCENT})

        threading.Thread(target=scan, daemon=True).start()
        self.after(30000, self._refresh_stats)

    def _tick_uptime(self):
        if self.running and self.session_start:
            delta  = datetime.now() - self.session_start
            h, rem = divmod(int(delta.total_seconds()), 3600)
            m, s   = divmod(rem, 60)
            self.uptime_label.configure(text=f"{h:02d}:{m:02d}:{s:02d}", text_color=GREEN)
        else:
            self.uptime_label.configure(text="--:--:--", text_color=MUTED)
        self.after(1000, self._tick_uptime)

    # ─────────────────────────────────────────────────────────────
    #  HELPERS
    # ─────────────────────────────────────────────────────────────
    def _section_label(self, parent, text):
        ctk.CTkLabel(parent, text=text, font=("Courier New", 11, "bold"), text_color=MUTED).pack(anchor="w", pady=(10, 2))

    def _stat_col(self, parent, label):
        col = ctk.CTkFrame(parent, fg_color="transparent")
        col.pack(side="left", expand=True)
        ctk.CTkLabel(col, text=label, font=("Courier New", 10), text_color=MUTED).pack(anchor="w")
        val = ctk.CTkLabel(col, text="...", font=("Courier New", 20, "bold"), text_color=ACCENT)
        val.pack(anchor="w")
        return val

    def _divider(self, parent):
        ctk.CTkFrame(parent, fg_color=BORDER, width=1).pack(side="left", fill="y", padx=16)

    def _show_about(self):
        win = ctk.CTkToplevel(self)
        win.title("About StreamKeep")
        win.geometry("360x280")
        win.resizable(False, False)
        win.configure(fg_color=SURFACE)
        win.grab_set()

        ctk.CTkLabel(win, text="STREAMKEEP", font=("Courier New", 18, "bold"), text_color=ACCENT).pack(pady=(28, 4))
        ctk.CTkLabel(win, text=f"Version {APP_VERSION}", font=("Courier New", 11), text_color=MUTED).pack()

        ctk.CTkFrame(win, fg_color=BORDER, height=1).pack(fill="x", padx=30, pady=16)

        ctk.CTkLabel(win, text="Created by", font=("Courier New", 11), text_color=MUTED).pack()
        ctk.CTkLabel(win, text="Nirlicnick", font=("Courier New", 16, "bold"), text_color=TEXT).pack(pady=(2, 0))

        ctk.CTkFrame(win, fg_color=BORDER, height=1).pack(fill="x", padx=30, pady=16)

        ctk.CTkLabel(win, text="Powered by yt-dlp · ffmpeg · Python", font=("Courier New", 10), text_color=MUTED).pack()
        ctk.CTkLabel(win, text="YouTube Live Stream Auto-Archiver", font=("Courier New", 10), text_color=MUTED).pack(pady=(2, 0))

        ctk.CTkButton(
            win, text="CLOSE", width=100, height=32,
            fg_color=ACCENT, text_color="#000", hover_color="#00c4da",
            font=("Courier New", 11, "bold"), corner_radius=4,
            command=win.destroy
        ).pack(pady=20)

    def _animate_dot(self, active):
        if active:
            self._dot_cycle()
        else:
            self.dot.configure(text_color=MUTED)

    def _dot_cycle(self):
        if not self.running:
            self.dot.configure(text_color=MUTED)
            return
        current = self.dot.cget("text_color")
        self.dot.configure(text_color=ACCENT if current == MUTED else MUTED)
        self.after(800, self._dot_cycle)


# ── ENTRY POINT ────────────────────────────────────────────────
if __name__ == "__main__":
    app = StreamKeepApp()
    app.mainloop()
