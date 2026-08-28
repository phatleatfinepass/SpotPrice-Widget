# Install Finland Electricity Rates

## Requirements

- macOS 26.5 or later
- Internet access for the initial download and live widget data

Xcode is not required for the signed product release.

## Install from the disk image

1. [Download the latest release](https://github.com/phatleatfinepass/SpotPrice-Widget/releases/latest/download/Finland-Electricity-Rates.dmg).
2. Open `Finland-Electricity-Rates.dmg`.
3. Drag **Finland Electricity Rates** into the Applications folder shown in the disk image.
4. Open the app once.
5. Open the macOS widget gallery and search for **Finland Electricity Rates**.

The disk image and embedded app are Developer ID-signed, Apple-notarized, and stapled for Gatekeeper verification.

## Terminal install or update

```bash
curl -fsSL https://raw.githubusercontent.com/phatleatfinepass/SpotPrice-Widget/stable/script/install.sh | bash
```

The installer downloads the latest GitHub Release, verifies the published SHA-256 checksum, validates the Developer ID signature and Gatekeeper acceptance, installs the app at `~/Applications/Finland Electricity Rates.app`, registers the widget extension, and opens the app.

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

## Build from source

The source installer remains available for contributors and requires the full Xcode app:

```bash
curl -fsSL https://raw.githubusercontent.com/phatleatfinepass/SpotPrice-Widget/stable/script/install-from-source.sh | bash
```

Source builds are ad hoc-signed development artifacts and are not equivalent to the notarized product release.

## Remove the app

Quit the host app, then move `Finland Electricity Rates.app` from Applications to the Trash. Timestamped backups beside the installation can also be moved to the Trash after confirming the current installation works.
