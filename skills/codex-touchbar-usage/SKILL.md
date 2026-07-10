---
name: codex-touchbar-usage
description: Install, test, or troubleshoot the local native macOS Codex Touch Bar usage helper.
---

# Codex Touch Bar Usage

Use this skill when the user wants Codex usage shown on a MacBook Touch Bar, or asks to install,
test, modify, or troubleshoot the `codex-touchbar-usage` local plugin.

## Architecture

- The plugin installs a lightweight native macOS helper app at `~/Applications/CodexTouchBarHelper.app`.
- The helper uses an AppKit `NSTouchBar` system modal view and only presents it while Codex is frontmost.
- Frontmost app changes are event-driven through `NSWorkspace.didActivateApplicationNotification`.
- `CodexTouchBarCore` briefly invokes the installed Codex/ChatGPT app-server for official quota and account token usage, then exits it after each refresh.
- Quota balance and reset times come from `account/rateLimits/read`; yesterday/lifetime tokens come from `account/usage/read` so they match the profile page.
- Official app-server access uses the Codex CLI credentials in `~/.codex/auth.json`; local session `rate_limits` and incremental `last_token_usage` stats are fallback sources only.
- While Codex or the ChatGPT Codex shell is frontmost, official account data refreshes every 30 seconds. Local fallback data is checked between official refreshes but cannot replace valid account totals.
- Within an active quota window, stale percentages cannot replace newer usage; a lower percentage is accepted after the previous reset time passes or a materially later reset timestamp identifies a new cycle.
- Session fallback data cannot overwrite an existing official cache. Missing or expired CLI credentials are reported in the helper log instead of silently freezing without a diagnostic.
- `scripts/install_touchbar_helper.sh` builds the helper and registers a LaunchAgent.

## Common Commands

Build the helper app bundle:

```bash
./scripts/build_touchbar_helper.sh
```

Install and launch the native helper:

```bash
./scripts/install_touchbar_helper.sh
```

Start the installed helper manually:

```bash
./scripts/start_touchbar_helper.sh
```

Print one usage snapshot:

```bash
~/Applications/CodexTouchBarHelper.app/Contents/MacOS/CodexTouchBarHelper --once-json
```

Rebuild local token stats cache:

```bash
~/Applications/CodexTouchBarHelper.app/Contents/MacOS/CodexTouchBarHelper --rebuild-token-stats
```

Uninstall the helper:

```bash
./scripts/uninstall_touchbar_helper.sh
```

## Troubleshooting

- If the Touch Bar is blank, make sure Codex is the frontmost app and the helper is running:
  `pgrep -fl CodexTouchBarHelper`.
- If usage cannot be fetched, run `--once-json --no-remote`; it should use local session/cache data.
- If official quota data is stale, run `codex login status`; if needed, use `codex login --device-auth` to recreate `~/.codex/auth.json`.
- Logs are written to `~/.codex/touchbar-usage/helper.out.log` and `~/.codex/touchbar-usage/helper.err.log`.
- Do not print or log the contents of `~/.codex/auth.json`.
