# TeleStream for Omarchy & Quickshell

TeleStream is a high-craft native desktop plugin and status bar widget for **Omarchy** and **Quickshell** on Wayland (Hyprland), designed to stream local video files or YouTube videos directly to RTMP servers (such as Telegram, YouTube, Twitch, Kick) using `ffmpeg` and `yt-dlp`.

---

## ✨ Features

- **Status Bar Pill Widget (`BarWidget.qml`)**:
  - Displays real-time streaming status, live elapsed timer, bitrate, and FPS telemetry.
  - Left-click opens the Control Center panel; Middle-click jumps to live logs; Right-click stops streaming.
- **Control Center Panel (`Panel.qml`)**:
  - **Media Sources**: Stream local video files (integrated with Flea / portal file picker) or YouTube streams/VODs with optimized low-latency HLS extraction.
  - **Recent Sources History**: Automatically saves and displays the last 5 media sources per mode (local files and YouTube URLs) with quick-select and clear controls.
  - **Live Story Mode**: Formats video into a 9:16 vertical aspect ratio with blurred background, ideal for mobile platforms and Telegram Live Stories.
  - **Quality Presets**: Choose between Source Quality (direct stream copy with zero transcoding overhead), 1080p, 720p, or 480p with zerolatency tuning.
  - **Favorites Manager**: Save, edit, and switch between multiple RTMP streaming servers (URL and Stream Key).
  - **Live Logs Viewer**: Real-time log monitoring with autoscroll, log clearing, and export to file.
  - **Wayland Keyboard-First**: Quick shortcuts (`s` start/stop, `l` logs, `f` favorites, `a` about, `Esc` close).
- **Background CLI Daemon (`telestream`)**:
  - Headless streaming daemon independent of graphical windows.
  - Full CLI interface: `telestream start`, `stop`, `status`, `add-recent`, `clear-recent`, and more.

---

## 📋 Prerequisites

- **Omarchy** running on Wayland / Hyprland
- **Quickshell** (`/usr/bin/quickshell`)
- **ffmpeg**
- **yt-dlp** (for YouTube streams)

Install dependencies on Arch Linux / Omarchy:
```bash
sudo pacman -S ffmpeg yt-dlp
```

---

## 🚀 Installation

1. Run the installer script inside the project directory:
   ```bash
   ./install.sh
   ```

2. Enable the widget in your Omarchy status bar:
   ```bash
   omarchy plugin enable dorneles.telestream --section right
   ```

3. To reload the plugin after changes:
   ```bash
   omarchy restart shell
   ```

---

## 🖥️ CLI Usage

The installer links the backend tool globally as `telestream`:

```bash
# Start streaming a local video or YouTube URL
telestream start --source "/path/to/video.mp4" --server "rtmps://dc1-1.rtmp.t.me/s/" --key "STREAM_KEY"

# Start with Live Story (9:16 vertical)
telestream start --source "https://www.youtube.com/watch?v=..." --server "rtmps://..." --key "..." --story

# Check current status
telestream status

# Stop streaming
telestream stop
```

---

## 🗑️ Uninstallation

To remove the plugin and CLI symlink:
```bash
./uninstall.sh
```

