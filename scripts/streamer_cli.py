#!/usr/bin/env python3
"""
streamer_cli.py - Backend CLI & Streaming Daemon for TeleStream Omarchy (Quickshell).
Handles ffmpeg invocation, yt-dlp URL extraction, state tracking, and config management.
"""

import sys
import os
import re
import time
import json
import signal
import shutil
import argparse
import subprocess
import threading
from datetime import datetime
from pathlib import Path

# Paths
STATE_DIR = Path(os.path.expanduser("~/.local/state/omarchy/telestream"))
STATE_FILE = STATE_DIR / "state.json"
LOG_FILE = STATE_DIR / "telestream.log"
PID_FILE = STATE_DIR / "streamer.pid"

LOCAL_CONFIG_FILE = Path(__file__).resolve().parent.parent / "config.json"
USER_CONFIG_DIR = Path(os.path.expanduser("~/.config/telestream"))
USER_CONFIG_FILE = USER_CONFIG_DIR / "config.json"

def get_config_path() -> Path:
    if USER_CONFIG_FILE.exists():
        return USER_CONFIG_FILE
    if LOCAL_CONFIG_FILE.exists():
        return LOCAL_CONFIG_FILE
    return USER_CONFIG_FILE

def ensure_state_dir():
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    try:
        os.chmod(STATE_DIR, 0o700)
    except Exception:
        pass

def ensure_user_config_dir():
    USER_CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    try:
        os.chmod(USER_CONFIG_DIR, 0o700)
    except Exception:
        pass

def load_config() -> dict:
    for cfg_path in [USER_CONFIG_FILE, LOCAL_CONFIG_FILE]:
        if cfg_path.exists():
            try:
                with open(cfg_path, "r", encoding="utf-8") as f:
                    data = json.load(f)
                    if isinstance(data, dict):
                        return data
            except Exception:
                pass
    return {
        "favorites": [],
        "theme": "dark",
        "live_story": False,
        "last_favorite_name": None,
        "recent_local_sources": [],
        "recent_url_sources": []
    }

def add_recent_source(source: str, is_url: bool = None) -> None:
    source = source.strip()
    if not source:
        return
    if is_url is None:
        is_url = (
            source.startswith("http://")
            or source.startswith("https://")
            or "youtube.com" in source
            or "youtu.be" in source
            or (not os.path.exists(source) and len(source) == 11 and bool(re.match(r'^[a-zA-Z0-9_-]{11}$', source)))
        )
    cfg = load_config()
    key = "recent_url_sources" if is_url else "recent_local_sources"
    current = cfg.get(key, [])
    if not isinstance(current, list):
        current = []
    if source in current:
        current.remove(source)
    current.insert(0, source)
    cfg[key] = current[:5]
    save_config(cfg)

def remove_recent_source(source: str, mode: str = "auto") -> None:
    source = source.strip()
    if not source:
        return
    cfg = load_config()
    if mode in ("local", "file"):
        cfg["recent_local_sources"] = [s for s in cfg.get("recent_local_sources", []) if s != source]
    elif mode in ("youtube", "url"):
        cfg["recent_url_sources"] = [s for s in cfg.get("recent_url_sources", []) if s != source]
    else:
        cfg["recent_local_sources"] = [s for s in cfg.get("recent_local_sources", []) if s != source]
        cfg["recent_url_sources"] = [s for s in cfg.get("recent_url_sources", []) if s != source]
    save_config(cfg)

def clear_recent_sources(mode: str = "all") -> None:
    cfg = load_config()
    if mode in ("local", "file"):
        cfg["recent_local_sources"] = []
    elif mode in ("youtube", "url"):
        cfg["recent_url_sources"] = []
    else:
        cfg["recent_local_sources"] = []
        cfg["recent_url_sources"] = []
    save_config(cfg)

