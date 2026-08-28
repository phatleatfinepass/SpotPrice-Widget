# Contributing

Thanks for helping improve SpotPriceWidget.

## Branch workflow

- Start work from `maintenance` and open changes against `maintenance`.
- Keep `stable` release-ready. It is updated only after the macOS and iOS builds pass and the release package is verified.
- Avoid force-pushes and history rewrites on either shared branch.

## Before submitting

Run both builds with the full Xcode app:

```bash
script/validate-product.sh

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -quiet \
  -project SpotPriceWidget.xcodeproj \
  -scheme SpotPriceWidget \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO build

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -quiet \
  -project SpotPriceWidget.xcodeproj \
  -scheme SpotPriceWidget \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

Check small and medium widget previews in light and dark appearances when changing layout, typography, color bands, or charts.

Release packaging and notarization are documented in [docs/RELEASE.md](docs/RELEASE.md). Never publish the ad hoc-signed QA disk image produced by the local validation mode.

## Credentials and private data

Never commit API keys, passwords, tokens, personal data, `.env` files, local Xcode configurations, or screenshots containing credentials. Fingrid credentials belong in macOS Keychain and must enter builds only through local, unversioned configuration.
