#!/usr/bin/env bash
set -e

PLUGIN_LINK="$HOME/.config/omarchy/plugins/dorneles.telestream"
CLI_TARGET="$HOME/.local/bin/telestream"

echo "Uninstalling TeleStream plugin from Omarchy..."

if [ -L "$PLUGIN_LINK" ] || [ -e "$PLUGIN_LINK" ]; then
    rm -f "$PLUGIN_LINK"
    echo "✓ Removed plugin symlink $PLUGIN_LINK"
fi

if [ -L "$CLI_TARGET" ] || [ -e "$CLI_TARGET" ]; then
    rm -f "$CLI_TARGET"
    echo "✓ Removed CLI command $CLI_TARGET"
fi

if command -v omarchy-shell > /dev/null 2>&1; then
    omarchy-shell shell rescanPlugins 2>/dev/null || true
fi

echo "TeleStream plugin uninstalled."
