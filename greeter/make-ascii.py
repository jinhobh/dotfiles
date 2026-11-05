#!/usr/bin/env python3
"""Convert a video, a folder of images, or a folder of .txt frames into
ascii/frames.json for the greeter.

  ./make-ascii.py clip.mp4 --width 60 --fps 12
  ./make-ascii.py frames/            # *.png / *.jpg  -> converted
  ./make-ascii.py frames/            # *.txt          -> used as-is
  ./make-ascii.py clip.mp4 --invert  # light background -> dark background
  ./make-ascii.py export.json        # {"frameRate", "frames": [{"rows": [...]}]}
"""
import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

RAMP = " .:-=+*#%@"  # dark -> bright; black pixels become spaces
IMAGE_EXTS = {".png", ".jpg", ".jpeg", ".webp", ".bmp", ".gif"}


def natural(path):
    return [int(t) if t.isdigit() else t for t in re.split(r"(\d+)", path.name)]


def trim_margins(frames):
    """Drop blank rows/columns that every frame shares, keeping frames aligned."""
    grids = [f.split("\n") for f in frames]
    used = [i for g in grids for i, line in enumerate(g) if line.strip()]
    if not used:
        return frames
    top, bottom = min(used), max(used)
    indent = min(len(line) - len(line.lstrip(" "))
                 for g in grids for line in g if line.strip())
    rows = [[line[indent:].rstrip() for line in g[top:bottom + 1]] for g in grids]
    # Pad to one width so a right-anchored animation doesn't jump between frames.
    width = max(len(line) for r in rows for line in r)
    return ["\n".join(line.ljust(width) for line in r) for r in rows]


def probe_size(src):
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v:0",
         "-show_entries", "stream=width,height", "-of", "csv=p=0", src],
        capture_output=True, text=True, check=True).stdout
    w, h = out.strip().splitlines()[0].split(",")[:2]
    return int(w), int(h)


def frames_from_pixels(input_args, size_src, a):
    w, h = probe_size(size_src)
    cols = a.width
    rows = max(1, round(cols * h / w * a.aspect))
    cmd = ["ffmpeg", "-v", "error", *input_args,
           "-vf", f"fps={a.fps},scale={cols}:{rows}:flags=area,format=gray",
           "-f", "rawvideo", "-"]
    raw = subprocess.run(cmd, capture_output=True, check=True).stdout
    ramp = a.ramp[::-1] if a.invert else a.ramp
    n = len(ramp) - 1
    size = cols * rows
    frames = []
    for i in range(0, len(raw) - size + 1, size):
        px = raw[i:i + size]
        lines = []
        for r in range(rows):
            row = px[r * cols:(r + 1) * cols]
            lines.append("".join(ramp[round(v / 255 * n)] for v in row).rstrip())
        frames.append("\n".join(lines))
    return frames


def main():
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("input", help="video file or folder of frames")
    p.add_argument("-o", "--output", default=str(Path(__file__).parent / "ascii/frames.json"))
    p.add_argument("--width", type=int, default=60, help="columns (default 60)")
    p.add_argument("--fps", type=float, help="default: the JSON export's frameRate, else 12")
    p.add_argument("--aspect", type=float, default=0.45,
                   help="character width/height ratio of the font (default 0.45)")
    p.add_argument("--invert", action="store_true", help="for light-background sources")
    p.add_argument("--ramp", default=RAMP, help="dark->bright characters (default %(default)r)")
    p.add_argument("--skip", type=int, default=0, help="drop this many frames from the start")
    p.add_argument("--seconds", type=float, help="keep only this many seconds (after --skip)")
    p.add_argument("--start", help="video start time, e.g. 1.5 or 00:00:03")
    p.add_argument("--duration", help="video length to convert, e.g. 4")
    a = p.parse_args()
    if a.fps is None and Path(a.input).suffix.lower() != ".json":
        a.fps = 12

    src = Path(a.input)
    if src.suffix.lower() == ".json":
        data = json.loads(src.read_text())
        a.fps = a.fps or data.get("frameRate")
        frames = ["\n".join(f["rows"]) for f in data["frames"]]
    elif src.is_dir():
        txts = sorted(src.glob("*.txt"), key=natural)
        imgs = sorted((f for f in src.iterdir() if f.suffix.lower() in IMAGE_EXTS), key=natural)
        if txts:
            frames = [f.read_text().rstrip("\n") for f in txts]
        elif imgs:
            ext = imgs[0].suffix
            frames = frames_from_pixels(
                ["-framerate", str(a.fps), "-pattern_type", "glob",
                 "-i", str(src / f"*{ext}")], str(imgs[0]), a)
        else:
            sys.exit(f"no .txt or image frames in {src}")
    else:
        trim = (["-ss", a.start] if a.start else []) + (["-t", a.duration] if a.duration else [])
        frames = frames_from_pixels([*trim, "-i", str(src)], str(src), a)

    frames = frames[a.skip:]
    if a.seconds:
        frames = frames[:round(a.seconds * (a.fps or 12))]
    if not frames:
        sys.exit("no frames produced")
    frames = trim_margins(frames)
    a.fps = a.fps or 12
    out = Path(a.output)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps({"fps": a.fps, "frames": frames}))
    print(f"{len(frames)} frames @ {a.fps} fps -> {out}")


if __name__ == "__main__":
    main()
