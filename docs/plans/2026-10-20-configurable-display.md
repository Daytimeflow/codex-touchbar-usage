# Configurable Codex display

Goal: Let users select the primary quota, weekly quota, reset cards, yesterday tokens and total tokens without rebuilding the helper.

Architecture: A dependency-free JSON configuration in CODEX_HOME/touchbar-usage/config.json feeds typed display settings. The existing 720 x 30 AppKit view packs enabled quota rows into columns of at most two rows and reserves a token column only when needed. Defaults preserve the existing primary/reset-card/token layout. Weekly selection checks the actual 10080-minute duration, since secondary can contain a model-specific quota instead.

Implementation and validation:
1. Add strict configuration decoding, defaults and a diagnostic CLI command. Test missing, partial, invalid and changed configuration files.
2. Add a typed display-row projection and dynamic geometry. Test all 32 switch combinations and absent/reordered weekly windows.
3. Reload on foreground activation and local refresh; retain the last valid settings on malformed edits and log a deduplicated diagnostic.
4. Extend the native AppKit harness with weekly-only, quota-only, all-enabled, tokens-only and empty presets; inspect rendered PNGs and verify bounds.
5. Document configuration in both READMEs; build the complete helper, run available test suites, review the diff, commit and open an upstream PR.

The configuration changes presentation only. It does not alter quota fetching, authorization, token accounting, polling or the ZCode panel.
