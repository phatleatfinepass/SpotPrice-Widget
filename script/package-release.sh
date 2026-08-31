#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output_dir="${SPOT_PRICE_OUTPUT_DIR:-$repo_root/dist}"
version="${SPOT_PRICE_VERSION:-}"
build_version="${SPOT_PRICE_BUILD_VERSION:-}"
distribution="${SPOT_PRICE_DISTRIBUTION:-direct}"
signing_identity="${SPOT_PRICE_SIGNING_IDENTITY:-}"
signing_keychain="${SPOT_PRICE_SIGNING_KEYCHAIN:-}"
notary_profile="${SPOT_PRICE_NOTARY_PROFILE:-}"

fail() {
  printf 'Release packaging failed: %s\n' "$1" >&2
  exit 1
}

if [[ -z "$version" ]]; then
  version="$(awk -F ' = ' '/MARKETING_VERSION = / { gsub(/;/, "", $2); print $2; exit }' "$repo_root/SpotPriceWidget.xcodeproj/project.pbxproj")"
fi
version="${version#v}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
  || fail "SPOT_PRICE_VERSION must use semantic versioning, for example 1.0.0"

if [[ -z "$build_version" ]]; then
  build_version="$(awk -F ' = ' '/CURRENT_PROJECT_VERSION = / { gsub(/;/, "", $2); print $2; exit }' "$repo_root/SpotPriceWidget.xcodeproj/project.pbxproj")"
fi
[[ "$build_version" =~ ^[0-9]+$ ]] \
  || fail "SPOT_PRICE_BUILD_VERSION must be numeric"

case "$distribution" in
  direct|developer-id) ;;
  *) fail "SPOT_PRICE_DISTRIBUTION must be direct or developer-id" ;;
esac

case "$output_dir" in
  ""|"/") fail "refusing unsafe output directory: '$output_dir'" ;;
esac

for command_name in xcodebuild codesign ditto hdiutil lipo shasum plutil; do
  command -v "$command_name" >/dev/null 2>&1 \
    || fail "required command is missing: $command_name"
done

if [[ "$distribution" == "developer-id" ]]; then
  [[ -n "$signing_identity" ]] \
    || fail "Developer ID mode requires SPOT_PRICE_SIGNING_IDENTITY"
  if [[ -z "$notary_profile" ]]; then
    for variable_name in SPOT_PRICE_NOTARY_APPLE_ID SPOT_PRICE_NOTARY_TEAM_ID SPOT_PRICE_NOTARY_APP_PASSWORD; do
      [[ -n "${!variable_name:-}" ]] || fail "set $variable_name or SPOT_PRICE_NOTARY_PROFILE"
    done
  fi
fi

codesign_keychain_args=()
if [[ -n "$signing_keychain" ]]; then
  codesign_keychain_args+=(--keychain "$signing_keychain")
fi

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/finland-electricity-release.XXXXXX")"
cleanup() {
  if [[ -d "$work_dir" ]]; then
    rm -rf -- "$work_dir"
  fi
}
trap cleanup EXIT

derived_data="$work_dir/DerivedData"
stage_dir="$work_dir/stage"
staged_app="$stage_dir/Finland Electricity Rates.app"
built_app="$derived_data/Build/Products/Release/Finland Electricity Rates.app"
built_extension="$built_app/Contents/PlugIns/SpotPriceWidgetFinlandExtension.appex"
staged_extension="$staged_app/Contents/PlugIns/SpotPriceWidgetFinlandExtension.appex"
built_uninstaller="$built_app/Contents/XPCServices/SpotPriceWidgetUninstaller.xpc"
staged_uninstaller="$staged_app/Contents/XPCServices/SpotPriceWidgetUninstaller.xpc"
artifact_name="Finland-Electricity-Rates.dmg"
approved_relay_url="https://finland-grid-emissions-relay.phat-le.workers.dev/v1/finland/emissions/current"

printf 'Building Finland Electricity Rates %s (%s) for macOS…\n' "$version" "$build_version"
xcodebuild -quiet \
  -project "$repo_root/SpotPriceWidget.xcodeproj" \
  -scheme SpotPriceWidget \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$derived_data" \
  ARCHS='arm64 x86_64' \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO \
  MARKETING_VERSION="$version" \
  CURRENT_PROJECT_VERSION="$build_version" \
  build

