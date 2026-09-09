#!/usr/bin/env bash
set -e

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$HOME/.local/bin"
CLI_TARGET="$BIN_DIR/telestream"
OMARCHY_PLUGINS_DIR="$HOME/.config/omarchy/plugins"
PLUGIN_LINK="$OMARCHY_PLUGINS_DIR/dorneles.telestream"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🚀 Installing TeleStream plugin for Omarchy..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 1. Ensure executable permissions
chmod +x "$PLUGIN_DIR/scripts/streamer_cli.py"
chmod +x "$PLUGIN_DIR/scripts/file_picker.py"

# 2. Create directories with restrictive permissions
mkdir -p "$BIN_DIR"
mkdir -p "$OMARCHY_PLUGINS_DIR"
STATE_DIR="$HOME/.local/state/omarchy/telestream"
mkdir -p -m 700 "$STATE_DIR"
chmod 700 "$STATE_DIR" 2>/dev/null || true
CONFIG_DIR="$HOME/.config/telestream"
mkdir -p -m 700 "$CONFIG_DIR"
chmod 700 "$CONFIG_DIR" 2>/dev/null || true

if [ -f "$CONFIG_DIR/config.json" ]; then
    chmod 600 "$CONFIG_DIR/config.json" 2>/dev/null || true
fi
if [ -f "$STATE_DIR/state.json" ]; then
    chmod 600 "$STATE_DIR/state.json" 2>/dev/null || true
fi
if [ -f "$STATE_DIR/telestream.log" ]; then
    chmod 600 "$STATE_DIR/telestream.log" 2>/dev/null || true
fi

# 3. Create symlink in Omarchy plugins directory
if [ -L "$PLUGIN_LINK" ] || [ -e "$PLUGIN_LINK" ]; then
    rm -f "$PLUGIN_LINK"
fi
ln -sf "$PLUGIN_DIR" "$PLUGIN_LINK"
echo "✓ Plugin linked to $PLUGIN_LINK"

# 4. Create global symlink for CLI command
ln -sf "$PLUGIN_DIR/scripts/streamer_cli.py" "$CLI_TARGET"
echo "✓ CLI command linked to $CLI_TARGET"

# 5. Notify Omarchy Shell to discover plugin
export OMARCHY_PATH="${OMARCHY_PATH:-/usr/share/omarchy}"
if [[ -z "${WAYLAND_DISPLAY:-}" ]]; then
    socket=$(ls -t "${XDG_RUNTIME_DIR:-/run/user/$UID}"/wayland-[0-9]* 2>/dev/null | grep -v '\.lock$' | head -n1)
    [[ -n $socket ]] && export WAYLAND_DISPLAY=${socket##*/}
fi

if command -v omarchy-shell > /dev/null 2>&1; then
    echo "✓ Rescanning Omarchy Shell plugins..."
    omarchy-shell shell rescanPlugins 2>/dev/null || true
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✨ Installation completed successfully!"
echo "• To enable and add the widget to your Omarchy bar:"
echo "  omarchy plugin enable dorneles.telestream"
echo "  omarchy bar move dorneles.telestream --section right"
echo "• To use the CLI:"
echo "  telestream --help"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
