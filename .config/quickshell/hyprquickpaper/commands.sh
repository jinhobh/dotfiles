#!/usr/bin/env bash
set -e
export PATH="$HOME/.local/bin:$PATH"
img="$1"
[[ -f "$img" ]] || { echo "commands.sh: not a file: $img" >&2; exit 1; }
cache="${XDG_CACHE_HOME:-$HOME/.cache}/43pr"
mkdir -p "$cache"
# Serialize selection and restoration, including player replacement.
exec 9>"$cache/wallpaper.lock"
flock 9
if [[ "${img,,}" == *.mp4 ]]; then
    command -v mpvpaper >/dev/null || {
        echo "MP4 wallpapers require mpvpaper (install with yay -S mpvpaper)." >&2
        exit 1
    }
    # Validate the video before replacing the current wallpaper.
    ffmpeg -nostdin -v error -y -i "$img" -frames:v 1 \
        -vf 'scale=-2:500' "$cache/video-frame.jpg"
    awww img "$cache/video-frame.jpg" -t none
    pkill -u "$(id -u)" -x mpvpaper || true
    setsid python3 "$(dirname "$(readlink -f "$0")")/video-wallpaper.py" "$img" 9>&- \
        >>"$cache/video-wallpaper.log" 2>&1 &
    player_pid=$!
    sleep 0.5
    kill -0 "$player_pid" 2>/dev/null || {
        echo "Video wallpaper failed; see $cache/video-wallpaper.log" >&2
        exit 1
    }
else
    awww img "$img" -t "${WALLPAPER_TRANSITION:-random}" --transition-duration 1
    pkill -u "$(id -u)" -x mpvpaper || true
fi

setsid -f python3 "$HOME/.config/43pr/bin/theme.py" wallpaper "$img" 9>&- \
    >>"$cache/theme.log" 2>&1
