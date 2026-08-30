# Changelog

## Unreleased

### Fixed

- Installer now unregisters stale parent-app records before refreshing WidgetKit, preventing the widget gallery from falling back to the generic macOS application icon.
- Grid Conditions no longer lets a current Fingrid reading color future slots; green and red forecast periods now come only from the normalized renewable outlook.
- The renewable outlook now compares each forecast hour with the same Finland month and local hour in 2023–2025, then requires a matching top/bottom forecast-window quartile for at least one hour.
- Energy-Charts' final available 15-minute slot is no longer dropped from the renewable timeline.
- Build 116 forces WidgetKit to replace stale local extension code after the normalized Grid Conditions update.
- Build 117 coalesces simultaneous Fingrid requests and keeps a current cached CO₂ reading visible when a refresh is rate-limited.

## 1.0.1 - 2026-08-28

### Fixed

- Widget gallery provider name now uses **Finland Electricity Rates** instead of the internal Xcode target name.
- Product icon and bundle-name metadata are validated before packaging or installation.
- Installer removes stale widget registrations before registering the installed extension.

## 1.0.0 - 2026-08-28

### Added

- Free direct-distribution workflow with ad-hoc app signatures
- Universal disk-image packaging with SHA-256 verification and first-launch guidance
- Binary installer that no longer requires Xcode
- Privacy manifest, privacy notice, support guide, and release validation

### Changed

- Product version normalized to 1.0.0 with build 100
- Source-building installation retained as a separate developer fallback
- Optional Developer ID/notarization packaging retained for a future paid release path
