# Changelog

## 1.2.8 - 2026-09-01

### Changed

- Aligned Check for Updates, Reset, and Uninstall as three equal-width horizontal actions with matching heights, corner geometry, and baselines.
- Simplified the maintenance labels to **Reset** and **Uninstall**, removed the idle signed-update helper, and retained clear supporting descriptions beneath the controls.

### Fixed

- Automatic updates now stop only the exact resident widget-extension process before replacing the app, preventing WidgetKit from continuing to execute pre-update code from memory.
- The replacement app uses a delayed, retryable startup handoff to the new maintenance helper, re-registers the embedded extension, and reloads every timeline. This also repairs upgrades initiated by the older 1.2.7 helper.
- Failed replacement preparation restores the existing widget registration without targeting Debug builds or other app copies.

### Verified

- Exact-process lifecycle tests prove that the embedded widget is stopped while a same-named executable outside the target app remains running.
- Product validation, update handoff, signed Debug compilation, widget-registration integration, and live timeline refresh checks cover this release.

## 1.2.7 - 2026-09-01

### Changed

- Redesigned App Management as one horizontal surface with a balanced 50/50 split between Software Update and App Controls.
- Placed Reset Data and Uninstall side by side without the previous nested danger-zone shell, using only a subtle internal divider.
- Adopted native SwiftUI material, SF Symbols, standard bordered controls, and the system destructive role for uninstall.
- Prevented update, reset, and uninstall operations from starting while another maintenance action is in progress.

### Verified

- macOS Debug compilation, product metadata, maintenance logic, updater handoff, update-version logic, and uninstall target tests cover this release.

## 1.2.6 - 2026-09-01

### Fixed

- Grid Conditions now keeps renewable-slot transitions and live-emissions expiry as separate timeline events, preventing a 15-minute forecast boundary from marking a still-current CO₂ measurement unavailable.
- An expired cached CO₂ value is labeled **Last reading**; **Data unavailable** is reserved for a genuinely missing measurement.

### Verified

- Grid Conditions signal tests reproduce the forecast-boundary-before-emissions-expiry case, and macOS Debug plus Universal Release builds compile the corrected WidgetKit timeline.

## 1.2.5 - 2026-09-01

### Fixed

- Automatic updates now wait for the authenticated host process to exit before replacing and relaunching the app, preventing the old and new versions from appearing at the same time.
- The updater explicitly refreshes Launch Services and WidgetKit registration for the replacement bundle, verifies the installed extension path, and restores the previous app and widget registration if relaunch fails.

### Verified

- CI and release validation now cover the host-exit handoff, its timeout behavior, PluginKit path parsing, and the required prepare → quit → replace → register → relaunch ordering.

## 1.2.4 - 2026-09-01

### Added

- Added a full native dashboard to the macOS app with live price and emissions summaries, a proportional daily price-range gauge, Today/Tomorrow prices, hourly recommendations, source timestamps, and a combined best-use window.
- Added Apple Charts views for hourly electricity prices, the next 24 hours of renewable share, and the past 24 hours of grid-emissions history when direct historical data is available.

### Changed

- Reworked Grid Conditions into two clearly labeled, fixed-size Forecast and History views instead of overlaying unrelated units on one normalized chart.
- Normalized the two analytical cards, segmented controls, chart plot padding, and axis-label widths so loading, selection, and data changes no longer resize the dashboard.
- The host app now resolves the public grid-emissions relay from its bundled widget extension, keeping the live Fingrid value available in the app as well as the widget.

### Fixed

- Today and Tomorrow no longer substitute for one another; unpublished tomorrow prices show an honest publication-time state.
- Price bars retain fully rounded tops, negative-price headroom, unobstructed trailing axis labels, and numeric minimum/maximum annotations.
- Local Debug builds inject an optional Fingrid key into both the host and widget bundles without changing the credential-free public Release path.

### Verified

- Product metadata, Grid Conditions logic, maintenance safeguards, updater trust, uninstaller target resolution, macOS build verification, and the signed public release pipeline all cover this release.

## 1.2.3 - 2026-08-31

### Changed

- Published the first minimal signed update intended to exercise the transactional in-app updater included in the 1.2.2 bridge release.
- Kept widget presentation, electricity pricing, Grid Conditions, reset, and uninstall behavior unchanged so the upgrade result measures only the update path.

### Verified

- Patch-version ordering explicitly covers automatic discovery from installed version 1.2.2 to signed version 1.2.3.
- The release workflow validates, packages, signs, and independently verifies the detached Ed25519 update signature before publishing.

## 1.2.2 - 2026-08-31

### Changed

- Replaced the installer-opening update flow with a signed, transactional in-place updater. The host and bounded maintenance helper independently verify a detached Ed25519 signature; the helper then validates the exact bundle identifier, newer semantic version, and complete nested code-signature tree before replacement.
- The previous app remains available as a hidden rollback copy until the updated process launches and remains alive. A failed launch restores the previous version.

### Fixed

- Automatic update no longer removes the running app before a verified replacement is ready.
- Removed the embedded Sparkle runtime, which cannot pass Hardened Runtime library validation in the project’s free ad-hoc signing mode because the app and framework have no matching Apple Team ID.

## 1.2.1 - 2026-08-31

### Changed

- Published a minimal patch release so installations running 1.2.0 can exercise the complete in-app update discovery, checksum verification, and installer-opening flow against a newer public version.

### Verified

- Patch-version ordering now explicitly covers the 1.2.0 to 1.2.1 update path.
- The uninstall behavior from 1.2.0 is unchanged: the confirmed action moves the installed app bundle to the Trash, which is the standard removal model for a standalone macOS app.

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
