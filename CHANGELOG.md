# Changelog

All notable changes to Codex Touch Bar Usage are documented here.

## [0.3.0] - 2026-07-10

### Added

- Official Codex account token totals from `account/usage/read`, matching the profile page.
- Compatibility with the latest Codex / ChatGPT desktop app-server discovery flow.
- Apple Silicon release packaging with an ad-hoc signed app, installer, uninstaller, and SHA-256 checksum.
- Homebrew Tap installation and `brew services` login startup support.
- Bilingual Chinese / English documentation and an animated README demo.

### Changed

- Official quota and token data refresh every 30 seconds while Codex is frontmost.
- Local JSONL token totals remain fallback-only and no longer replace official account totals.
- All-zero and stale snapshots are rejected before they can replace valid quota data.

[0.3.0]: https://github.com/Daytimeflow/codex-touchbar-usage/releases/tag/v0.3.0
