# claude-stuck-notifier

Get a macOS notification (banner + sound) whenever **any** Claude Code window is
waiting on you — a permission / tool-approval prompt, an `AskUserQuestion`
popup, or an idle/finished session sitting behind another window.

No more discovering, ten minutes later, that a Claude window was blocked the
whole time.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/gokulmc/claude-stuck-notifier/main/install.sh | bash
```

Then **reload any open Claude Code windows** so they pick up the new hooks.

Requirements: **macOS** (uses `osascript`) and **`jq`** (`brew install jq`).

## What it does

The installer:

1. Drops a small hook script at `~/.claude/hooks/notify-stuck.sh`.
2. Backs up `~/.claude/settings.json` (to `settings.json.bak.<timestamp>`).
3. Merges two hooks into your settings — **idempotently and
   non-destructively**, so your existing `permissions`, `model`, and any other
   hooks are left untouched. Re-running the installer never creates duplicates.

The two hooks:

| Hook | Matcher | Fires when |
|------|---------|-----------|
| `Notification` | *(any)* | Claude needs permission, or is idle/finished and waiting for you |
| `PreToolUse` | `AskUserQuestion` | Claude opens a question popup |

For a question popup, the banner shows the **actual question text**. For a
permission prompt it shows Claude's message. The banner subtitle is the project
folder, so you can tell *which* window is blocked.

The hooks are **notify-only** — they never block or change what Claude does.

## Uninstall

```bash
bash uninstall.sh
```

(or clone the repo and run it). It backs up settings, removes only this tool's
hooks, and deletes the hook script.

## Troubleshooting

- **No banner?** Enable notifications for the delivering app (your terminal /
  VS Code / Script Editor) in **System Settings → Notifications**, and make sure
  **Focus / Do Not Disturb** isn't suppressing them. macOS can also suppress a
  banner attributed to the app that is currently frontmost.
- **Want it clickable (jump straight to the window)?** Install
  [`terminal-notifier`](https://github.com/julienXX/terminal-notifier)
  (`brew install terminal-notifier`) and swap the `osascript` line in
  `~/.claude/hooks/notify-stuck.sh` for a `terminal-notifier … -activate` call —
  more reliable delivery and clickable-to-focus.

## How it works

Claude Code fires [hook events](https://code.claude.com/docs/en/hooks) at
lifecycle points and passes JSON on stdin. `notify-stuck.sh` reads that JSON,
extracts the message / question and the working directory with `jq`, and calls
`osascript -e 'display notification …'`.

macOS-only for now; Linux (`notify-send`) support could be added behind a
`uname` branch.
