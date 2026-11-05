#!/usr/bin/env bash
# Installs the greeter into /etc/greetd and enables greetd. Run with sudo.
# Re-run after changing shell.qml or the animation to update the installed copy.
set -euo pipefail
cd "$(dirname "$0")"

pacman -S --needed --noconfirm greetd

install -d /etc/greetd/greeter/ascii
install -m644 shell.qml /etc/greetd/greeter/shell.qml
install -m644 ascii/frames.json /etc/greetd/greeter/ascii/frames.json
install -m644 hyprland.lua /etc/greetd/hyprland.lua

# Quickshell and Hyprland want a writable home for cache/state.
home=$(getent passwd greeter | cut -d: -f6)
install -d -o greeter -g greeter "$home"

if [[ -f /etc/greetd/config.toml && ! -f /etc/greetd/config.toml.orig ]]; then
    cp /etc/greetd/config.toml /etc/greetd/config.toml.orig
fi
cat > /etc/greetd/config.toml <<'TOML'
[terminal]
vt = 1

[default_session]
command = "start-hyprland -- --config /etc/greetd/hyprland.lua"
user = "greeter"
TOML

systemctl enable greetd.service
echo "Installed. Reboot to see it. If it breaks: Ctrl+Alt+F2, log in, 'sudo systemctl disable greetd'."
