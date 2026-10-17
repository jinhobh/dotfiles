#!/usr/bin/env bash
# install-ubuntu.sh - Ubuntu 26.04 installer for the 43PR Hyprland setup.
#
# Upstream install.sh only supports Arch (it uses pacman and AUR helpers), so
# this is a separate script. It does the same linking and theme steps and
# skips the package-manager parts. The apt packages and the Hyprland stack
# (Hyprland, quickshell, awww, hyprlock) must already be installed.
#
#   ./install-ubuntu.sh
#
# Existing files that would be replaced are moved to ~/.config-backups/<timestamp>/.
# Symlinks that already exist are repointed without a backup (they are only
# printed); the rollback snapshot covers them.
set -uo pipefail

if [[ "${EUID}" -eq 0 ]]; then
    echo "[ERROR] Do not run this script as root." >&2
    exit 1
fi

if [[ ! -f /etc/os-release ]]; then
    echo "[ERROR] Cannot determine the operating system." >&2
    exit 1
fi
# shellcheck disable=SC1091
source /etc/os-release
if [[ "${ID:-}" != "ubuntu" ]]; then
    echo "[ERROR] This installer is for Ubuntu. Detected: ${PRETTY_NAME:-unknown}" >&2
    echo "        Arch-based systems should use install.sh." >&2
    exit 1
fi

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SRC="$REPO_DIR/.config"
CONFIG_DIR="$HOME/.config"
BACKUP_ROOT="$HOME/.config-backups"
TIMESTAMP="$(date '+%Y-%m-%d_%H-%M-%S')"
BACKUP_DIR="$BACKUP_ROOT/$TIMESTAMP"

# Written by theme.py at runtime. Copied once so configs that include them
# parse before the first `theme apply`. Never symlinked.
GENERATED_FILES=(
    "kitty/matugen.conf"
    "hypr/hyprlock-colors.conf"
    "gtk-3.0/colors.css"
    "gtk-4.0/colors.css"
    "gtk-3.0/settings.ini"
    "gtk-4.0/settings.ini"
    "rofi/colors.rasi"
    "quickshell/Theme.qml"
)

info()    { printf '\n\033[1;34m[INFO]\033[0m %s\n' "$1"; }
success() { printf '\n\033[1;32m[DONE]\033[0m %s\n' "$1"; }
warning() { printf '\n\033[1;33m[WARN]\033[0m %s\n' "$1"; }
error()   { printf '\n\033[1;31m[ERROR]\033[0m %s\n' "$1" >&2; }

# --------------------------------------------------
# Checks: the stack that build-stack.sh installs
# --------------------------------------------------

info "Checking required programs..."
MISSING=()
for c in Hyprland qs awww awww-daemon matugen python3; do
    command -v "$c" >/dev/null 2>&1 || MISSING+=("$c")
done
if [[ "${#MISSING[@]}" -gt 0 ]]; then
    error "Missing required programs: ${MISSING[*]}"
    error "Run build-stack.sh first (see ~/.local/share/43pr-install/)."
    exit 1
fi
for c in hyprlock kitty rofi thunar cliphist nm-applet; do
    command -v "$c" >/dev/null 2>&1 || warning "optional program not found: $c"
done

# --------------------------------------------------
# Link dotfiles (symlinked; the repo is the only copy)
# --------------------------------------------------

info "Linking dotfiles..."
mkdir -p "$CONFIG_DIR"

is_generated() {
    local rel="$1" g
    for g in "${GENERATED_FILES[@]}"; do
        [[ "$rel" == "$g" ]] && return 0
    done
    return 1
}

LINK_FAILED=0
LINKED_COUNT=0
BACKED_UP_COUNT=0

while IFS= read -r -d '' src; do
    rel="${src#"$SRC"/}"
    is_generated "$rel" && continue

    dest="$CONFIG_DIR/$rel"
    mkdir -p "$(dirname "$dest")"

    if [[ -L "$dest" ]]; then
        warning "repointing existing symlink ~/.config/$rel (was -> $(readlink "$dest"))"
        ln -sfn "$src" "$dest"
    elif [[ -e "$dest" ]]; then
        mkdir -p "$BACKUP_DIR/config/$(dirname "$rel")"
        mv "$dest" "$BACKUP_DIR/config/$rel"
        BACKED_UP_COUNT=$((BACKED_UP_COUNT + 1))
        ln -s "$src" "$dest"
    else
        ln -s "$src" "$dest"
    fi

    if [[ -L "$dest" && "$(readlink -f "$dest")" == "$(readlink -f "$src")" ]]; then
        LINKED_COUNT=$((LINKED_COUNT + 1))
    else
        LINK_FAILED=1
        error "Failed to link $rel"
    fi
done < <(find "$SRC" \( -type f -o -type l \) -not -path '*/.git/*' -print0)

# ~/.zshrc lives outside ~/.config
if [[ -f "$SRC/.zshrc" ]]; then
    if [[ -e "$HOME/.zshrc" && ! -L "$HOME/.zshrc" ]]; then
        mkdir -p "$BACKUP_DIR/home"
        mv "$HOME/.zshrc" "$BACKUP_DIR/home/.zshrc"
        BACKED_UP_COUNT=$((BACKED_UP_COUNT + 1))
    fi
    ln -sfn "$SRC/.zshrc" "$HOME/.zshrc"
    success "Linked ~/.zshrc."
fi

