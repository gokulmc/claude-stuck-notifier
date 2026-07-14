#!/usr/bin/env bash
# claude-stuck-notifier uninstaller
# Removes the notifier hooks from settings.json and deletes the hook script.
set -euo pipefail

CLAUDE_DIR="$HOME/.claude"
HOOK_DEST="$CLAUDE_DIR/hooks/notify-stuck.sh"
SETTINGS="$CLAUDE_DIR/settings.json"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required to safely edit settings.json. Install: brew install jq" >&2
  exit 1
fi

if [ -f "$SETTINGS" ]; then
  BACKUP="$SETTINGS.bak.$(date +%Y%m%d%H%M%S)"
  cp "$SETTINGS" "$BACKUP"
  tmp="$(mktemp)"
  # Strip our command from every event's matcher-groups, then drop groups whose
  # hooks list became empty, then drop events whose group list became empty.
  jq --arg cmd "$HOOK_DEST" '
    if .hooks then
      .hooks |= with_entries(
        .value |= ( map(.hooks |= map(select(.command != $cmd)))
                    | map(select((.hooks | length) > 0)) )
      )
      | .hooks |= with_entries(select((.value | length) > 0))
      | if (.hooks | length) == 0 then del(.hooks) else . end
    else . end
  ' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
  echo "Removed hooks from $SETTINGS (backup: $BACKUP)"
fi

rm -f "$HOOK_DEST"
echo "Deleted $HOOK_DEST"
echo "claude-stuck-notifier uninstalled. Reload open Claude Code windows."
