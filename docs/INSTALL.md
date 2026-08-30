# Install Finland Electricity Rates

## Requirements

- macOS 26.5 or later
- Internet access for the initial download and live widget data

Xcode is not required for the packaged product release.

## Install from the disk image

1. [Download the latest release](https://github.com/phatleatfinepass/SpotPrice-Widget/releases/latest/download/Finland-Electricity-Rates.dmg).
2. Open `Finland-Electricity-Rates.dmg`.
3. Drag **Finland Electricity Rates** into the Applications folder shown in the disk image.
4. Open the app once. If macOS blocks it, open **System Settings → Privacy & Security**, confirm the app name, and select **Open Anyway**.
5. Confirm the second macOS prompt, then open the macOS widget gallery and search for **Finland Electricity Rates**.

The disk image contains an ad-hoc signed Universal app for Intel and Apple silicon. It is not Apple-notarized and carries no paid Developer ID identity, so manual approval can be required on first launch. Only download releases from this repository and compare the published SHA-256 checksum when verifying one manually.

## Terminal install or update

```bash
curl -fsSL https://raw.githubusercontent.com/phatleatfinepass/SpotPrice-Widget/stable/script/install.sh | bash
```

The installer downloads the latest GitHub Release, verifies the published SHA-256 checksum and app code-signature integrity, installs the app at `~/Applications/Finland Electricity Rates.app`, registers the widget extension, and opens the app. It removes stale Launch Services records for older copies of this app so the widget gallery resolves the installed name and logo; it does not delete those older app bundles. It explains the same manual approval path when Gatekeeper does not recognize the release.

An existing product installation is moved to a timestamped backup before replacement. The older `SpotPriceWidget.app` development installation is also backed up during migration. The installer never uses `sudo` or changes Gatekeeper settings.

### Installer options

Set an option only for the installer process:

```bash
curl -fsSL https://raw.githubusercontent.com/phatleatfinepass/SpotPrice-Widget/stable/script/install.sh \
  | SPOT_PRICE_INSTALL_DIR=/path/to/apps SPOT_PRICE_SKIP_OPEN=1 bash
```

- `SPOT_PRICE_INSTALL_DIR` — destination directory; defaults to `~/Applications`.
- `SPOT_PRICE_SKIP_OPEN=1` — install and register without opening the app.
- `SPOT_PRICE_REPOSITORY` — GitHub `owner/repository`; intended for testing forks.
- `SPOT_PRICE_RELEASE_BASE_URL` — exact release-asset base URL; intended for release validation.

## Add the widgets

1. Open **Finland Electricity Rates** once after installation.
2. Open the macOS widget gallery.
3. Search for **Finland Electricity Rates**.
4. Choose Electricity Rates or Grid Conditions and select a supported size.

If the gallery was already open, close and reopen it after the app launches.

## Fingrid emissions

Fingrid's grid-emissions API requires registration and an API key. The public release does not embed a shared credential. When emissions are unavailable, the independent, keyless renewable forecast continues to work.

Developers who enable emissions must keep the credential in macOS Keychain and inject it through a local, unversioned Xcode build configuration. Never add a Fingrid key to source files, project files, shell scripts, screenshots, or commits.

For a local credential-enabled test, the source installer accepts `SPOT_PRICE_CONFIGURATION=Debug` and reads `FINGRID_API_KEY` from the current process only. Release builds always ignore that variable. Load the value from Keychain into the current shell through your private project workflow; do not paste it into a command or save it in an environment file.

## Build from source

The source installer remains available for contributors and requires the full Xcode app:

```bash
curl -fsSL https://raw.githubusercontent.com/phatleatfinepass/SpotPrice-Widget/maintenance/script/install-from-source.sh | bash
```

Source builds are local development artifacts. The packaged direct release adds a Universal build, fixed product naming, disk-image layout, integrity checks, and release documentation.

Always update a local Debug installation with the complete `.app` bundle. Do not replace only the launcher in `Contents/MacOS`: Xcode Debug builds keep the Swift implementation in companion `.debug.dylib` files. A partial replacement can leave old widget logic active or cause `dyld` to reject mismatched signatures. The source installer copies and signs the complete bundle.

## Remove the app

Quit the host app, then move `Finland Electricity Rates.app` from Applications to the Trash. Timestamped backups beside the installation can also be moved to the Trash after confirming the current installation works.
