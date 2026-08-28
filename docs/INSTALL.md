# Install SpotPriceWidget

## Requirements

- macOS 26.5 or later
- The full Xcode app, with the license accepted and command-line components available
- Internet access while downloading the source and widget data

## One-command install

```bash
curl -fsSL https://raw.githubusercontent.com/phatleatfinepass/SpotPrice-Widget/stable/script/install.sh | bash
```

The script downloads the `stable` branch into a temporary directory, builds the macOS app locally, applies an ad hoc signature, verifies that signature, installs the app at `~/Applications/SpotPriceWidget.app`, registers the widget extension, and opens the app.

An existing installation is moved to a timestamped backup in the same directory before replacement. The installer never uses `sudo`, changes Gatekeeper settings, or persists credentials.

## Installer options

Set an option only for the installer process:

```bash
curl -fsSL https://raw.githubusercontent.com/phatleatfinepass/SpotPrice-Widget/stable/script/install.sh \
  | SPOT_PRICE_INSTALL_DIR=/path/to/apps SPOT_PRICE_SKIP_OPEN=1 bash
```

Available variables:

- `SPOT_PRICE_INSTALL_DIR` — destination directory; defaults to `~/Applications`.
- `SPOT_PRICE_SKIP_OPEN=1` — install and register without opening the app.
- `SPOT_PRICE_REF` — repository branch or tag; defaults to `stable`.
- `SPOT_PRICE_REPOSITORY` — GitHub `owner/repository`; intended for testing forks.

## Add the widgets

1. Open **Finland Electricity Rates** once after installation.
2. Open the macOS widget gallery.
3. Search for **Finland Electricity Rates**.
4. Choose the Electricity Rates, Grid Conditions, or HEL Airspace Radar widget and select a supported size.

If the gallery had already been open, close and reopen it after the app launches.

## Fingrid emissions

Fingrid’s grid-emissions endpoint requires an API key. Public builds deliberately leave this optional value unset, so the emissions value may appear unavailable while the keyless renewable forecast continues to work.

Developers who enable emissions must keep the credential in macOS Keychain and inject it through a local, unversioned Xcode build configuration. Never add a Fingrid key to source files, project files, shell scripts, screenshots, or commits.

## Remove the app

Quit the host app, then move `~/Applications/SpotPriceWidget.app` to the Trash. Any timestamped backup beside it can also be moved to the Trash after you confirm the current installation works.
