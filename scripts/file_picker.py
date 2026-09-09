#!/usr/bin/env python3
"""
file_picker.py - Desktop video file picker for TeleStream on Omarchy (Hyprland / Quickshell).
Uses GTK FileChooserNative (XDG Desktop Portal) or tkinter fallback.
Communicates chosen file path back to TeleStream via stdout and omarchy-shell IPC.
"""

import sys
import os
import json
import shutil
import tempfile
import subprocess
from urllib.parse import unquote, urlparse

# If current python lacks gi, re-exec with system python /usr/bin/python3
try:
    import gi
except ImportError:
    system_python = "/usr/bin/python3"
    if os.path.exists(system_python) and sys.executable != system_python:
        try:
            os.execv(system_python, [system_python] + sys.argv)
        except Exception:
            pass

def pick_with_flea() -> str:
    """Primary: Native keyboard-first Flea picker for Omarchy."""
    flea_bin = shutil.which("flea") or "/usr/bin/flea"
    if not (os.path.exists(flea_bin) and os.access(flea_bin, os.X_OK)):
        return ""

    with tempfile.TemporaryDirectory(prefix="telestream-flea-") as tmpdir:
        reply_path = os.path.join(tmpdir, "reply.json")
        picker_req = {
            "mode": "open",
            "title": "Select Video File - TeleStream",
            "app": "dorneles.telestream",
            "accept": "Open",
            "multiple": False,
            "directory": False,
            "folder": os.path.expanduser("~/Videos") if os.path.isdir(os.path.expanduser("~/Videos")) else os.path.expanduser("~"),
            "file": "",
            "name": "",
            "files": [],
            "filters": [
                {
                    "label": "Video Files (*.mp4, *.mkv, *.avi, ...)",
                    "globs": ["*.mp4", "*.mkv", "*.avi", "*.mov", "*.webm", "*.flv", "*.ts", "*.m4v"],
                    "mimes": ["video/*"]
                },
                {
                    "label": "All Files (*.*)",
                    "globs": ["*"],
                    "mimes": []
                }
            ],
            "current": "Video Files (*.mp4, *.mkv, *.avi, ...)"
        }

        env = os.environ.copy()
        env["FLEA_PICKER"] = json.dumps(picker_req)

        try:
            res = subprocess.run([flea_bin, "--pick", reply_path], env=env, capture_output=True)
            if os.path.exists(reply_path):
                with open(reply_path, "r", encoding="utf-8") as f:
                    data = json.load(f)
                if isinstance(data, dict) and data.get("response") == 0:
                    uris = data.get("uris", [])
                    if uris and isinstance(uris[0], str):
                        uri = uris[0]
                        if uri.startswith("file://"):
                            parsed = urlparse(uri)
                            return unquote(parsed.path)
                        return uri
        except Exception as e:
            sys.stderr.write(f"flea picker error: {e}\n")

    return ""

def pick_with_omarchy() -> str:
    """Fallback 1: omarchy-file-select portal wrapper."""
    omarchy_select = shutil.which("omarchy-file-select") or "/usr/share/omarchy/bin/omarchy-file-select"
    if os.path.exists(omarchy_select) and os.access(omarchy_select, os.X_OK):
        try:
            res = subprocess.run(
                [omarchy_select, "--title", "Select Video File - TeleStream",
                 "--extensions", "mp4 mkv avi mov webm flv ts m4v mpg mpeg"],
                capture_output=True, text=True
            )
            if res.returncode == 0 and res.stdout.strip():
                return res.stdout.strip().split("\n")[0]
        except Exception:
            pass
    return ""

def pick_with_gtk() -> str:
    """Fallback 2: GTK FileChooserNative (XDG Desktop Portal)."""
    try:
        import gi
        gi.require_version('Gtk', '3.0')
        from gi.repository import Gtk
        native = Gtk.FileChooserNative.new(
            "Select Video File - TeleStream",
            None,
            Gtk.FileChooserAction.OPEN,
            "_Open",
            "_Cancel"
        )
        filter_vid = Gtk.FileFilter()
        filter_vid.set_name("Video Files (*.mp4, *.mkv, *.avi, *.mov, *.webm, *.flv)")
        filter_vid.add_mime_type("video/*")
        for ext in ["*.mp4", "*.mkv", "*.avi", "*.mov", "*.webm", "*.flv", "*.ts", "*.m4v"]:
            filter_vid.add_pattern(ext)
        native.add_filter(filter_vid)

        filter_all = Gtk.FileFilter()
        filter_all.set_name("All Files (*.*)")
        filter_all.add_pattern("*")
        native.add_filter(filter_all)

        response = native.run()
        selected = ""
        if response == Gtk.ResponseType.ACCEPT:
            selected = native.get_filename() or ""
        native.destroy()
        if selected:
            return selected
    except Exception:
        pass
    return ""

def pick_file() -> str:
    # 1. Flea (Default native Omarchy file manager/picker)
    path = pick_with_flea()
    if path:
        return path

    # 2. Omarchy file select
    path = pick_with_omarchy()
    if path:
        return path

    # 3. GTK FileChooserNative
    path = pick_with_gtk()
    if path:
        return path

    # 4. Zenity if installed
    zenity = shutil.which("zenity")
    if zenity:
        try:
            res = subprocess.run(
                [zenity, "--file-selection", "--title=Select Video File",
                 "--file-filter=Video files (*.mp4 *.mkv *.avi *.mov *.webm *.flv) | *.mp4 *.mkv *.avi *.mov *.webm *.flv",
                 "--file-filter=All files | *"],
                capture_output=True, text=True
            )
            if res.returncode == 0 and res.stdout.strip():
                return res.stdout.strip()
        except Exception:
            pass

    # 5. Tkinter fallback
    try:
        import tkinter as tk
        from tkinter import filedialog
        root = tk.Tk()
        root.withdraw()
        root.attributes("-topmost", True)
        file_path = filedialog.askopenfilename(
            title="Select Video File",
            filetypes=[
                ("Video Files", "*.mp4 *.mkv *.avi *.mov *.webm *.flv *.ts *.m4v"),
                ("All Files", "*.*")
            ]
        )
        root.destroy()
        return file_path or ""
    except Exception:
        pass

    return ""

if __name__ == "__main__":
    result = pick_file()
    omarchy_shell = shutil.which("omarchy-shell") or "/usr/share/omarchy/bin/omarchy-shell"

    if result:
        print(result)
        # Notify Omarchy shell IPC
        if os.path.exists(omarchy_shell):
            try:
                subprocess.run(
                    [omarchy_shell, "dorneles.telestream", "setVideoPath", result],
                    capture_output=True, timeout=3
                )
            except Exception:
                pass
    else:
        # Re-open panel if cancelled
        if os.path.exists(omarchy_shell):
            try:
                subprocess.run(
                    [omarchy_shell, "dorneles.telestream", "open"],
                    capture_output=True, timeout=3
                )
            except Exception:
                pass
