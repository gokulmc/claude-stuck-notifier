#!/bin/sh
# claude-stuck-notifier
# Fires a macOS banner (+ sound) when a Claude Code window is waiting on you.
# Invoked by Claude Code hooks with the event JSON on stdin.
#
#   Notification event  -> shows .message  (permission prompts, idle/finished)
#   PreToolUse AskUserQuestion -> shows the question text from .tool_input
#
# Everything degrades to a generic line if a field is missing, so it never
# errors out of the hook.

input=$(cat)

tool=$(printf '%s' "$input" | jq -r '.tool_name // ""')
msg=$(printf '%s' "$input" | jq -r '.message // ""')
dir=$(printf '%s' "$input" | jq -r '.cwd // ""')
[ -z "$dir" ] && dir="$PWD"
proj=$(basename "$dir")

if [ -z "$msg" ]; then
  if [ "$tool" = "AskUserQuestion" ]; then
    msg=$(printf '%s' "$input" | jq -r '.tool_input.questions[0].question // "Waiting for your answer"')
  else
    msg="Needs your attention"
  fi
fi

# Prefer the Nudge menu-bar app when installed: clickable banner that focuses the
# waiting VS Code window. Otherwise fall back to a plain osascript banner so the
# zero-dependency shell install still works everywhere.
if [ -d "/Applications/Nudge.app" ]; then
  enc() { printf '%s' "$1" | jq -sRr @uri; }
  open "nudge://notify?title=Claude%20Code&subtitle=$(enc "$proj")&message=$(enc "$msg")&cwd=$(enc "$dir")"
else
  # Truncate for a readable banner, collapse newlines, escape \ and " for AppleScript.
  esc=$(printf '%.140s' "$msg" | tr '\n' ' ' | sed 's/\\/\\\\/g; s/"/\\"/g')
  osascript -e "display notification \"$esc\" with title \"Claude Code\" subtitle \"$proj\" sound name \"Ping\""
fi
