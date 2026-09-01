# App, Widget, Icon, and Update Engineering Playbook

Lifecycle: active
Authority: operational
Owner: project
Verified baseline: SpotPriceWidget 1.2.5 (`ce4acde`), 2026-09-01

This is the project-owned implementation guide for building Finland Electricity Rates. It records the mechanisms that were verified while creating the host app, WidgetKit extension, product icon, direct release, and automatic updater. It is deliberately specific to this repository; it does not replace Apple's platform documentation.

## Product architecture

| Component | Project target | Bundle identifier | Security boundary |
| --- | --- | --- | --- |
| Host app | `SpotPriceWidget` | `personal.SpotPriceWidget` | Sandboxed; user interface, dashboard, update discovery |
| Widget extension | `SpotPriceWidgetFinlandExtension` | `personal.SpotPriceWidget.SpotPriceWidgetFinland` | Sandboxed; network client, WidgetKit timelines |
| Maintenance helper | `SpotPriceWidgetUninstaller` | `personal.SpotPriceWidget.Uninstaller` | Unsandboxed and narrowly scoped; authenticated XPC caller, update transaction, registration repair, uninstall |
| Grid-emissions relay | `backend/grid-emissions-relay` | Public read-only endpoint | Keeps the Fingrid credential outside every app bundle |

The host embeds the widget extension at:

```text
Finland Electricity Rates.app/Contents/PlugIns/SpotPriceWidgetFinlandExtension.appex
```

The host also embeds the XPC service. The helper is not a general installer: it accepts only the exact containing app, the fixed product identifiers, and a signed newer project release.

## 1. Create the app

### Establish identity before UI work

Keep these values synchronized in `SpotPriceWidget.xcodeproj/project.pbxproj`:

- product name and `CFBundleDisplayName`: `Finland Electricity Rates`
- host bundle identifier: `personal.SpotPriceWidget`
- semantic version: `MARKETING_VERSION`
- monotonically increasing build: `CURRENT_PROJECT_VERSION`
- supported platforms and deployment targets
- `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` on the host target

A rename is not complete until the built app, embedded extension, scripts, release assets, update trust policy, and registration tests agree. Source-folder names may remain internal; customer-visible names must come from product metadata.

### Keep the boundaries explicit

- The host and widget use App Sandbox entitlements.
- The widget has outbound network access because WidgetKit performs its own refreshes.
- The free ad-hoc distribution deliberately avoids an App Group. `Shared/WidgetDataStore.swift` therefore keeps rebuildable fallback caches per process.
- Secrets never belong in source, project settings, the app, the extension, screenshots, or release assets. The public build reads Fingrid data through the server-side relay.
- The maintenance helper stays outside App Sandbox only because replacing or trashing the containing app cannot be implemented reliably from the host sandbox. Its XPC connection is authenticated against the exact containing application.

### Build the complete product, not only the executable

Use the scheme so Xcode builds and embeds all targets:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project SpotPriceWidget.xcodeproj \
  -scheme SpotPriceWidget \
  -destination 'platform=macOS' \
  build
```

Never update only `Contents/MacOS/SpotPriceWidget`. A development build can depend on companion dynamic libraries, the widget extension, resources, and the XPC service. Install or replace the complete `.app` bundle.

### Package direct distribution

`script/package-release.sh` is the authority for the free direct build. It:

1. builds Universal `arm64` and `x86_64` host, widget, and helper binaries;
2. requires the correct bundle names, identifiers, relay URL, and `AppIcon.icns`;
3. rejects an embedded Fingrid credential;
4. applies nested ad-hoc signatures in dependency order;
5. verifies the complete signature tree;
6. creates `Finland-Electricity-Rates.dmg` and its SHA-256 checksum.

Ad-hoc signing protects bundle integrity but does not provide a verified Apple developer identity or notarization. A first-time user may still need **Privacy & Security → Open Anyway**. The product must never disable Gatekeeper or remove quarantine metadata to hide that trade-off.

## 2. Create and update the app safely

### Trust chain

GitHub Releases is the authoritative update source. A publishable release contains exactly:

```text
Finland-Electricity-Rates.dmg
Finland-Electricity-Rates.dmg.sha256
Finland-Electricity-Rates.dmg.sig
```

The detached signature is Ed25519. Its private key exists only in the protected provider secret named `SPOT_PRICE_UPDATE_PRIVATE_KEY`; only the public verification key is compiled into the product. The host and helper independently verify the signature so neither the network response nor a compromised release account is sufficient to install arbitrary bytes.

The update client also requires:

- the expected GitHub repository and HTTPS asset paths;
- a non-draft, non-prerelease semantic version newer than the current version;
- the expected host bundle identifier and version inside the DMG;
- a complete, strict nested code-signature validation across all architectures;
- bounded metadata, signature, and disk-image sizes.

### Finalized handoff

The approved transaction is:

```text
discover
  → download DMG + detached signature
  → host verifies signature and release policy
  → helper verifies again and stages the complete app
  → helper replies READY
  → current host terminates
  → helper waits for that authenticated caller PID to exit
  → unregister old host and widget
  → stop the exact resident widget-extension executable
  → move old app to a transaction backup
  → move staged app to the canonical path
  → register the new host and exact embedded widget
  → launch one new app instance
  → verify process survival and exact widget registration
  → remove backup
