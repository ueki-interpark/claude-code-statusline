#!/bin/bash
# claude-code-statusline installer
# Copies statusline.sh to ~/.claude/ and configures settings.json

set -e

CLAUDE_DIR="$HOME/.claude"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_SCRIPT="$SCRIPT_DIR/statusline.sh"
DEST_SCRIPT="$CLAUDE_DIR/statusline.sh"

# Check for jq
if ! command -v jq &>/dev/null; then
  echo "Error: jq is required but not installed."
  echo "Install it with:"
  echo "  macOS:  brew install jq"
  echo "  Ubuntu: sudo apt install jq"
  echo "  Arch:   sudo pacman -S jq"
  exit 1
fi

# Check source file exists
if [ ! -f "$SOURCE_SCRIPT" ]; then
  echo "Error: statusline.sh not found at $SOURCE_SCRIPT"
  exit 1
fi

# Ensure ~/.claude directory exists
mkdir -p "$CLAUDE_DIR"

# Copy statusline.sh
cp "$SOURCE_SCRIPT" "$DEST_SCRIPT"
chmod +x "$DEST_SCRIPT"
echo "Copied statusline.sh to $DEST_SCRIPT"

# Update settings.json
if [ -f "$SETTINGS_FILE" ]; then
  # Backup existing settings
  cp "$SETTINGS_FILE" "$SETTINGS_FILE.bak"
  echo "Backed up settings.json to $SETTINGS_FILE.bak"

  # Add or update statusLine configuration
  jq '.statusLine = {"type": "command", "command": "~/.claude/statusline.sh"}' \
    "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp" && mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
else
  # Create new settings.json with statusLine config
  cat > "$SETTINGS_FILE" <<'EOF'
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline.sh"
  }
}
EOF
fi

echo "Updated $SETTINGS_FILE with statusLine configuration"
echo ""
echo "Installation complete! Restart Claude Code to see the status line."
