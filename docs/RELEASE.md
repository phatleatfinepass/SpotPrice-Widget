# Release Finland Electricity Rates

This project distributes the macOS app outside the Mac App Store as a Developer ID-signed and Apple-notarized disk image. Do not publish an ad hoc-signed QA artifact as a release.

## Release prerequisites

- Active Apple Developer Program membership for team `NWP7L2BJP5`
- A **Developer ID Application** certificate exported as a password-protected PKCS#12 file
- An Apple ID and app-specific password authorized to submit notarization requests for that team
- A clean `maintenance` branch with passing macOS and iOS Simulator CI

The signing certificate and notarization credentials belong in GitHub Actions secrets, never in source files or documentation:

- `DEVELOPER_ID_APPLICATION_P12` — base64-encoded PKCS#12 archive
- `DEVELOPER_ID_APPLICATION_PASSWORD`
- `NOTARY_APPLE_ID`
- `NOTARY_TEAM_ID`
- `NOTARY_APP_PASSWORD`

## Validate locally

Validate metadata and produce an explicitly labelled, ad hoc-signed QA disk image:

```bash
script/validate-product.sh
SPOT_PRICE_SKIP_SIGNING=1 \
SPOT_PRICE_SKIP_NOTARIZATION=1 \
script/package-release.sh
```

The QA disk image is for structural testing only. Gatekeeper is expected to reject it on another Mac.

For a local production package, first store notarization credentials in Keychain with `notarytool`, then run:

```bash
SPOT_PRICE_SIGNING_IDENTITY="Developer ID Application: …" \
SPOT_PRICE_NOTARY_PROFILE="SpotPriceWidget-Notary" \
script/package-release.sh
```

The script signs the widget extension and host app, enables a secure timestamp and hardened runtime, notarizes and staples the app, builds and signs the disk image, notarizes and staples the disk image, validates Gatekeeper acceptance, and writes a SHA-256 checksum.

## Publish

1. Merge the release commit from `maintenance` into `stable`.
2. Create an annotated semantic-version tag on the verified `stable` commit, such as `v1.0.0`.
3. Push the tag.
4. Confirm the **Release macOS** workflow succeeds.
5. Download the published disk image from GitHub Releases on a clean Mac and verify install, launch, widget discovery, refresh, and replacement of an older installation.
6. Confirm the public installer resolves the new release and passes checksum, signature, and Gatekeeper verification.

The tag-triggered workflow publishes `Finland-Electricity-Rates.dmg` and its checksum only after signing and notarization succeed.
