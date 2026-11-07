#!/usr/bin/env bash

CONFIG="$1/config.json"

expand_home() {
    local path="$1"

    if [[ "$path" == '$HOME' ]]; then
        printf '%s\n' "$HOME"
    elif [[ "$path" == '$HOME/'* ]]; then
        printf '%s/%s\n' "$HOME" "${path#'$HOME/'}"
    else
        printf '%s\n' "$path"
    fi
}

wallpaper_path=$(expand_home "$(jq -r '.wallpaper_path' "$CONFIG")")
cache_path=$(expand_home "$(jq -r '.cache_path' "$CONFIG")")
cache_batch_size=$(jq -r '.cache_batch_size' "$CONFIG")

mkdir -p "$cache_path"

echo "Wallpaper path: $wallpaper_path"
echo "Cache path: $cache_path"

generate_thumbnail() {
    local img="$1" filename out tmp filename_format
    filename_format="${img##*.}"
    filename=$(basename "$img")
    out="$cache_path/$filename"
    [[ "${img,,}" == *.mp4 ]] && out+=".jpg"
    [[ -s "$out" && "$out" -nt "$img" ]] && return
    tmp=$(mktemp "$cache_path/.thumb-XXXXXXXX") || return
    if [[ "${img,,}" == *.mp4 ]]; then
        ffmpeg -nostdin -v error -y -i "$img" -frames:v 1 \
            -vf 'scale=-2:500' -c:v mjpeg -f image2 -update 1 "$tmp"
    else
        convert "$img[0]" -thumbnail x500 -strip -quality 85 "$filename_format:$tmp"
    fi && mv -f "$tmp" "$out"
    rm -f "$tmp"
}

# Keep jobs in this shell so wait includes every thumbnail worker.
while IFS= read -r -d '' img; do
    generate_thumbnail "$img" &
    if (( cache_batch_size > 0 )); then
        while (( $(jobs -rp | wc -l) >= cache_batch_size )); do
            wait -n || true
        done
    fi
done < <(find "$wallpaper_path" -maxdepth 1 -type f \( \
    -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o \
    -iname '*.gif' -o -iname '*.webp' -o -iname '*.mp4' \) -print0)
wait
echo "Thumbnail generation complete."
