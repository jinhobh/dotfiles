#!/usr/bin/env python3
"""Play a live wallpaper while at least one display shows an empty workspace."""

import json
import os
from pathlib import Path
import select
import signal
import socket
import subprocess
import sys
import tempfile
import time


WORKSPACE_EVENTS = {
    "workspace", "workspacev2", "focusedmon", "focusedmonv2",
    "openwindow", "closewindow", "movewindow", "movewindowv2",
    "moveworkspace", "moveworkspacev2", "activespecial", "activespecialv2",
    "monitoradded", "monitoraddedv2", "monitorremoved", "configreloaded", "pin",
}


def should_pause(monitors, workspaces):
    windows = {workspace["id"]: workspace["windows"] for workspace in workspaces}
    displays = [monitor for monitor in monitors
                if not monitor.get("disabled", False) and monitor.get("dpmsStatus", True)]
    if not displays:
        return True
    return all(any(windows.get(monitor.get(kind, {}).get("id", 0), 0) > 0
                   for kind in ("activeWorkspace", "specialWorkspace"))
               for monitor in displays)


def desktop_paused():
    def query(name):
        result = subprocess.run(["hyprctl", "-j", name], check=True,
                                capture_output=True, text=True, timeout=2)
        return json.loads(result.stdout)

    try:
        return should_pause(query("monitors"), query("workspaces"))
    except (OSError, subprocess.SubprocessError, ValueError, KeyError, TypeError):
        # Keep playback paused until the compositor can report workspace state.
        return True


def set_paused(ipc_path, paused):
    with socket.socket(socket.AF_UNIX) as ipc:
        ipc.settimeout(1)
        ipc.connect(str(ipc_path))
        command = {"command": ["set_property", "pause", paused]}
        ipc.sendall(json.dumps(command).encode() + b"\n")
        with ipc.makefile("rb") as replies:
            for line in replies:
                reply = json.loads(line)
                if "error" in reply:
                    return reply["error"] == "success"
    return False


def watch(player, ipc_path):
    runtime = Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}"))
    event_path = runtime / "hypr" / os.environ["HYPRLAND_INSTANCE_SIGNATURE"] / ".socket2.sock"
    events = None
    pending = b""
    last_paused = None
    refresh_at = 0
    try:
        while player.poll() is None:
            if events is None:
                connection = socket.socket(socket.AF_UNIX)
                connection.settimeout(1)
                try:
                    connection.connect(str(event_path))
                    events = connection
                    pending = b""
                    refresh_at = 0
                except OSError:
                    connection.close()

            if time.monotonic() >= refresh_at:
                paused = desktop_paused()
                try:
                    if paused != last_paused and set_paused(ipc_path, paused):
                        last_paused = paused
                except (OSError, ValueError):
                    last_paused = None
                # Retry startup failures promptly; also recover from missed events.
                refresh_at = time.monotonic() + (1 if last_paused is None else 5)

            readable, _, _ = select.select([events] if events else [], [], [], 0.2)
            if readable:
                try:
                    data = events.recv(65536)
                except OSError:
                    data = b""
                if not data:
                    events.close()
                    events = None
                    refresh_at = 0
                    continue
                pending += data
                lines = pending.split(b"\n")
                pending = lines.pop()
                if any(line.partition(b">>")[0].decode(errors="replace") in WORKSPACE_EVENTS
                       for line in lines):
                    refresh_at = 0
    finally:
        if events is not None:
            events.close()


def main():
    def stop(signum, frame):
        raise SystemExit(0)

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    with tempfile.TemporaryDirectory(prefix="43pr-video-", dir=os.environ.get("XDG_RUNTIME_DIR")) as directory:
        ipc_path = Path(directory) / "mpv.sock"
        options = f"no-config no-audio loop-file=inf panscan=1 hwdec=auto pause=yes input-ipc-server={ipc_path}"
        player = subprocess.Popen(["mpvpaper", "-o", options, "ALL", sys.argv[1]])
        try:
            watch(player, ipc_path)
            return player.returncode
        finally:
            if player.poll() is None:
                player.terminate()
                try:
                    player.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    player.kill()
                    player.wait()


if __name__ == "__main__":
    sys.exit(main())
