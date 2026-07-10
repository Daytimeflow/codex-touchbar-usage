# Changelog

All notable changes to Codex Touch Bar Usage are documented here.

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

[0.3.2]: https://github.com/Daytimeflow/codex-touchbar-usage/releases/tag/v0.3.2
[0.3.1]: https://github.com/Daytimeflow/codex-touchbar-usage/releases/tag/v0.3.1
[0.3.0]: https://github.com/Daytimeflow/codex-touchbar-usage/releases/tag/v0.3.0