[[ -d "$built_app" && -d "$built_extension" && -d "$built_uninstaller" ]] \
  || fail "build completed without the expected app, widget extension, and uninstall helper"
[[ "$(plutil -extract CFBundleName raw "$built_app/Contents/Info.plist")" == "Finland Electricity Rates" ]] \
  || fail "built app has the wrong bundle name"
[[ "$(plutil -extract CFBundleDisplayName raw "$built_extension/Contents/Info.plist")" == "Finland Electricity Rates" ]] \
  || fail "built widget extension has the wrong display name"
[[ -f "$built_app/Contents/Resources/AppIcon.icns" ]] \
  || fail "built app does not contain AppIcon.icns"

require_universal_binary() {
  local executable_path="$1"
  local label="$2"
  local architectures
  architectures="$(lipo -archs "$executable_path")"
  [[ " $architectures " == *" arm64 "* && " $architectures " == *" x86_64 "* ]] \
    || fail "$label is not universal (found: $architectures)"
}

require_universal_binary "$built_app/Contents/MacOS/SpotPriceWidget" "host app"
require_universal_binary "$built_extension/Contents/MacOS/SpotPriceWidgetFinlandExtension" "widget extension"
require_universal_binary "$built_uninstaller/Contents/MacOS/SpotPriceWidgetUninstaller" "uninstall helper"

embedded_fingrid_key="$(plutil -extract FingridAPIKey raw "$built_extension/Contents/Info.plist" 2>/dev/null || true)"
[[ -z "$embedded_fingrid_key" || "$embedded_fingrid_key" == '$(FINGRID_API_KEY)' ]] \
  || fail "release build contains a Fingrid API credential"

grid_emissions_relay_url="$(plutil -extract GridEmissionsRelayURL raw "$built_extension/Contents/Info.plist" 2>/dev/null || true)"
[[ "$grid_emissions_relay_url" == "$approved_relay_url" ]] \
  || fail "release build does not contain the exact approved grid-emissions relay URL"
"$repo_root/script/verify-grid-emissions-relay.sh" "$grid_emissions_relay_url"

mkdir -p "$stage_dir"
ditto "$built_app" "$staged_app"
ln -s /Applications "$stage_dir/Applications"

if [[ "$distribution" == "direct" ]]; then
  ditto "$repo_root/docs/DIRECT-DISTRIBUTION.txt" "$stage_dir/READ ME — First Launch.txt"
  printf 'Applying ad hoc signatures for free direct distribution…\n'
  codesign --force --sign - --options runtime \
    --identifier personal.SpotPriceWidget.Uninstaller \
    "$staged_uninstaller" >/dev/null
  codesign --force --sign - --options runtime \
    --identifier personal.SpotPriceWidget.SpotPriceWidgetFinland \
    --entitlements "$repo_root/SpotPriceWidgetFinland/SpotPriceWidgetFinland.entitlements" \
    "$staged_extension" >/dev/null
  codesign --force --sign - --options runtime \
    --identifier personal.SpotPriceWidget \
    --entitlements "$repo_root/SpotPriceWidget/SpotPriceWidget.entitlements" \
    "$staged_app" >/dev/null
else
  printf 'Signing the uninstall helper, widget extension, and app with Developer ID…\n'
  codesign --force --sign "$signing_identity" "${codesign_keychain_args[@]}" --options runtime --timestamp \
    --identifier personal.SpotPriceWidget.Uninstaller \
    "$staged_uninstaller" >/dev/null
  codesign --force --sign "$signing_identity" "${codesign_keychain_args[@]}" --options runtime --timestamp \
    --identifier personal.SpotPriceWidget.SpotPriceWidgetFinland \
    --entitlements "$repo_root/SpotPriceWidgetFinland/SpotPriceWidgetFinland.entitlements" \
    "$staged_extension" >/dev/null
  codesign --force --sign "$signing_identity" "${codesign_keychain_args[@]}" --options runtime --timestamp \
    --identifier personal.SpotPriceWidget \
    --entitlements "$repo_root/SpotPriceWidget/SpotPriceWidget.entitlements" \
    "$staged_app" >/dev/null
