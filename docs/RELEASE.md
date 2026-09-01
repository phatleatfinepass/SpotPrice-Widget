# Release Finland Electricity Rates

The default product path is free direct distribution outside the Mac App Store. It creates an ad-hoc signed Universal disk image without a paid Apple Developer Program account. This preserves bundle integrity, but it does not establish a verified developer identity or satisfy Gatekeeper automatically on a newly downloaded copy.

## Trust model

- GitHub Releases is the authoritative download location.
- The release includes a SHA-256 checksum for corruption and manual integrity checks.
- Automatic updates require a detached Ed25519 signature. The app and its bounded helper independently verify it with a pinned public key before replacing an installation.
- The app, widget extension, and narrowly scoped uninstall XPC service are ad-hoc signed and validated with `codesign --verify --deep --strict`.
- Users may need **System Settings → Privacy & Security → Open Anyway** on first launch.
- Release tooling must never disable Gatekeeper, strip quarantine metadata, or describe a direct artifact as Apple-notarized.

The detached signature is created with a private update key held outside the repository. A compromised release account cannot create an accepted automatic update without that key. Developer ID signing and notarization remain the upgrade path when verified publisher identity and automatic Gatekeeper acceptance on first installation become product requirements.

## Release prerequisites

- A clean `maintenance` branch with passing macOS and iOS Simulator CI
- A semantic version matching `MARKETING_VERSION`
- Xcode with the macOS SDK needed by the project
- No embedded Fingrid credential
- A deployed, healthy HTTPS grid-emissions relay configured in the Release build
- Passing relay type checks and tests from the locked npm dependency graph
- A passing disposable-copy uninstall integration test with the host and widget sandboxed and the bounded XPC service unsandboxed
- Release validation that depends only on commands present in the macOS runner; any added tool must be installed explicitly in CI
- A package job with read-only repository permission and no persisted checkout credential; only the artifact-only publish job receives `contents: write`
- The Ed25519 update private key configured as the protected provider secret `SPOT_PRICE_UPDATE_PRIVATE_KEY`; the value must never enter source, logs, documentation, or a command argument

No Apple signing certificate, Apple membership, or notarization password is required in direct mode. The project-specific Ed25519 update secret is required only to publish an artifact accepted by automatic update.

## Validate locally

```bash
script/validate-product.sh
SPOT_PRICE_DISTRIBUTION=direct script/package-release.sh
SPOT_PRICE_UPDATE_SIGNING_ACCOUNT=phatleatfinepass.SpotPriceWidget \
  SPOT_PRICE_SIGN_UPDATE_TOOL=/path/to/audited/sign_update \
  script/sign-release-update.sh
```

The packaging script builds the host, widget extension, and uninstall XPC service for both `arm64` and `x86_64`. It signs each nested component with a fixed identifier, requires the host and widget sandbox entitlements, requires the bounded helper to remain outside the app sandbox, verifies the complete signature tree, confirms that Developer ID assessment is rejected as expected, creates `dist/Finland-Electricity-Rates.dmg`, signs the disk image ad hoc, and writes its SHA-256 checksum.

The packaging script also calls the exact embedded relay endpoint and requires a valid dataset 396 payload. The signing step creates `dist/Finland-Electricity-Rates.dmg.sig` and immediately verifies it with the same pinned public key used by the product. Mount the disk image and verify the app, both architectures, product version, privacy manifests, absence of credentials, and the included first-launch notice before publishing.

## Publish

1. Fast-forward `stable` to the verified `maintenance` commit.
2. Create an annotated semantic-version tag on that exact commit, such as `v1.0.0`.
3. Push the tag.
4. Confirm the **Release macOS** workflow succeeds.
5. Confirm the GitHub Release contains `Finland-Electricity-Rates.dmg`, `Finland-Electricity-Rates.dmg.sha256`, and `Finland-Electricity-Rates.dmg.sig`, and clearly describes the direct-distribution trust model.
6. Run the public installer into a temporary destination and verify checksum, detached signature, code-signature integrity, installation, widget registration, and first-launch guidance.
7. From the preceding public version, run **Check for Updates** and verify discovery, signature verification, staged replacement, relaunch, version change, and removal of the temporary backup only after the new process stays alive.

The first release containing this signed transactional updater is a one-time bridge: installations on 1.2.1 or earlier still use the older installer-opening flow and must install that bridge release manually. After the bridge is installed, later signed releases can complete the in-place flow automatically.

The architecture, process-handoff invariant, widget-registration repair, icon pipeline, and adopted failure findings are maintained in the [app, widget, icon, and update engineering playbook](APP-WIDGET-ENGINEERING-PLAYBOOK.md).

## Optional Developer ID mode

`SPOT_PRICE_DISTRIBUTION=developer-id` remains available for a future paid distribution path. It requires a Developer ID Application identity plus notarization credentials or a `notarytool` Keychain profile. See the variables checked by `script/package-release.sh` and store every credential outside the repository.

Do not switch the public workflow to Developer ID mode until the exact Apple team, certificate, credentials, and release goal have been approved and verified.