```

`SpotPriceWidget/SoftwareUpdateService.swift` owns discovery, download, host-side verification, and host termination. `SpotPriceWidgetUninstaller/UpdateInstaller.swift` owns prepare, commit, rollback, registration, and relaunch. `UpdateHostLifecycle.swift` waits for the exact XPC caller PID. `WidgetExtensionLifecycle.swift` enumerates same-user processes and stops only the complete canonical executable path embedded in the validated app. The helper disables sudden and automatic termination while a prepared transaction is outstanding.

This order is an invariant. Launching the replacement before the old process exits creates two app instances and lets macOS resolve the wrong bundle or widget extension. Replacing the bundle without stopping its resident WidgetKit process can leave macOS executing pre-update code from memory even though the on-disk extension is current. Deleting the old app before the replacement is staged and verified removes the rollback boundary.

### Rollback is part of installation

The previous app is retained until the replacement:

- launches from the canonical path;
- remains alive through the validation interval; and
- owns the registered widget-extension path.

If replacement, launch, or registration fails, the helper unregisters the failed copy, restores the backup to the canonical path, registers it again, and relaunches it. A successful update removes the backup only after verification.

### Understand bridge releases

The currently installed app executes the updater. Therefore, a release that fixes the updater cannot change the handoff that installs itself. Treat updater changes as a two-release proof:

1. verify `N → N+1` delivers the new updater safely enough;
2. verify `N+1 → N+2` exercises the new behavior end to end.

Version 1.2.2 was the signed transactional-updater bridge. Version 1.2.5 added the clean host-process handoff and launch-time widget-registration repair. Version 1.2.8 adds exact widget-process termination. Because 1.2.7's helper installs 1.2.8, the replacement host waits for that incoming transaction to finish, calls a new restart selector, retries if the old helper still owns the service, then reloads every timeline. Future updater work must retain an explicit bridge test instead of assuming the new code controls the incoming update.

### Release gates

Before publishing:

```bash
script/validate-product.sh
script/test-software-update.sh
script/test-update-handoff.sh
script/test-product-maintenance.sh
script/test-widget-registration-integration.sh /path/to/signed/Finland\ Electricity\ Rates.app
script/test-uninstaller-integration.sh /path/to/signed/Finland\ Electricity\ Rates.app
SPOT_PRICE_DISTRIBUTION=direct script/package-release.sh
```

CI runs the product checks on macOS and builds the iOS Simulator target. The release workflow packages from the exact `stable` commit, signs the update with the protected provider secret, verifies that signature, and gives write permission only to the artifact-only publish job.

## 3. Create the WidgetKit extension

### Target and bundle setup

The working shape is:

1. Add a Widget Extension target and embed it in the host app.
2. Use a bundle identifier nested under the host identifier.
3. Set `NSExtensionPointIdentifier` to `com.apple.widgetkit-extension`.
4. Set `SKIP_INSTALL = YES`; the extension ships inside the host rather than as a separate app.
5. Give the extension only the entitlements it needs: App Sandbox and outbound network access here.
6. Declare customer-facing widgets in one `WidgetBundle`.

`SpotPriceWidgetFinlandBundle.swift` exposes both `SpotPriceWidgetFinland` and `FinlandGridForecastWidget`. Each has a stable `kind`, a `TimelineProvider`, a `StaticConfiguration`, supported families, and `.containerBackground(.fill.tertiary, for: .widget)`.

### Timeline pattern

Each provider must implement three distinct states:

- placeholder: deterministic sample content for the gallery;
- snapshot: preview content in previews, otherwise a bounded live/fallback load;
- timeline: entries at meaningful data transitions plus a conservative reload policy.

For prices, the timeline includes upcoming market boundaries and requests another refresh 15 minutes after the final entry. For Grid Conditions, the provider loads renewable forecast and live emissions independently, adds safety entries when a forecast slot or emissions measurement expires, and retries within 15 minutes.

Network failure must not turn stale data into a false current claim. Preserve a bounded last-known value, mark it stale, and render an honest unavailable state when its validity expires. `WidgetCenter.reloadAllTimelines()` and `reloadTimelines(ofKind:)` request refreshes; WidgetKit still controls execution time.

### Design each family for its job

Do not scale one canvas into every widget family.

- Small: one glanceable current state, compact range or signal, no duplicate labels.
- Medium: current state plus the next useful context, such as a complete 24-hour chart.
- Large or extra large: richer explanation only when it remains scannable.
- Accessibility: combine the visual into a sentence that states current value, band, and forecast meaning.

Use Apple Charts for quantitative series and SF Symbols for semantic icons. Encode state with text and geometry as well as color. Keep chart marks and labels within the plot area, reserve enough padding for axes, and test negative values rather than clamping them away.

### Registration is part of correctness

A valid `.appex` on disk does not prove the widget gallery is using it. The authoritative diagnostic is:

```bash
/usr/bin/pluginkit -m -A -D -v \
  -i personal.SpotPriceWidget.SpotPriceWidgetFinland