fi

codesign --verify --deep --strict "$staged_app"

require_identifier() {
  local bundle_path="$1"
  local expected_identifier="$2"
  local actual_identifier
  actual_identifier="$(codesign -dvv "$bundle_path" 2>&1 | awk -F= '/^Identifier=/{ print $2; exit }')"
  [[ "$actual_identifier" == "$expected_identifier" ]] \
    || fail "wrong signing identifier for $bundle_path (found: $actual_identifier)"
}

require_sandbox_entitlement() {
  local bundle_path="$1"
  local label="$2"
  local entitlement_file="$work_dir/$(printf '%s' "$label" | tr ' ' '-').entitlements.plist"
  codesign -d --entitlements :- "$bundle_path" >"$entitlement_file" 2>/dev/null
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.app-sandbox' "$entitlement_file" 2>/dev/null || true)" == "true" ]] \
    || fail "$label must remain sandboxed"
}

require_identifier "$staged_app" personal.SpotPriceWidget
require_identifier "$staged_extension" personal.SpotPriceWidget.SpotPriceWidgetFinland
require_identifier "$staged_uninstaller" personal.SpotPriceWidget.Uninstaller
require_sandbox_entitlement "$staged_app" "host app"
require_sandbox_entitlement "$staged_extension" "widget extension"

uninstaller_entitlements="$work_dir/uninstaller.entitlements.plist"
codesign -d --entitlements :- "$staged_uninstaller" >"$uninstaller_entitlements" 2>/dev/null || true
if [[ -s "$uninstaller_entitlements" ]] && \
   [[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.app-sandbox' "$uninstaller_entitlements" 2>/dev/null || true)" == "true" ]]; then
  fail "the narrowly scoped uninstall helper must run outside the app sandbox"
fi

notary_submit() {
  local artifact="$1"
  if [[ -n "$notary_profile" ]]; then
    xcrun notarytool submit "$artifact" --keychain-profile "$notary_profile" --wait
  else
    xcrun notarytool submit "$artifact" \
      --apple-id "$SPOT_PRICE_NOTARY_APPLE_ID" \
      --team-id "$SPOT_PRICE_NOTARY_TEAM_ID" \
      --password "$SPOT_PRICE_NOTARY_APP_PASSWORD" \
      --wait
  fi
}

if [[ "$distribution" == "developer-id" ]]; then
  printf 'Notarizing the signed app…\n'
  app_zip="$work_dir/Finland-Electricity-Rates-${version}.zip"
  ditto -c -k --keepParent "$staged_app" "$app_zip"
  notary_submit "$app_zip"
  xcrun stapler staple "$staged_app"
  xcrun stapler validate "$staged_app"
else
  if spctl --assess --type execute "$staged_app" >/dev/null 2>&1; then
    fail "direct package unexpectedly passed Developer ID assessment"
  fi
  printf 'Gatekeeper assessment: manual first-launch approval expected.\n'
fi

mkdir -p "$output_dir"
dmg_path="$output_dir/$artifact_name"
checksum_path="$dmg_path.sha256"
rm -f -- "$dmg_path" "$checksum_path"

printf 'Creating disk image…\n'
hdiutil create \
  -volname 'Finland Electricity Rates' \
  -srcfolder "$stage_dir" \
  -ov \
  -format UDZO \
  "$dmg_path" >/dev/null

if [[ "$distribution" == "direct" ]]; then
  codesign --force --sign - "$dmg_path" >/dev/null
else
  codesign --force --sign "$signing_identity" "${codesign_keychain_args[@]}" --timestamp "$dmg_path" >/dev/null
  printf 'Notarizing the disk image…\n'
  notary_submit "$dmg_path"
  xcrun stapler staple "$dmg_path"
  xcrun stapler validate "$dmg_path"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg_path"
  spctl --assess --type execute --verbose=2 "$staged_app"
fi

codesign --verify "$dmg_path"

(
  cd "$output_dir"
  shasum -a 256 "$artifact_name" > "$(basename "$checksum_path")"
)

printf 'Distribution mode: %s\n' "$distribution"
printf 'Release artifact: %s\n' "$dmg_path"
printf 'Checksum: %s\n' "$checksum_path"
