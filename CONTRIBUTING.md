# Contributing

Thanks for helping improve SpotPriceWidget.

## Branch workflow

- Start work from `maintenance` and open changes against `maintenance`.
- Keep `stable` release-ready. It is updated only after the macOS and iOS builds pass and the terminal installer is verified.
- Avoid force-pushes and history rewrites on either shared branch.

## Before submitting

Run both builds with the full Xcode app:

```bash
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

## Credentials and private data

Never commit API keys, passwords, tokens, personal data, `.env` files, local Xcode configurations, or screenshots containing credentials. Fingrid credentials belong in macOS Keychain and must enter builds only through local, unversioned configuration.
