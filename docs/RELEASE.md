# Release Finland Electricity Rates

The default product path is free direct distribution outside the Mac App Store. It creates an ad-hoc signed Universal disk image without a paid Apple Developer Program account. This preserves bundle integrity, but it does not establish a verified developer identity or satisfy Gatekeeper automatically on a newly downloaded copy.

## Trust model

- GitHub Releases is the authoritative download location.
- The release includes a SHA-256 checksum for corruption and manual integrity checks.
- The app, widget extension, and narrowly scoped uninstall XPC service are ad-hoc signed and validated with `codesign --verify --deep --strict`.
- Users may need **System Settings → Privacy & Security → Open Anyway** on first launch.
- Release tooling must never disable Gatekeeper, strip quarantine metadata, or describe a direct artifact as Apple-notarized.

The checksum and disk image live in the same GitHub release, so they do not protect against compromise of the repository or its release account. Developer ID signing and notarization are the upgrade path when verified publisher identity and automatic Gatekeeper acceptance become product requirements.

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

No signing certificate, Apple membership, notarization password, or release secret is required in direct mode.

## Validate locally

```bash
script/validate-product.sh
SPOT_PRICE_DISTRIBUTION=direct script/package-release.sh
```

The packaging script builds the host, widget extension, and uninstall XPC service for both `arm64` and `x86_64`. It signs each nested component with a fixed identifier, requires the host and widget sandbox entitlements, requires the bounded helper to remain outside the app sandbox, verifies the complete signature tree, confirms that Developer ID assessment is rejected as expected, creates `dist/Finland-Electricity-Rates.dmg`, signs the disk image ad hoc, and writes its SHA-256 checksum.

The packaging script also calls the exact embedded relay endpoint and requires a valid dataset 396 payload. Mount the disk image and verify the app, both architectures, product version, privacy manifests, absence of credentials, and the included first-launch notice before publishing.

## Publish

1. Fast-forward `stable` to the verified `maintenance` commit.
2. Create an annotated semantic-version tag on that exact commit, such as `v1.0.0`.
3. Push the tag.
4. Confirm the **Release macOS** workflow succeeds.
5. Confirm the GitHub Release contains `Finland-Electricity-Rates.dmg` and `Finland-Electricity-Rates.dmg.sha256` and clearly describes the direct-distribution trust model.
6. Run the public installer into a temporary destination and verify checksum, signature integrity, installation, widget registration, and first-launch guidance.

## Optional Developer ID mode

`SPOT_PRICE_DISTRIBUTION=developer-id` remains available for a future paid distribution path. It requires a Developer ID Application identity plus notarization credentials or a `notarytool` Keychain profile. See the variables checked by `script/package-release.sh` and store every credential outside the repository.

Do not switch the public workflow to Developer ID mode until the exact Apple team, certificate, credentials, and release goal have been approved and verified.