def save_config(data: dict):
    # Save exclusively to user config dir with restrictive permissions (0600)
    ensure_user_config_dir()
    try:
        tmp_cfg = USER_CONFIG_DIR / f"config.{os.getpid()}.{time.time_ns()}.tmp"
        fd = os.open(tmp_cfg, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with open(fd, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=4)
        tmp_cfg.replace(USER_CONFIG_FILE)
        try:
            os.chmod(USER_CONFIG_FILE, 0o600)
        except Exception:
            pass
    except Exception as e:
        sys.stderr.write(f"Error saving user config: {e}\n")

def parse_telemetry(line: str) -> dict:
    data = {}
    m_frame = re.search(r"frame=\s*(\d+)", line)
    if m_frame:
        data["frame"] = int(m_frame.group(1))
    m_fps = re.search(r"fps=\s*([\d\.]+)", line)
    if m_fps:
        data["fps"] = m_fps.group(1)
    m_bitrate = re.search(r"bitrate=\s*([\d\.]+\s*\S+)", line)
    if m_bitrate:
        data["bitrate"] = m_bitrate.group(1)
    m_speed = re.search(r"speed=\s*([\d\.]+x)", line)
    if m_speed:
        data["speed"] = m_speed.group(1)
    m_size = re.search(r"size=\s*([\d\.]+\s*\S+)", line)
    if m_size:
        data["size"] = m_size.group(1)
    m_time = re.search(r"time=\s*([\d:.]+)", line)
    if m_time:
        data["time"] = m_time.group(1)
    return data

def update_state(**kwargs):
    ensure_state_dir()
    state = {}
    if STATE_FILE.exists():
        try:
            with open(STATE_FILE, "r", encoding="utf-8") as f:
                state = json.load(f)
        except Exception:
            state = {}
    state.update(kwargs)
    state["updated_at"] = time.time()
    tmp_file = STATE_DIR / f"state.{os.getpid()}.{time.time_ns()}.tmp"
    try:
        fd = os.open(tmp_file, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with open(fd, "w", encoding="utf-8") as f:
            json.dump(state, f, indent=2)
        tmp_file.replace(STATE_FILE)
        try:
            os.chmod(STATE_FILE, 0o600)
        except Exception:
            pass
    except Exception:
        pass

def mask_sensitive(text: str, secret: str = "") -> str:
    if not text:
        return ""
    if secret and len(secret) >= 3:
        text = text.replace(secret, "***REDACTED***")
    # Mask RTMP stream keys in URLs: rtmps://.../<key>
    text = re.sub(r"(rtmps?://[^/\s]+/[^/\s]+/)([^\s\?&#]+)", r"\1***REDACTED***", text)
    return text

def append_log(msg: str, secret: str = ""):
    ensure_state_dir()
    msg_clean = mask_sensitive(msg, secret)
    timestamp = datetime.now().strftime("%H:%M:%S")
    formatted = f"[{timestamp}] {msg_clean}\n"
    try:
        if LOG_FILE.exists() and LOG_FILE.stat().st_size > 1048576:
            # Rotate / prune log file if it exceeds 1MB to avoid infinite growth
            lines = LOG_FILE.read_text(encoding="utf-8", errors="replace").splitlines()
            LOG_FILE.write_text("\n".join(lines[-500:]) + "\n", encoding="utf-8")
            try:
                os.chmod(LOG_FILE, 0o600)
            except Exception:
                pass
        if not LOG_FILE.exists():
            fd = os.open(LOG_FILE, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
            with open(fd, "a", encoding="utf-8") as f:
                f.write(formatted)
        else:
            with open(LOG_FILE, "a", encoding="utf-8") as f:
                f.write(formatted)
    except Exception:
        pass

def clear_logs():
    ensure_state_dir()
    if LOG_FILE.exists():
        LOG_FILE.write_text("")

def fetch_youtube_urls(url: str, quality_preset: str = "") -> list[str]:
    clean_url = url.strip()
    if clean_url.startswith("-"):
        append_log("[ERROR] Invalid YouTube URL: cannot start with '-'")
        return []

    append_log(f"Fetching YouTube stream URL with yt-dlp...")
    yt_dlp_bin = shutil.which("yt-dlp")
    if not yt_dlp_bin:
        append_log("[ERROR] yt-dlp executable not found in PATH.")
        return []

    # Map quality preset to max height
    max_height = 1080
    if "720p" in quality_preset:
        max_height = 720
    elif "480p" in quality_preset:
        max_height = 480

    combined_formats = "301/300/94/93/92/91"
    if max_height <= 480:
        combined_formats = "94/93/92/91"
    elif max_height <= 720:
        combined_formats = "300/94/93/92/91"

    format_spec = (
        f"{combined_formats}/"
        f"bv*[vcodec^=avc1][height<={max_height}]+ba[acodec^=mp4a]/"
        f"bv*[vcodec^=avc1][height<={max_height}]+ba/"
        f"b[vcodec^=avc1][height<={max_height}]/"
        f"bv*[height<={max_height}]+ba/"
        f"b[height<={max_height}]/"
        f"bv*+ba/best"
    )

    cmd = [
        yt_dlp_bin,
        "--extractor-args", "youtube:player_client=android,web",
        "-g", "-f", format_spec,
        "--",
        clean_url
    ]
    try:
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        if res.returncode == 0 and res.stdout.strip():
            urls = [line.strip() for line in res.stdout.strip().splitlines() if line.strip()]
            if urls:
                append_log(f"Successfully extracted {len(urls)} stream URL(s) with yt-dlp.")
                return urls
        err = res.stderr.strip() if res.stderr else "No stream URLs returned."
        append_log(f"[ERROR] yt-dlp failed: {err}")
    except subprocess.TimeoutExpired:
        append_log("[ERROR] yt-dlp timed out while fetching stream URL.")
    except Exception as e:
        append_log(f"[ERROR] yt-dlp execution error: {e}")

    return []

ALLOWED_STREAMING_SCHEMES = ("rtmp://", "rtmps://", "srt://")

def validate_server_url(url: str) -> bool:
    if not url or not isinstance(url, str):
        return False
    url_lower = url.strip().lower()
    return any(url_lower.startswith(scheme) for scheme in ALLOWED_STREAMING_SCHEMES)

def is_raspberry_pi() -> bool:
    try:
        with open("/proc/cpuinfo", "r") as f:
            cpuinfo = f.read()
            if "Raspberry Pi" in cpuinfo or "BCM" in cpuinfo:
                return True
    except Exception:
        pass
    return False

def build_ffmpeg_command(
    input_sources: list[str],
    rtmp_url: str,
    is_local: bool,
    loop_mode: str,
    quality_preset: str,
    is_live_story: bool
) -> list:
    ffmpeg_bin = shutil.which("ffmpeg") or "ffmpeg"
    vcodec = "h264_v4l2m2m" if is_raspberry_pi() else "libx264"
    cmd = [
        ffmpeg_bin,
        "-y",
        "-nostdin",
        "-protocol_whitelist", "file,crypto,data,tls,tcp,http,https,rtmp,rtmps",
        "-fflags", "+genpts+discardcorrupt"
    ]

    if is_local:
        cmd.append("-re")
        if loop_mode == "Loop Infinitely":
            cmd.extend(["-stream_loop", "-1"])
        for inp in input_sources:
            if inp.startswith("-"):
                raise ValueError(f"Invalid input filename '{inp}': cannot start with '-'")
            cmd.extend(["-i", inp])
    else:
        for inp in input_sources:
            if inp.startswith("-"):
                raise ValueError(f"Invalid input URL '{inp}': cannot start with '-'")
            cmd.extend([
                "-thread_queue_size", "4096",
                "-reconnect", "1",
                "-reconnect_streamed", "1",
                "-reconnect_delay_max", "5",
                "-rw_timeout", "15000000",
                "-i", inp
            ])

    if len(input_sources) >= 2:
        cmd.extend(["-map", "0:v:0", "-map", "1:a:0?"])
    elif len(input_sources) == 1:
        cmd.extend(["-map", "0:v:0", "-map", "0:a?"])

    if is_live_story:
        quality_params_story = {
            "1080p (5 Mbps)": {"res": "1080x1920", "bitrate": "5M", "bufsize": "10M"},
            "720p (3 Mbps)": {"res": "720x1280", "bitrate": "3M", "bufsize": "6M"},
            "480p (1.5 Mbps)": {"res": "480x854", "bitrate": "1.5M", "bufsize": "3M"},
        }
        preset = quality_params_story.get(quality_preset, quality_params_story["1080p (5 Mbps)"])
        res = preset["res"]
        width, height = map(int, res.split("x"))
        bitrate = preset["bitrate"]
        bufsize = preset.get("bufsize", "10M")

        # Fast downscaled background blur for 9:16 layout without high CPU penalty
        video_filter = (
            f"[0:v]split=2[original][bg]; "
            f"[bg]scale=180:320:force_original_aspect_ratio=increase,crop=180:320,boxblur=5,scale={width}:{height}[blurred_bg]; "
            f"[original]scale={width}:{height}:force_original_aspect_ratio=decrease[fg]; "
            f"[blurred_bg][fg]overlay=(W-w)/2:(H-h)/2"
        )
        cmd.extend([
            "-vf", video_filter,
            "-vcodec", vcodec,
            "-r", "30",
            "-g", "60",
            "-b:v", bitrate,
            "-maxrate", bitrate,
            "-bufsize", bufsize,
            "-pix_fmt", "yuv420p"
        ])
        if vcodec == "libx264":
            cmd.extend(["-preset", "ultrafast", "-tune", "zerolatency"])
        cmd.extend(["-c:a", "aac", "-b:a", "128k", "-ar", "44100"])
    elif not is_local and quality_preset == "Source Quality":
        # Direct stream copy for network live streams: 0% CPU overhead, 0 frame drops
        cmd.extend([
            "-c:v", "copy",
            "-c:a", "aac",
            "-b:a", "128k",
            "-ar", "44100"
        ])
    else:
        cmd.extend([
            "-vcodec", vcodec,
            "-r", "30",
            "-g", "60",
            "-pix_fmt", "yuv420p"
        ])
        if vcodec == "libx264":
            cmd.extend(["-preset", "ultrafast", "-tune", "zerolatency"])
        quality_params = {
            "1080p (5 Mbps)": ["-s", "1920x1080", "-b:v", "5M", "-maxrate", "5M", "-bufsize", "10M"],
            "720p (3 Mbps)": ["-s", "1280x720", "-b:v", "3M", "-maxrate", "3M", "-bufsize", "6M"],
            "480p (1.5 Mbps)": ["-s", "854x480", "-b:v", "1.5M", "-maxrate", "1.5M", "-bufsize", "3M"],
        }
        if quality_preset in quality_params:
            cmd.extend(quality_params[quality_preset])

        cmd.extend(["-c:a", "aac", "-b:a", "128k", "-ar", "44100"])

    cmd.extend([
        "-avoid_negative_ts", "make_zero",
        "-max_interleave_delta", "0",
        "-max_muxing_queue_size", "4096",
        "-f", "flv",
        "-flvflags", "no_duration_filesize",
        rtmp_url
    ])
    return cmd

class StreamRunner:
    def __init__(self, source: str, server_url: str, stream_key: str,
                 loop_mode: str, quality_preset: str, is_live_story: bool):
        self.source = source
        self.server_url = server_url.rstrip("/")
        self.stream_key = stream_key
        self.loop_mode = loop_mode
        self.quality_preset = quality_preset
        self.is_live_story = is_live_story
        self.is_running = False
        self.stop_requested = False
        self.process = None

    def run(self):
        self.is_running = True
        ensure_state_dir()
        try:
            fd = os.open(PID_FILE, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
            with open(fd, "w", encoding="utf-8") as f:
                f.write(str(os.getpid()))
        except Exception:
            pass

        # Validate server URL scheme (rtmp://, rtmps://, srt://)
        if not validate_server_url(self.server_url):
            err_msg = f"Invalid server URL '{self.server_url}'. Allowed schemes: rtmp://, rtmps://, srt://"
            append_log(f"[ERROR] {err_msg}")
            update_state(status="error", error=err_msg)
            return

        update_state(
            status="starting",
            source=self.source,
            server_url=self.server_url,
            is_live_story=self.is_live_story,
            loop_mode=self.loop_mode,
            quality_preset=self.quality_preset,
            start_time=time.time(),
            pid=os.getpid()
        )
        append_log(f"Starting TeleStream on PID {os.getpid()}...")

        raw_source = self.source.strip()
        is_youtube = (
            raw_source.startswith("http://")
            or raw_source.startswith("https://")
            or "youtube.com" in raw_source
            or "youtu.be" in raw_source
            or (not os.path.exists(raw_source) and len(raw_source) == 11 and bool(re.match(r'^[a-zA-Z0-9_-]{11}$', raw_source)))
        )
        if is_youtube and not raw_source.startswith("http://") and not raw_source.startswith("https://"):
            if len(raw_source) == 11 and re.match(r'^[a-zA-Z0-9_-]{11}$', raw_source):
                raw_source = f"https://www.youtube.com/watch?v={raw_source}"

        # Validate local source file
        if not is_youtube:
            if raw_source.startswith("-"):
                err_msg = f"Invalid video source '{raw_source}': cannot begin with '-'"
                append_log(f"[ERROR] {err_msg}")
                update_state(status="error", error=err_msg)
                return
            if not os.path.exists(raw_source):
                err_msg = f"Local file not found: '{raw_source}'"
                append_log(f"[ERROR] {err_msg}")
                update_state(status="error", error=err_msg)
                return

        full_rtmp = f"{self.server_url}/{self.stream_key}"

        while not self.stop_requested:
            input_sources = [raw_source]
            if is_youtube:
                update_state(status="fetching")
                fetched = fetch_youtube_urls(raw_source, quality_preset=self.quality_preset)
                if not fetched:
                    append_log("[ERROR] Could not resolve YouTube URL. Stopping stream.")
                    update_state(status="error", error="Failed to fetch YouTube URL")
                    break
                input_sources = fetched

            if self.stop_requested:
                break

            try:
                cmd = build_ffmpeg_command(
                    input_sources, full_rtmp, not is_youtube,
                    self.loop_mode, self.quality_preset, self.is_live_story
                )
            except ValueError as ve:
                append_log(f"[ERROR] {ve}")
                update_state(status="error", error=str(ve))
                break

            append_log("Executing ffmpeg...")
            update_state(
                status="streaming",
                telemetry={"frame": 0, "fps": "--", "bitrate": "--", "speed": "--", "size": "--", "time": "00:00:00"}
            )

            try:
                self.process = subprocess.Popen(
                    cmd,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    text=True,
                    bufsize=1,
                    universal_newlines=True
                )
            except Exception as e:
                append_log(f"[ERROR] Failed to spawn ffmpeg: {e}", secret=self.stream_key)
                update_state(status="error", error=str(e), telemetry={})
                break

            # Read ffmpeg output line by line with progress throttling and key masking
            last_progress = 0.0
            last_telemetry = {}
            for line in self.process.stdout:
                line_clean = line.strip()
                if line_clean:
                    is_progress = "frame=" in line_clean or "bitrate=" in line_clean
                    now = time.time()
                    if is_progress:
                        t = parse_telemetry(line_clean)
                        if t:
                            last_telemetry.update(t)
                        if now - last_progress >= 1.0:
                            append_log(line_clean, secret=self.stream_key)
                            if last_telemetry:
                                update_state(telemetry=last_telemetry)
                            last_progress = now
                    else:
                        append_log(line_clean, secret=self.stream_key)
                if self.stop_requested:
                    break

            self.process.wait()
            ret = self.process.returncode
            self.process = None

            if self.stop_requested:
                append_log("Stream stopped by user request.")
                break

            append_log(f"ffmpeg exited with code {ret}.")

            # If it's YouTube and loop mode is infinite, restart the cycle
            if is_youtube and self.loop_mode == "Loop Infinitely" and not self.stop_requested:
                append_log("Re-looping YouTube stream in 3 seconds...")
                time.sleep(3)
            else:
                break

        self.cleanup()

    def stop(self):
        self.stop_requested = True
        if self.process and self.process.poll() is None:
            append_log("Terminating ffmpeg...")
            try:
                self.process.terminate()
                try:
                    self.process.wait(timeout=4)
                except subprocess.TimeoutExpired:
                    append_log("ffmpeg hung; killing process...")
                    self.process.kill()
            except Exception as e:
                append_log(f"Error terminating process: {e}")

    def cleanup(self):
        self.is_running = False
        if PID_FILE.exists():
            PID_FILE.unlink(missing_ok=True)
        update_state(status="idle", pid=None, telemetry={})
        append_log("TeleStream is idle.")

RUNNER = None

def signal_handler(signum, frame):
    global RUNNER
    if RUNNER:
        RUNNER.stop()
    sys.exit(0)

def cmd_start(args):
    global RUNNER
    # Record recent source in history (max 5 per mode)
    try:
        add_recent_source(args.source)
    except Exception:
        pass

    # Reject insecure CLI parameter if passed
    if getattr(args, "key", None):
        err_msg = (
            "Passing stream keys via --key is insecure because process command lines "
            "are world-readable in /proc/<pid>/cmdline. "
            "Please pass your stream key securely via standard input (--key-stdin), "
            "an inherited file descriptor (--key-fd), a protected file (--key-file), "
            "or use a saved favorite (--favorite)."
        )
        sys.stderr.write(f"Error: {err_msg}\n")
        print(json.dumps({"error": err_msg}))
        sys.exit(1)

    # Resolve server URL and stream key securely
    server_url = (args.server or "").strip()
    stream_key = ""

    if getattr(args, "favorite", None):
        cfg = load_config()
        for fav in cfg.get("favorites", []):
            if fav.get("name") == args.favorite:
                if not server_url:
                    server_url = fav.get("url", "").strip()
                stream_key = fav.get("key", "").strip()
                break

    if not stream_key:
        if getattr(args, "key_stdin", False):
            if not sys.stdin.isatty():
                stream_key = sys.stdin.readline().rstrip("\r\n").strip()
            else:
                import getpass
                stream_key = getpass.getpass("Enter Stream Key: ").strip()
        elif getattr(args, "key_fd", None) is not None:
            try:
                fd = int(args.key_fd)
                stream_key = os.read(fd, 4096).decode("utf-8").rstrip("\r\n").strip()
            except Exception as e:
                sys.stderr.write(f"Error reading stream key from fd {args.key_fd}: {e}\n")
                sys.exit(1)
        elif getattr(args, "key_file", None):
            try:
                key_path = Path(args.key_file).resolve()
                if not key_path.exists():
                    sys.stderr.write(f"Error: Stream key file does not exist: {key_path}\n")
                    sys.exit(1)
                st = key_path.stat()
                if st.st_mode & 0o077:
                    sys.stderr.write(f"Warning: Stream key file has loose permissions ({oct(st.st_mode)}). Expected 0600.\n")
                stream_key = key_path.read_text(encoding="utf-8").rstrip("\r\n").strip()
            except Exception as e:
                sys.stderr.write(f"Error reading stream key from file: {e}\n")
                sys.exit(1)
        elif not sys.stdin.isatty():
            try:
                import select
                r, _, _ = select.select([sys.stdin], [], [], 0)
                if r:
                    stream_key = sys.stdin.readline().rstrip("\r\n").strip()
            except Exception:
                pass
        elif os.environ.get("TELESTREAM_KEY", "").strip():
            # Fallback only - environment variable alone is not an equivalent confidentiality boundary
            stream_key = os.environ.get("TELESTREAM_KEY", "").strip()

    if not server_url:
        sys.stderr.write("Error: Server URL is required (--server or --favorite)\n")
        print(json.dumps({"error": "Server URL is required"}))
        sys.exit(1)

    if not stream_key:
        sys.stderr.write("Error: Stream key is required (--key-stdin, --key-fd, --key-file, or --favorite)\n")
        print(json.dumps({"error": "Stream key is required"}))
        sys.exit(1)

    if not validate_server_url(server_url):
        err_msg = f"Invalid server URL scheme in '{server_url}'. Allowed schemes: rtmp://, rtmps://, srt://"
        sys.stderr.write(f"Error: {err_msg}\n")
        print(json.dumps({"error": err_msg}))
        sys.exit(1)

    # Check if already running
    if PID_FILE.exists():
        try:
            pid = int(PID_FILE.read_text().strip())
            os.kill(pid, 0)
            print(json.dumps({"status": "already_running", "pid": pid}))
            return
        except (ValueError, OSError):
            PID_FILE.unlink(missing_ok=True)

    RUNNER = StreamRunner(
        source=args.source,
        server_url=server_url,
        stream_key=stream_key,
        loop_mode=args.loop,
        quality_preset=args.preset,
        is_live_story=args.story
    )
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    RUNNER.run()

def cmd_stop():
    if PID_FILE.exists():
        try:
            pid = int(PID_FILE.read_text().strip())
            os.kill(pid, signal.SIGTERM)
            print(json.dumps({"status": "stopping", "pid": pid}))
            return
        except OSError:
            PID_FILE.unlink(missing_ok=True)
    update_state(status="idle", pid=None, telemetry={})
    print(json.dumps({"status": "not_running"}))

def cmd_status():
    ensure_state_dir()
    state = {"status": "idle"}
    if STATE_FILE.exists():
        try:
            with open(STATE_FILE, "r", encoding="utf-8") as f:
                state = json.load(f)
        except Exception:
            pass

    # Verify if process is actually alive
    pid = state.get("pid")
    if pid:
        try:
            os.kill(pid, 0)
        except OSError:
            state["status"] = "idle"
            state["pid"] = None
            update_state(status="idle", pid=None)

    print(json.dumps(state))

def cmd_get_config():
    cfg = load_config()
    print(json.dumps(cfg))

def cmd_save_favorite(name: str, url: str, key: str = None, old_name: str = None,
                      key_stdin: bool = False, key_fd: int = None, key_file: str = None):
    # Reject insecure positional key argument
    if key:
        err_msg = (
            "Passing stream keys as command-line arguments is insecure because "
            "process command lines are world-readable in /proc/<pid>/cmdline. "
            "Please pass your stream key securely via standard input (--key-stdin), "
            "an inherited file descriptor (--key-fd), or a protected file (--key-file)."
        )
        sys.stderr.write(f"Error: {err_msg}\n")
        print(json.dumps({"error": err_msg}))
        sys.exit(1)

    resolved_key = ""
    if key_stdin:
        if not sys.stdin.isatty():
            resolved_key = sys.stdin.readline().rstrip("\r\n").strip()
        else:
            import getpass
            resolved_key = getpass.getpass("Enter Stream Key: ").strip()
    elif key_fd is not None:
        try:
            resolved_key = os.read(key_fd, 4096).decode("utf-8").rstrip("\r\n").strip()
        except Exception as e:
            sys.stderr.write(f"Error reading stream key from fd {key_fd}: {e}\n")
            sys.exit(1)
    elif key_file:
        try:
            key_p = Path(key_file).resolve()
            resolved_key = key_p.read_text(encoding="utf-8").rstrip("\r\n").strip()
        except Exception as e:
            sys.stderr.write(f"Error reading stream key from file: {e}\n")
            sys.exit(1)
    elif not sys.stdin.isatty():
        try:
            import select
            r, _, _ = select.select([sys.stdin], [], [], 0)
            if r:
                resolved_key = sys.stdin.readline().rstrip("\r\n").strip()
        except Exception:
            pass

    if not resolved_key:
        sys.stderr.write("Error: Stream key is required (--key-stdin, --key-fd, or --key-file)\n")
        print(json.dumps({"error": "Stream key is required"}))
        sys.exit(1)

    cfg = load_config()
    favs = cfg.get("favorites", [])

    # If renaming an existing favorite
    if old_name and old_name != name:
        favs = [f for f in favs if f.get("name") != old_name]

    found = False
    for item in favs:
        if item.get("name") == name:
            item["url"] = url
            item["key"] = resolved_key
            found = True
            break
    if not found:
        favs.append({"name": name, "url": url, "key": resolved_key})

    cfg["favorites"] = favs
    cfg["last_favorite_name"] = name
    save_config(cfg)
    print(json.dumps({"success": True, "favorites": favs, "last_favorite_name": name}))

def cmd_remove_favorite(name: str):
    cfg = load_config()
    favs = [f for f in cfg.get("favorites", []) if f.get("name") != name]
    cfg["favorites"] = favs
    if cfg.get("last_favorite_name") == name:
        cfg["last_favorite_name"] = favs[0]["name"] if favs else None
    save_config(cfg)
    print(json.dumps({"success": True, "favorites": favs}))

def cmd_set_last_favorite(name: str):
    cfg = load_config()
    cfg["last_favorite_name"] = name if name else None
    save_config(cfg)
    print(json.dumps({"success": True, "last_favorite_name": cfg["last_favorite_name"]}))

def cmd_save_log_file():
    ensure_state_dir()
    if not LOG_FILE.exists():
        print(json.dumps({"success": False, "error": "Log file is empty"}))
        return
    timestamp = datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
    out_path = Path.home() / f"telestream_log_{timestamp}.txt"
    try:
        shutil.copy(LOG_FILE, out_path)
        print(json.dumps({"success": True, "path": str(out_path)}))
    except Exception as e:
        print(json.dumps({"success": False, "error": str(e)}))

def main():
    parser = argparse.ArgumentParser(description="TeleStream Backend CLI")
    subparsers = parser.add_subparsers(dest="subcommand")

    # start
    p_start = subparsers.add_parser("start")
    p_start.add_argument("--source", required=True, help="Video path or YouTube URL")
    p_start.add_argument("--server", default="", help="RTMP Server URL (e.g. rtmps://...)")
    p_start.add_argument("--key-stdin", action="store_true", help="Read stream key securely from standard input (prevents /proc/cmdline leaks)")
    p_start.add_argument("--key-fd", type=int, default=None, help="Read stream key securely from an inherited file descriptor")
    p_start.add_argument("--key-file", default=None, help="Read stream key securely from a file (mode 0600)")
    p_start.add_argument("--key", default=None, help=argparse.SUPPRESS)
    p_start.add_argument("--favorite", default=None, help="Favorite server name to resolve URL and Key securely")
    p_start.add_argument("--loop", default="Loop Infinitely", choices=["Loop Infinitely", "Play Once"])
    p_start.add_argument("--preset", default="Source Quality")
    p_start.add_argument("--story", action="store_true", help="Live Story 9:16 mode")
    p_start.add_argument("--rpi", action="store_true", help=argparse.SUPPRESS)

    # stop
    subparsers.add_parser("stop")

    # status
    subparsers.add_parser("status")

    # get-config
    subparsers.add_parser("get-config")

    # save-favorite
    p_fav = subparsers.add_parser("save-favorite")
    p_fav.add_argument("name", help="Favorite profile name")
    p_fav.add_argument("url", help="RTMP Server URL")
    p_fav.add_argument("--key-stdin", action="store_true", help="Read stream key securely from standard input")
    p_fav.add_argument("--key-fd", type=int, default=None, help="Read stream key securely from an inherited file descriptor")
    p_fav.add_argument("--key-file", default=None, help="Read stream key securely from a file (mode 0600)")
    p_fav.add_argument("key", nargs="?", default=None, help=argparse.SUPPRESS)
    p_fav.add_argument("--old-name", dest="old_name", default=None)

    # remove-favorite
    p_rfav = subparsers.add_parser("remove-favorite")
    p_rfav.add_argument("name")

    # set-last-favorite
    p_last = subparsers.add_parser("set-last-favorite")
    p_last.add_argument("name", nargs="?", default="")

    # clear-logs
    subparsers.add_parser("clear-logs")

    # save-log-file
    subparsers.add_parser("save-log-file")

    # add-recent
    p_add_rec = subparsers.add_parser("add-recent")
    p_add_rec.add_argument("source_pos", nargs="?", default=None)
    p_add_rec.add_argument("--source", dest="source_opt", default=None)
    p_add_rec.add_argument("--url", action="store_true", default=None)
    p_add_rec.add_argument("--local", action="store_true", default=None)

    # remove-recent
    p_rem_rec = subparsers.add_parser("remove-recent")
    p_rem_rec.add_argument("source_pos", nargs="?", default=None)
    p_rem_rec.add_argument("--source", dest="source_opt", default=None)
    p_rem_rec.add_argument("--type", default="auto")

    # clear-recent
    p_clr_rec = subparsers.add_parser("clear-recent")
    p_clr_rec.add_argument("--type", default="all")

    args = parser.parse_args()

    if args.subcommand == "start":
        cmd_start(args)
    elif args.subcommand == "stop":
        cmd_stop()
    elif args.subcommand == "status":
        cmd_status()
    elif args.subcommand == "get-config":
        cmd_get_config()
    elif args.subcommand == "save-favorite":
        cmd_save_favorite(
            args.name,
            args.url,
            key=getattr(args, "key", None),
            old_name=getattr(args, "old_name", None),
            key_stdin=getattr(args, "key_stdin", False),
            key_fd=getattr(args, "key_fd", None),
            key_file=getattr(args, "key_file", None),
        )
    elif args.subcommand == "remove-favorite":
        cmd_remove_favorite(args.name)
    elif args.subcommand == "set-last-favorite":
        cmd_set_last_favorite(args.name)
    elif args.subcommand == "clear-logs":
        clear_logs()
        print(json.dumps({"success": True}))
    elif args.subcommand == "save-log-file":
        cmd_save_log_file()
    elif args.subcommand == "add-recent":
        src = args.source_pos or args.source_opt
        if not src:
            parser.error("source is required")
        is_url = True if args.url else (False if args.local else None)
        add_recent_source(src, is_url=is_url)
        print(json.dumps({"success": True}))
    elif args.subcommand == "remove-recent":
        src = args.source_pos or args.source_opt
        if not src:
            parser.error("source is required")
        remove_recent_source(src, mode=args.type)
        print(json.dumps({"success": True}))
    elif args.subcommand == "clear-recent":
        clear_recent_sources(mode=args.type)
        print(json.dumps({"success": True}))
    else:
        parser.print_help()

if __name__ == "__main__":
    main()
