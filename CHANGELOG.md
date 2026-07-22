# Changelog

All notable changes to Codex Touch Bar Usage are documented here.

## [0.3.6] - 2026-07-22

### Added

- Show the available Codex rate-limit reset-card count and earliest expiration on the second Touch Bar row.
- Parse reset-card details from the existing app-server rate-limit response without adding a request on the normal refresh path.
- Use the authenticated `wham/rate-limit-reset-credits` endpoint as a fallback when app-server access is unavailable.

### Changed

- Replace the low-value Spark quota row with compact reset-card ticket indicators, count, and expiration time.
- Cache only the reset-card count and earliest expiration; card IDs and descriptions are discarded.
- Detect reset-card consumption and temporarily refresh official quota about every 8 seconds for up to 3 minutes, stopping when the new quota cycle propagates.

### Fixed

- Accept genuine weekly quota resets whose reset timestamp moves forward by less than one quarter of the full window.
- Give the official app-server enough time to return current rate limits on slower refreshes.
- Prevent overlapping official refresh tasks during reset-card follow-up polling.
- Pin direct Swift builds to the documented macOS 12 deployment target.

## [0.3.5] - 2026-07-13

### Fixed

- Parse the new `rateLimitsByLimitId` and `additional_rate_limits` response shapes.
- Adapt Touch Bar row labels to current main and model-specific windows, including `1周 / Spark`, while preserving legacy `5小时 / 1周` support.
- Accept quota-window identity changes without retaining percentages from a removed window.
- Stop forcing `account/read` token refreshes on every poll, avoiding refresh-token races with Codex Desktop.

## [0.3.4] - 2026-07-11

### Fixed

- Accept a lower quota percentage when a materially later reset timestamp identifies a new quota cycle, even if the previously cached reset time has not passed yet.
- Preserve the last official cache when authenticated refreshes fall back to local session data.
- Report app-server authentication failures instead of silently ignoring session fallback refreshes.

## [0.3.3] - 2026-07-10

### Fixed

- Allow the latest official future reset time to correct an active quota window without allowing the used percentage to regress.
- Format reset times with the Mac's automatically updating local time zone and a fixed Gregorian calendar.

## [0.3.2] - 2026-07-10

### Fixed

- Prevent the installer from racing LaunchAgent startup and leaving two helper processes running.
- Switch the Homebrew Tap package to a prebuilt Cask so installation does not require a current Swift/Xcode toolchain.

## [0.3.1] - 2026-07-10

### Fixed

- Prevent quota percentages and reset times from jumping back to an older snapshot within the same active window.
- Preserve official cache provenance so startup data participates in the same quota-stability checks.
- Accept lower usage normally after the previous quota window has actually expired.

## [0.3.0] - 2026-07-10

### Added

- Official Codex account token totals from `account/usage/read`, matching the profile page.
- Compatibility with the latest Codex / ChatGPT desktop app-server discovery flow.
- Apple Silicon release packaging with an ad-hoc signed app, installer, uninstaller, and SHA-256 checksum.
- Homebrew Tap installation support.
- Bilingual Chinese / English documentation and an animated README demo.

### Changed

- Official quota and token data refresh every 30 seconds while Codex is frontmost.
- Local JSONL token totals remain fallback-only and no longer replace official account totals.
- All-zero and stale snapshots are rejected before they can replace valid quota data.

[0.3.6]: https://github.com/Daytimeflow/codex-touchbar-usage/releases/tag/v0.3.6
[0.3.5]: https://github.com/Daytimeflow/codex-touchbar-usage/releases/tag/v0.3.5
[0.3.4]: https://github.com/Daytimeflow/codex-touchbar-usage/releases/tag/v0.3.4
[0.3.3]: https://github.com/Daytimeflow/codex-touchbar-usage/releases/tag/v0.3.3
[0.3.2]: https://github.com/Daytimeflow/codex-touchbar-usage/releases/tag/v0.3.2
[0.3.1]: https://github.com/Daytimeflow/codex-touchbar-usage/releases/tag/v0.3.1
[0.3.0]: https://github.com/Daytimeflow/codex-touchbar-usage/releases/tag/v0.3.0
