#!/bin/sh
# claude-stuck-notifier / Nudge
# Clears a project's "waiting" entry from the Nudge menu-bar app once the user
# has answered (wired to PostToolUse AskUserQuestion). No-op without Nudge, so
# it's harmless in a shell-only install.
[ -d /Applications/Nudge.app ] || exit 0

input=$(cat)
dir=$(printf '%s' "$input" | jq -r '.cwd // ""')
[ -z "$dir" ] && dir="$PWD"

open "nudge://clear?cwd=$(printf '%s' "$dir" | jq -sRr @uri)"
