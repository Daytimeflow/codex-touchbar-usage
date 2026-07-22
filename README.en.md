<div align="center">
  <img src="assets/logo.svg" width="112" alt="Codex Touch Bar Usage logo">
  <h1>Codex Touch Bar Usage</h1>
  <p>
    A native MacBook Pro Touch Bar usage plugin built for Codex.
  </p>
  <p>
    Put Codex quota, reset cards, reset times, and token usage directly on your Touch Bar.
  </p>
</div>

<p align="center">
  <a href="README.md">简体中文</a> · <strong>English</strong>
</p>

<div align="center">

[![License: MIT](https://img.shields.io/badge/license-MIT-111?style=flat-square)](LICENSE)
[![Release](https://img.shields.io/github/v/release/Daytimeflow/codex-touchbar-usage?style=flat-square&color=8DFF55)](https://github.com/Daytimeflow/codex-touchbar-usage/releases/latest)
[![macOS](https://img.shields.io/badge/macOS-Touch%20Bar-111?style=flat-square&logo=apple)](#requirements)
[![Swift](https://img.shields.io/badge/Swift-native%20AppKit-F05138?style=flat-square&logo=swift&logoColor=white)](helper/CodexTouchBarHelper)
[![Codex](https://img.shields.io/badge/Codex-Touch%20Bar%20Plugin-8DFF55?style=flat-square)](#features)
[![Homebrew](https://img.shields.io/badge/Homebrew-tap-FBB040?style=flat-square&logo=homebrew&logoColor=111)](#installation)

</div>

![Codex Touch Bar Usage animated demo](assets/demo.gif)

<p align="center"><sub>Quota, reset cards, and token usage appear when Codex is focused; system controls return when you switch away.</sub></p>

## Overview

**Codex Touch Bar Usage** is a native Touch Bar plugin built specifically for frequent Codex users. It puts the usage information you keep checking directly above your keyboard.

When Codex is the frontmost app, the helper temporarily presents a compact usage panel on the Touch Bar. When you switch away, it hides automatically and the system Control Strip, including brightness and volume controls, comes back.

It is not Electron, not a WebView, and not a fragile pile of separate Touch Bar items. The UI is a single native AppKit-drawn `NSTouchBar` custom view, which keeps layout stable, refreshes lightly, and responds quickly.

## Features

| Module | What it shows |
| --- | --- |
| Identity | White italic `Codex` title |
| Main quota | Automatically detects the official window duration and shows balance capsules, remaining amount, and reset time |
| Reset cards | Shows the available count and earliest expiration so earned resets do not expire unnoticed |
| Token usage | Yesterday's tokens and lifetime tokens, formatted in `万` / `亿` units |
| Frontmost app awareness | Shows only when Codex is focused, hides when you switch away |
| Lightweight refresh | Normally refreshes about every 30 seconds; after a reset card is used, follows up about every 8 seconds for up to 3 minutes; stops while hidden |

## Why This Project

| Design priority | Codex Touch Bar Usage |
| --- | --- |
| Codex-first | Built around official main quota, reset cards, reset times, and yesterday / lifetime tokens instead of a generic dashboard |
| Official account totals | Prefers the official Codex app-server data, matching the token totals shown on the profile page |
| Focus-aware | Appears only while Codex / ChatGPT is frontmost, then restores brightness, volume, and other system controls |
| Native and lightweight | One Swift + AppKit custom view with no Electron / WebView; app focus is event-driven and refresh stops while hidden |
| Complete at a glance | Partial-fill balance capsules plus remaining percentages, reset-card count, earliest expiration, and account token totals |

## Who Is This For

- People who use Codex, Codex CLI, or Codex Desktop for long sessions every day;
- People who want to know how much main Codex quota remains and whether a reset card is close to expiring;
- People who want yesterday and lifetime token usage without opening the profile page repeatedly;
- People with a Touch Bar MacBook Pro who want that strip to be useful again.

Keywords: `Codex Touch Bar`, `Codex usage`, `Codex token tracker`, `Codex quota`, `MacBook Pro Touch Bar plugin`.

## Requirements

- MacBook Pro with Touch Bar
- macOS 12 or later
- The latest Codex / ChatGPT desktop app installed (the new shell still hosts Codex services)
- Signed in to Codex, with `~/.codex/auth.json` available locally
- Homebrew / GitHub Release installs do not require Swift; source installation requires full Xcode or Command Line Tools

> Note: this project uses macOS private system-modal Touch Bar capabilities. It is intended for local personal use and open-source learning, not App Store distribution.

## Installation

### Homebrew (recommended)

```bash
brew install --cask daytimeflow/tap/codex-touchbar-usage
```

The cask installs the helper, registers its LaunchAgent, and starts it immediately. No separate `brew services start` command is needed.

Upgrade:

```bash
brew update
brew upgrade --cask codex-touchbar-usage
```

### GitHub Release (Apple Silicon)

Download `CodexTouchBarUsage-v0.3.6-arm64.zip` and its `.sha256` file from [Releases](https://github.com/Daytimeflow/codex-touchbar-usage/releases/latest):

```bash
shasum -a 256 -c CodexTouchBarUsage-v0.3.6-arm64.zip.sha256
unzip CodexTouchBarUsage-v0.3.6-arm64.zip
cd CodexTouchBarUsage-v0.3.6-arm64
./install.sh
```

The prebuilt app is ad-hoc signed and not yet Apple-notarized. Verify its SHA-256 first. If Gatekeeper blocks it, open System Settings → Privacy & Security, approve **Open Anyway**, then start the helper again. You can also install from source to compile it locally.

### Install from source

```bash
git clone https://github.com/Daytimeflow/codex-touchbar-usage.git
cd codex-touchbar-usage
./scripts/install_touchbar_helper.sh
```

The installer will:

- build the native Swift helper;
- install it to `~/Applications/CodexTouchBarHelper.app`;
- register a LaunchAgent at `~/Library/LaunchAgents/com.local.codex-touchbar-helper.plist`;
- enable login startup;
- start the background helper.

Open Codex and focus its window. The Touch Bar usage panel should appear.

## Manual Start

If you do not see the Touch Bar panel after a reboot, start it manually once:

```bash
./scripts/start_touchbar_helper.sh
```

Check status:

```bash
launchctl print-disabled gui/$(id -u) | grep com.local.codex-touchbar-helper
launchctl print gui/$(id -u)/com.local.codex-touchbar-helper
```

Expected output includes:

```text
com.local.codex-touchbar-helper => enabled
state = running
```

## Update

Homebrew installation:

```bash
brew update
brew upgrade --cask codex-touchbar-usage
```

Source installation:

```bash
git pull
./scripts/install_touchbar_helper.sh
```

## Uninstall

Homebrew installation:

```bash
brew uninstall --cask codex-touchbar-usage
```

Release installation (from the extracted folder):

```bash
./uninstall.sh
```

Source installation (from the repository):

```bash
./scripts/uninstall_touchbar_helper.sh
```

It removes:

- `~/Applications/CodexTouchBarHelper.app`
- `~/Library/LaunchAgents/com.local.codex-touchbar-helper.plist`
- the running `CodexTouchBarHelper` process

It does not delete your Codex login information and does not remove `~/.codex`.

## Data Sources

| Data | Source |
| --- | --- |
| Quota balance / reset times | Official Codex app-server `account/rateLimits/read` |
| Reset cards | Details returned by the same `account/rateLimits/read`; falls back to `wham/rate-limit-reset-credits` when app-server access is unavailable |
| Yesterday / lifetime tokens | Official Codex app-server `account/usage/read`, matching the profile page |
| Local fallback | Codex session JSONL and usage cache, used only when official data is unavailable |
| Cache | `~/.codex/touchbar-usage/` |

Privacy principles:

- local session contents are not uploaded;
- access tokens are not logged or printed;
- only reset-card count and earliest expiration are cached; card IDs and descriptions are discarded;
- when the helper is hidden, it does not refresh UI or make network requests;
- app-server starts only briefly for an official data refresh and exits immediately afterward; it is not an additional resident process.

## Refresh Behavior

- When Codex becomes frontmost, the helper immediately requests official data, then refreshes about every 30 seconds;
- when the reset-card count decreases, it temporarily follows the new quota cycle about every 8 seconds for up to 3 minutes;
- the upstream service may update the card count before the quota. The helper never fabricates `100%`; it refreshes as soon as the new cycle is actually returned;
- at most one official request runs at a time, and all timers and network refreshes pause when Codex is not frontmost.

## Useful Commands

Print one current snapshot:

```bash
~/Applications/CodexTouchBarHelper.app/Contents/MacOS/CodexTouchBarHelper --once-json
```

Use only local cache/session data:

```bash
~/Applications/CodexTouchBarHelper.app/Contents/MacOS/CodexTouchBarHelper --once-json --no-remote
```

Rebuild the local token stats cache:

```bash
~/Applications/CodexTouchBarHelper.app/Contents/MacOS/CodexTouchBarHelper --rebuild-token-stats
```

View logs:

```bash
tail -f ~/.codex/touchbar-usage/helper.err.log
tail -f ~/.codex/touchbar-usage/helper.out.log
```

If quota data stops updating, check the Codex CLI login first. A desktop app upgrade may require one new authorization:

```bash
codex login status
codex login --device-auth
```

The helper does not read or copy private desktop-app credentials. It only uses credentials stored locally by the official Codex CLI. After signing in again, use the `--once-json` command at the start of this section to print an official snapshot and compare it with the Touch Bar value.

## FAQ

### Is this an official Codex plugin?

No. This is a community/personal Codex Touch Bar usage plugin built for local workflows. It does not claim to be official and does not use OpenAI or Codex trademarks as official endorsement.

### The Touch Bar is not lighting up

First confirm the system Touch Bar itself works. If brightness and volume controls are also missing, the macOS Touch Bar service may be stuck. Try:

```bash
killall ControlStrip
```

If it is still black, you may need to restart the system TouchBarServer:

```bash
sudo pkill TouchBarServer
```

### The helper is running, but the Codex panel does not appear

Make sure Codex is the frontmost app:

```bash
launchctl print gui/$(id -u)/com.local.codex-touchbar-helper
```

The LaunchAgent matches the following targets by default:

```text
Codex,ChatGPT,com.openai.codex
```

If you use a renamed Codex app, edit `CODEX_TOUCHBAR_TARGET_APPS` in the LaunchAgent.

### How much storage does it use, and should I clean it periodically?

The helper stores only small caches and diagnostic logs in `~/.codex/touchbar-usage/`, normally measured in MB. The installer rotates helper logs larger than 2 MB. `~/.codex/sessions/` is Codex task history, not plugin data; deleting it affects historical tasks and context recovery, so do not remove it merely to clean up this plugin.

Check their sizes separately:

```bash
du -sh ~/.codex/touchbar-usage ~/.codex/sessions
```

### Why does token usage not update character by character?

The right-side values use the official account totals shown on the Codex profile page and refresh about every 30 seconds. The upstream profile data may update in batches, so it does not change with every generated character; local JSONL increments are only a fallback when official account usage is unavailable.

### Why does quota not change immediately after I use a reset card?

The upstream service may deduct the card first and switch the quota cycle asynchronously. When the card count drops, the helper enters a follow-up mode for up to 3 minutes; once the official endpoint returns the new quota, it normally appears within about 8 seconds. If it is still unchanged after 3 minutes, use the `--once-json` command above to confirm whether the official data has propagated.

## Development

Build:

```bash
./scripts/build_touchbar_helper.sh
```

Test:

```bash
cd helper/CodexTouchBarHelper
swift test
```

If the machine only has Command Line Tools and SwiftPM is unavailable, the build script automatically falls back to direct `swiftc` compilation.

## Roadmap

- [x] Publish a prebuilt Apple Silicon `.app` Release
- [x] Support one-line installation through a Homebrew Tap
- [ ] Add a menu bar status entry
- [ ] Add configurable refresh intervals
- [ ] Add more token breakdowns for Codex surfaces

## Disclaimer

This is an unofficial Codex Touch Bar plugin. It is not affiliated with, authorized by, or endorsed by OpenAI or Codex. Codex internal endpoints, session JSONL structures, and macOS system-modal Touch Bar APIs may change across app or system versions. Use it at your own discretion.

## Support

If this little tool saves you a few profile-page checks, a Star is appreciated. Sponsorship is also welcome.

| Alipay | WeChat |
| --- | --- |
| <img src="assets/sponsor/alipay.jpeg" alt="Alipay QR code" width="220"> | <img src="assets/sponsor/wechat.jpeg" alt="WeChat Pay QR code" width="220"> |