```

The registered path must be the exact extension inside the canonical installed app—not DerivedData, a mounted DMG, a temporary update stage, or an older installation.

The maintenance helper repairs registration by:

1. validating the exact containing app and widget identifiers;
2. unregistering the current extension path;
3. stopping only the resident process whose canonical executable path matches that embedded extension;
4. removing competing registrations for the same widget identifier;
5. registering the host with `lsregister -f -R`;
6. registering the embedded extension with `pluginkit -a`;
7. polling until PluginKit reports the canonical extension path.

Registration repair begins in `SpotPriceWidgetApp.init`, not in a view's `.task`. macOS may restore the application without constructing a visible SwiftUI window, so product maintenance that depends on a view appearing is not reliable.

## 4. Make the app and widget logo

### Keep one canonical visual source

The approved source artwork is:

```text
docs/assets/logo-concepts/selected-confluence.png
```

Use one source to generate every platform asset. Do not keep competing concepts in the shipping asset catalog. The mark should remain recognizable at 16 points, preserve a quiet safe area around its silhouette, and avoid hairline detail that disappears in Finder or the widget gallery.

### Build the host AppIcon set

The host's `Assets.xcassets/AppIcon.appiconset` contains these rendered outputs:

| Slot | Pixels |
| --- | ---: |
| macOS 16 pt @1x / @2x | 16 / 32 |
| macOS 32 pt @1x / @2x | 32 / 64 |
| macOS 128 pt @1x / @2x | 128 / 256 |
| macOS 256 pt @1x / @2x | 256 / 512 |
| macOS 512 pt @1x / @2x | 512 / 1024 |
| iOS universal marketing icon | 1024 |

`SpotPriceWidget/Assets.xcassets/AppIcon.appiconset/Contents.json` must name every actual file, and the host target must compile `AppIcon`. The release is invalid if the built macOS bundle does not contain `Contents/Resources/AppIcon.icns`.

Inspect dimensions before building:

```bash
sips -g pixelWidth -g pixelHeight \
  SpotPriceWidget/Assets.xcassets/AppIcon.appiconset/*.png
```

Then inspect the built product rather than trusting the source catalog:

```bash
test -f '/path/to/Finland Electricity Rates.app/Contents/Resources/AppIcon.icns'
plutil -p '/path/to/Finland Electricity Rates.app/Contents/Info.plist'
codesign --verify --deep --strict '/path/to/Finland Electricity Rates.app'
```

### The widget gallery does not have a second product logo

The gallery entry is attributed to the containing app. Its name and logo come from the host application's metadata, compiled `AppIcon`, and Launch Services registration. Symbols drawn inside a widget—such as a leaf, bolt, or CO2 icon—are widget UI, not the gallery logo.

The extension currently has no independently compiled shipping icon. Adding a second set of icon files to the extension does not repair a missing gallery logo and can create conflicting identity. Verify the host icon first, then verify that Launch Services and PluginKit point to the canonical host and extension.

## Findings adopted from the build and update work

| Expected | Actual | Supported mechanism | Durable action | Claim |
| --- | --- | --- | --- | --- |
| Updating should replace one running app with one newer app. | The earlier flow visibly opened the replacement and then closed the old app. | The installer launched before the authenticated caller PID had exited. | Stage first, reply ready, terminate host, wait for its PID, then swap and relaunch. Covered by `test-update-handoff.sh`. | Observed |
| A packaged widget should remain selectable after an update. | The widget disappeared even though the `.appex` existed and signatures were valid. | PluginKit could still resolve a Debug, temporary, or previous extension path. | Treat exact-path registration and verification as part of install and rollback. Covered by `test-widget-registration-integration.sh`. | Observed |
| Startup repair in the dashboard should repair registration. | The integration path could launch without constructing that view. | A SwiftUI view task is conditional on view creation; app initialization is not. | Start product maintenance from the app lifecycle. | Observed |
| Installing a release containing an updater fix should immediately use the new flow. | The incoming update still behaved like the previous version. | The old installed process performs the installation. | Plan bridge releases and prove both `N → N+1` and `N+1 → N+2`. | Observed |
| Replacing the app bundle should update the visible widgets. | The app reached 1.2.7 while the widget kept rendering older code. | The WidgetKit extension process had remained resident since before several app updates. | Stop only the exact canonical embedded-extension process before replacement and from the new startup repair. Covered by `test-update-handoff.sh` and the registration integration test. | Observed |
| Supplying icon PNGs should make the gallery logo appear. | Correct-looking source assets could still produce a blank or stale gallery identity. | Registration and caches also participate; the exact original single cause was not isolated. | Verify built `AppIcon.icns` and canonical host/extension registration before changing artwork. | Inferred |

All six lessons are owned by this project. The first five have project regression coverage or direct integration coverage; the icon lesson remains an evidence-backed diagnostic rule rather than a claim that every blank icon has the same cause.

Adoption status: adopted. Verification status: passing on the 1.2.8 baseline. Regression is passing for update trust, host and widget process handoff, product maintenance, and exact-path widget registration. A separate automated regression is not required for the bridge-release rule or icon diagnostic: their repeatable verification is the two-step `N → N+1 → N+2` public update test and inspection of the packaged `AppIcon.icns` plus canonical Launch Services/PluginKit paths.

## Definition of done

### App and update

- Versions and customer-facing names agree across targets and release assets.
- Host and widget are sandboxed; the helper is authenticated and narrowly scoped.
- No provider credential is embedded.
- DMG, checksum, and detached signature are published from the exact `stable` commit.
- Update discovery, signature verification, prepare/commit handoff, rollback, relaunch, and bridge behavior are tested.
- The previous resident widget-extension process is gone before the replacement is registered.
- Only one new app instance launches and the previous backup is removed after validation.

### Widget

- Every widget kind appears in the bundle and declares supported families.
- Placeholders, snapshots, live timelines, stale states, and unavailable states are tested.
- The widget is embedded and completely signed.
- PluginKit resolves the extension inside the canonical installed app.
- Registration repair works even when no SwiftUI window is restored.

### Logo

- One approved source owns the visual identity.
- Every AppIcon filename and pixel dimension matches `SpotPriceWidget/Assets.xcassets/AppIcon.appiconset/Contents.json`.
- The host compiles `AppIcon`, and the packaged app contains `AppIcon.icns`.
- The mark is inspected at 16, 32, 128, and 1024 pixels.
- Finder, Applications, and the widget gallery are checked only after stale registrations are excluded.

## Primary implementation references

- App lifecycle: `SpotPriceWidget/SpotPriceWidgetApp.swift`
- Update client: `SpotPriceWidget/SoftwareUpdateService.swift`
- XPC contract: `SpotPriceWidget/ProductMaintenanceLogic.swift`
- Update transaction: `SpotPriceWidgetUninstaller/UpdateInstaller.swift`
- Widget process handoff: `SpotPriceWidgetUninstaller/WidgetExtensionLifecycle.swift`
- Registration parser: `SpotPriceWidgetUninstaller/WidgetRegistrationPaths.swift`
- Widget bundle: `SpotPriceWidgetFinland/SpotPriceWidgetFinlandBundle.swift`
- Electricity Rates widget: `SpotPriceWidgetFinland/SpotPriceWidgetFinland.swift`
- Grid Conditions widget: `SpotPriceWidgetFinland/FinlandGridForecastWidget.swift`
- Release process: `docs/RELEASE.md`
- Installation and recovery: `docs/INSTALL.md`
