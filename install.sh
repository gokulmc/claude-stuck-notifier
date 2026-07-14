#!/usr/bin/env bash
# claude-stuck-notifier installer
# Enables a macOS notification whenever any Claude Code window is waiting on you.
# Safe to re-run: it backs up settings.json and merges idempotently.
#
#   curl -fsSL https://raw.githubusercontent.com/gokulmc/claude-stuck-notifier/main/install.sh | bash
#
set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/gokulmc/claude-stuck-notifier/main"
CLAUDE_DIR="$HOME/.claude"
HOOK_DEST="$CLAUDE_DIR/hooks/notify-stuck.sh"
SETTINGS="$CLAUDE_DIR/settings.json"

# 1. Guards -----------------------------------------------------------------
if [ "$(uname)" != "Darwin" ]; then
  echo "claude-stuck-notifier is macOS-only (it uses osascript). Aborting." >&2
  exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required. Install it with:  brew install jq" >&2
  exit 1
fi
if ! command -v osascript >/dev/null 2>&1; then
  echo "osascript not found (expected on macOS). Aborting." >&2
  exit 1
fi

# 2. Install the hook script ------------------------------------------------
mkdir -p "$CLAUDE_DIR/hooks"
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || echo "")"
if [ -n "$SRC_DIR" ] && [ -f "$SRC_DIR/hooks/notify-stuck.sh" ]; then
  cp "$SRC_DIR/hooks/notify-stuck.sh" "$HOOK_DEST"          # local clone
else
  curl -fsSL "$REPO_RAW/hooks/notify-stuck.sh" -o "$HOOK_DEST"  # piped via curl
fi
chmod +x "$HOOK_DEST"

# 3. Ensure settings.json exists -------------------------------------------
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"

# 4. Back up before editing -------------------------------------------------
BACKUP="$SETTINGS.bak.$(date +%Y%m%d%H%M%S)"
cp "$SETTINGS" "$BACKUP"

# 5. Idempotent, non-destructive merge -------------------------------------
tmp="$(mktemp)"
jq --arg cmd "$HOOK_DEST" '
  .hooks //= {}
  | .hooks.Notification = ((.hooks.Notification // [])
      | if any(.[]?; (.hooks // [])[]?.command == $cmd) then .
        else . + [{matcher:"", hooks:[{type:"command", command:$cmd}]}] end)
  | .hooks.PreToolUse = ((.hooks.PreToolUse // [])
      | if any(.[]?; (.hooks // [])[]?.command == $cmd) then .
        else . + [{matcher:"AskUserQuestion", hooks:[{type:"command", command:$cmd}]}] end)
' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"

# 6. Done -------------------------------------------------------------------
echo "claude-stuck-notifier installed."
echo "  hook script : $HOOK_DEST"
echo "  settings    : $SETTINGS  (backup: $BACKUP)"
echo
echo "Reload any open Claude Code windows to pick up the new hooks."
echo "If no banner appears, enable notifications for your terminal / VS Code in"
echo "System Settings -> Notifications, and check Focus / Do Not Disturb is off."
