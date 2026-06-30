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
- `CodexTouchBarCore` reads `~/.codex/auth.json`, calls the Codex usage endpoint for quota balance and reset times, and falls back to the newest local session `rate_limits` event.
- Right-side yesterday/cumulative rows use local Codex session `last_token_usage` token amounts, incrementally cached in `~/.codex/touchbar-usage/token-stats-cache.json`.
- While Codex is frontmost, the helper refreshes local session data every 3 seconds and remote quota data every 30 seconds.
- `scripts/install_touchbar_helper.sh` builds the helper and registers a LaunchAgent. It only backs up/removes MTMR when run with `REMOVE_MTMR=1`.

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
  `pgrep -x CodexTouchBarHelper`.
- If usage cannot be fetched, run `--once-json --no-remote`; it should use local session/cache data.
- Logs are written to `~/.codex/touchbar-usage/helper.out.log` and `~/.codex/touchbar-usage/helper.err.log`.
- Do not print or log the contents of `~/.codex/auth.json`.
