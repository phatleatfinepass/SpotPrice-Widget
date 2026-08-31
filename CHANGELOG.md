# Changelog

## 1.2.0 - 2026-08-31

### Added

- The macOS host app now checks the official GitHub release for updates, verifies the disk-image SHA-256 checksum, and opens the verified installer.
- A confirmed Danger Zone can reset rebuildable app data or move the exact running app to the Trash through a narrowly scoped embedded XPC service.

### Changed

- Direct builds keep host and widget fallback caches in their own sandboxes. Reset clears the host cache and asks WidgetKit to replace extension caches with fresh timelines.
- The app and widget remain sandboxed. The uninstall service runs outside the sandbox, accepts no filesystem path, validates the caller’s user, signing identifier, and exact containing-app path, and can recycle only its containing app.

### Fixed

- Uninstall no longer falls back to Finder or requires the user to locate and delete the app manually.
- The XPC client retains each request until its reply arrives, preventing a suspended uninstall task.
- Ad-hoc direct builds no longer declare an App Group that macOS denies at runtime.

## 1.1.0 - 2026-08-31

### Added

- Public Release builds now obtain live Fingrid dataset 396 emissions through a fixed, read-only Cloudflare Worker cache; customers no longer need an API key.
- The relay refreshes every five minutes, retains the last valid response during upstream failures, and recalculates its 30-day emissions thresholds daily.

### Security

- Fingrid primary and secondary credentials are encrypted provider secrets and are never embedded in the app, installer, repository, logs, or public response.
- Release packaging rejects missing relay configuration, rejects embedded Fingrid credentials, and verifies a live dataset 396 payload before creating the disk image.
- Credential-bearing provider requests reject redirects, public reads use edge caching before KV, and the health route consumes no metered storage reads.
- Release packaging runs with read-only GitHub permission and no persisted checkout credential; only the isolated artifact-publishing job receives write permission.
- Local Debug-key injection removes the credential from build/download subprocess environments and command arguments, and does not retain credential-bearing rollback bundles.

### Fixed

- Installer now unregisters stale parent-app records before refreshing WidgetKit, preventing the widget gallery from falling back to the generic macOS application icon.
- Grid Conditions no longer lets a current Fingrid reading color future slots; green and red forecast periods now come only from the normalized renewable outlook.
- The renewable outlook now compares each forecast hour with the same Finland month and local hour in 2023–2025, then requires a matching top/bottom forecast-window quartile for at least one hour.
- Energy-Charts' final available 15-minute slot is no longer dropped from the renewable timeline.
- Build 116 forces WidgetKit to replace stale local extension code after the normalized Grid Conditions update.
- Build 117 coalesces simultaneous Fingrid requests and keeps a current cached CO₂ reading visible when a refresh is rate-limited.
- Build 118 routes public emissions through the secure relay while preserving direct Fingrid access only for local Debug builds.
- The relay now decodes Fingrid dataset 396's production one-row-per-period field instead of rejecting valid measurements as unavailable.

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
