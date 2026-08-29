#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
SCHEME_NAME="SpotPriceWidget"
APP_BUNDLE_NAME="Finland Electricity Rates"
APP_PROCESS="SpotPriceWidget"
BUNDLE_ID="personal.SpotPriceWidget"
WIDGET_BUNDLE_ID="personal.SpotPriceWidget.SpotPriceWidgetFinland"
WIDGET_PROCESS="SpotPriceWidgetFinlandExtension"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/SpotPriceWidget.xcodeproj"
DERIVED_DATA_DIR="$ROOT_DIR/DerivedData"
APP_BUNDLE="$DERIVED_DATA_DIR/Build/Products/Debug/$APP_BUNDLE_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_PROCESS"
WIDGET_EXTENSION="$APP_BUNDLE/Contents/PlugIns/SpotPriceWidgetFinlandExtension.appex"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

pkill -x "$APP_PROCESS" >/dev/null 2>&1 || true
pkill -x "$WIDGET_PROCESS" >/dev/null 2>&1 || true

xcodebuild \
  -quiet \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME_NAME" \
  -configuration Debug \
  -destination "platform=macOS" \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  build

if [[ -n "${FINGRID_API_KEY:-}" ]]; then
  widget_info="$WIDGET_EXTENSION/Contents/Info.plist"
  if /usr/libexec/PlistBuddy -c 'Print :FingridAPIKey' "$widget_info" >/dev/null 2>&1; then
    /usr/libexec/PlistBuddy -c "Set :FingridAPIKey $FINGRID_API_KEY" "$widget_info" >/dev/null
  else
    /usr/libexec/PlistBuddy -c "Add :FingridAPIKey string $FINGRID_API_KEY" "$widget_info" >/dev/null
  fi
  codesign --force --sign - \
    --entitlements "$ROOT_DIR/SpotPriceWidgetFinland/SpotPriceWidgetFinland.entitlements" \
    "$WIDGET_EXTENSION" >/dev/null
  codesign --force --sign - \
    --entitlements "$ROOT_DIR/SpotPriceWidget/SpotPriceWidget.entitlements" \
    "$APP_BUNDLE" >/dev/null
fi

codesign --verify --deep --strict "$APP_BUNDLE"

while IFS= read -r registered_extension; do
  if [[ "$registered_extension" == /* ]]; then
    pluginkit -r "$registered_extension" >/dev/null 2>&1 || true
  fi
done < <(pluginkit -m -A -D -v -i "$WIDGET_BUNDLE_ID" | awk -F '\t' 'NF >= 4 { print $NF }')

"$LSREGISTER" -f -R "$APP_BUNDLE"
pluginkit -a "$WIDGET_EXTENSION"

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_PROCESS\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 2
    pgrep -x "$APP_PROCESS" >/dev/null
    printf 'Verified %s build ' "$APP_BUNDLE_NAME"
    /usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_BUNDLE/Contents/Info.plist"
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
