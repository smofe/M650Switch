#!/bin/sh
# Installs (or updates) the latest M650Switch release into ~/Applications.
#   curl -fsSL https://raw.githubusercontent.com/smofe/M650Switch/main/install.sh | sh
set -eu

URL="https://github.com/smofe/M650Switch/releases/latest/download/M650Switch.zip"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "Downloading M650Switch…"
curl -fsSL "$URL" -o "$TMP/M650Switch.zip"

pkill -x M650Switch 2>/dev/null && sleep 1 || true
mkdir -p "$HOME/Applications"
rm -rf "$HOME/Applications/M650Switch.app"
ditto -x -k "$TMP/M650Switch.zip" "$HOME/Applications"

echo "Installed to ~/Applications/M650Switch.app — starting it."
open "$HOME/Applications/M650Switch.app"