# Generated files: copy once, and only if absent (theme apply rewrites them)
for g in "${GENERATED_FILES[@]}"; do
    [[ -f "$SRC/$g" ]] || continue
    dest="$CONFIG_DIR/$g"
    if [[ ! -e "$dest" || -L "$dest" ]]; then
        [[ -L "$dest" ]] && rm -f "$dest"
        mkdir -p "$(dirname "$dest")"
        cp "$SRC/$g" "$dest"
    fi
done

if [[ "$LINK_FAILED" -eq 1 ]]; then
    error "One or more files failed to link. See errors above."
else
    success "Dotfiles linked ($LINKED_COUNT file(s))."
fi
if [[ "$BACKED_UP_COUNT" -gt 0 ]]; then
    info "Replaced $BACKED_UP_COUNT existing file(s); originals saved to: $BACKUP_DIR"
fi

# --------------------------------------------------
# Wallpaper directory and default wallpaper
# --------------------------------------------------

info "Creating user directories..."
WALLPAPER_DIR="$HOME/Pictures/Wallpapers"
DEFAULT_WALLPAPER_SRC="$REPO_DIR/wallhaven-k8jvm7.jpg"
DEFAULT_WALLPAPER_DEST="$WALLPAPER_DIR/wallhaven-k8jvm7.jpg"
mkdir -p "$HOME/Pictures" "$WALLPAPER_DIR"
# Copy, never overwrite, so the picker can rename or delete it
if [[ -f "$DEFAULT_WALLPAPER_SRC" && ! -e "$DEFAULT_WALLPAPER_DEST" ]]; then
    cp "$DEFAULT_WALLPAPER_SRC" "$DEFAULT_WALLPAPER_DEST"
fi
success "Pictures and Wallpapers directories ready."

# --------------------------------------------------
# User audio services (Ubuntu already runs PipeWire; this is idempotent)
# --------------------------------------------------

info "Enabling PipeWire user services..."
systemctl --user enable --now pipewire.service pipewire-pulse.service wireplumber.service \
    || warning "could not enable PipeWire user services"

# --------------------------------------------------
# power-profiles-daemon (system service; used by the Power page)
# --------------------------------------------------

if systemctl is-active --quiet power-profiles-daemon.service; then
    info "power-profiles-daemon already active."
else
    info "Enabling power-profiles-daemon (needs sudo)..."
    sudo systemctl enable --now power-profiles-daemon.service \
        || warning "could not enable power-profiles-daemon"
fi

# --------------------------------------------------
# hyprlock PAM service. The build installs pam/hyprlock under
# /usr/local/etc, which PAM does not read; PAM reads /etc/pam.d.
# Marker line lets revert.sh tell this file apart from anything else.
# --------------------------------------------------

PAM_MARKER="# managed by 43pr install-ubuntu.sh"
if [[ -f /etc/pam.d/hyprlock ]] && grep -qF "$PAM_MARKER" /etc/pam.d/hyprlock; then
    info "/etc/pam.d/hyprlock already present."
elif [[ -e /etc/pam.d/hyprlock ]]; then
    warning "/etc/pam.d/hyprlock exists and is not ours; leaving it alone"
else
    info "Installing /etc/pam.d/hyprlock (needs sudo)..."
    printf '%s\n# PAM configuration for hyprlock (same as upstream pam/hyprlock)\nauth        include     login\n' "$PAM_MARKER" \
        | sudo install -m 644 /dev/stdin /etc/pam.d/hyprlock \
        || warning "could not install /etc/pam.d/hyprlock (hyprlock will not unlock)"
fi

# --------------------------------------------------
# Default shell
# --------------------------------------------------

if [[ -x /bin/zsh ]]; then
    if [[ "$SHELL" != "/bin/zsh" ]]; then
        info "Setting zsh as the default login shell (needs sudo)..."
        if sudo chsh -s /bin/zsh "$USER"; then
            success "Default shell changed to zsh (takes effect at next login)."
        else
            warning "Failed to change the default shell to zsh."
        fi
    else
        info "zsh is already the default shell."
    fi
else
    warning "zsh is not installed; skipping default shell."
fi

# --------------------------------------------------
# Initial theme (generates the files the configs include)
# --------------------------------------------------

if [[ ! -f "$HOME/.local/state/43pr/state.json" ]] || ! grep -q '"wallpaper":' "$HOME/.local/state/43pr/state.json" 2>/dev/null; then
    info "Setting default wallpaper and generating colors..."
    python3 "$CONFIG_DIR/43pr/bin/theme.py" wallpaper "$DEFAULT_WALLPAPER_DEST" \
        || warning "Could not apply the default wallpaper."
else
    info "A wallpaper is already recorded; leaving it alone."
fi

info "Generating theme files..."
python3 "$CONFIG_DIR/43pr/bin/theme.py" apply \
    || warning "Initial theme generation failed."

# --------------------------------------------------
# Finish
# --------------------------------------------------

printf '\n\033[1;32m========================================\033[0m\n'
printf '\033[1;32m       43PR Hyprland Setup Ready       \033[0m\n'
printf '\033[1;32m========================================\033[0m\n\n'
printf 'Distribution:  %s\n' "${PRETTY_NAME:-unknown}"
printf 'Configuration: %s (symlinked to %s)\n' "$CONFIG_DIR" "$SRC"
[[ "$BACKED_UP_COUNT" -gt 0 ]] && printf 'Backup:        %s\n' "$BACKUP_DIR"
printf '\n'
warning "Log out and choose the Hyprland session to start the new setup."
