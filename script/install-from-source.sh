#!/usr/bin/env bash
set -euo pipefail

repository="${SPOT_PRICE_REPOSITORY:-phatleatfinepass/SpotPrice-Widget}"
ref="${SPOT_PRICE_REF:-stable}"
install_dir="${SPOT_PRICE_INSTALL_DIR:-${HOME}/Applications}"
source_override="${SPOT_PRICE_SOURCE_DIR:-}"
app_name="Finland Electricity Rates"
app_bundle_id="personal.SpotPriceWidget"
widget_bundle_id="personal.SpotPriceWidget.SpotPriceWidgetFinland"
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

fail() {
  printf 'SpotPriceWidget source installer: %s\n' "$1" >&2
  exit 1
}

registered_app_paths() {
  [[ -x "$lsregister" ]] || return 0

  "$lsregister" -dump 2>/dev/null | awk -v bundle_id="$app_bundle_id" '
    BEGIN { RS = "--------------------------------------------------------------------------------" }
    {
      registered_identifier = ""
      registered_path = ""
      line_count = split($0, lines, "\n")
      for (line_number = 1; line_number <= line_count; line_number += 1) {
        line = lines[line_number]
        if (line ~ /^[[:space:]]*identifier:[[:space:]]*/) {
          registered_identifier = line
          sub(/^[[:space:]]*identifier:[[:space:]]*/, "", registered_identifier)
          sub(/[[:space:]]+$/, "", registered_identifier)
        } else if (line ~ /^[[:space:]]*path:[[:space:]]*/) {
          registered_path = line
          sub(/^[[:space:]]*path:[[:space:]]*/, "", registered_path)
          sub(/[[:space:]]+\(0x[[:xdigit:]]+\)[[:space:]]*$/, "", registered_path)
        }
      }
      if (registered_identifier == bundle_id && registered_path ~ /^\//) {
        print registered_path
      }
    }
  '
}

unregister_competing_apps() {
  local canonical_app="$1"
  local registered_app

  while IFS= read -r registered_app; do
    if [[ -n "$registered_app" && "$registered_app" != "$canonical_app" ]]; then
      "$lsregister" -u "$registered_app" >/dev/null 2>&1 || true
    fi
  done < <(registered_app_paths)
}

case "$install_dir" in
  ""|"/") fail "refusing unsafe install directory: '$install_dir'" ;;
esac

for command_name in awk curl tar xcodebuild codesign ditto; do
  command -v "$command_name" >/dev/null 2>&1 \
    || fail "required command is missing: $command_name"
done

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

xcodebuild -version >/dev/null 2>&1 \
  || fail "the full Xcode app is required; install Xcode and select its developer directory"

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/spot-price-widget-source.XXXXXX")"
cleanup() {
  if [[ -d "$work_dir" ]]; then
    rm -rf -- "$work_dir"
  fi
}
trap cleanup EXIT

if [[ -n "$source_override" ]]; then
  [[ -d "$source_override/SpotPriceWidget.xcodeproj" ]] \
    || fail "SPOT_PRICE_SOURCE_DIR does not contain SpotPriceWidget.xcodeproj"
  source_root="$source_override"
else
  archive="$work_dir/source.tar.gz"
  archive_url="https://github.com/${repository}/archive/refs/heads/${ref}.tar.gz"
  printf 'Downloading %s at %s…\n' "$repository" "$ref"
  curl -fsSL "$archive_url" -o "$archive"
  mkdir -p "$work_dir/source"
  tar -xzf "$archive" -C "$work_dir/source"
  source_root="$(find "$work_dir/source" -mindepth 1 -maxdepth 1 -type d -print -quit)"
  [[ -n "$source_root" && -d "$source_root/SpotPriceWidget.xcodeproj" ]] \
    || fail "downloaded archive does not contain the expected Xcode project"
fi

derived_data="$work_dir/DerivedData"
printf 'Building the macOS app locally…\n'
xcodebuild -quiet \
  -project "$source_root/SpotPriceWidget.xcodeproj" \
  -scheme SpotPriceWidget \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$derived_data" \
  CODE_SIGNING_ALLOWED=NO \
  build

built_app="$derived_data/Build/Products/Release/${app_name}.app"
built_extension="$built_app/Contents/PlugIns/SpotPriceWidgetFinlandExtension.appex"
[[ -d "$built_app" && -d "$built_extension" ]] \
  || fail "build completed without the expected app and widget extension"

codesign --force --sign - \
  --entitlements "$source_root/SpotPriceWidgetFinland/SpotPriceWidgetFinland.entitlements" \
  "$built_extension" >/dev/null
codesign --force --sign - \
  --entitlements "$source_root/SpotPriceWidget/SpotPriceWidget.entitlements" \
  "$built_app" >/dev/null
codesign --verify --deep --strict "$built_app"

mkdir -p "$install_dir"
target_app="$install_dir/${app_name}.app"
backup_app=""
if [[ -e "$target_app" ]]; then
  backup_app="$install_dir/${app_name}.app.backup-$(date +%Y%m%d-%H%M%S)-$$"
  mv "$target_app" "$backup_app"
fi

if ! ditto "$built_app" "$target_app"; then
  if [[ -e "$target_app" ]]; then
    mv "$target_app" "$work_dir/failed-install.app"
  fi
  if [[ -n "$backup_app" && -e "$backup_app" ]]; then
    mv "$backup_app" "$target_app"
  fi
  fail "copy failed; the previous installation was restored"
fi

codesign --verify --deep --strict "$target_app"

unregister_competing_apps "$target_app"

if [[ -x "$lsregister" ]]; then
  "$lsregister" -f -R "$target_app"
fi

installed_extension="$target_app/Contents/PlugIns/SpotPriceWidgetFinlandExtension.appex"
if command -v pluginkit >/dev/null 2>&1; then
  pluginkit -a "$installed_extension" || true
fi

pkill -x NotificationCenter >/dev/null 2>&1 || true
pkill -x chronod >/dev/null 2>&1 || true

printf 'Installed development build at %s\n' "$target_app"
if [[ -n "$backup_app" ]]; then
  printf 'Previous installation backed up at %s\n' "$backup_app"
fi
printf 'Widget bundle registered as %s\n' "$widget_bundle_id"

if [[ "${SPOT_PRICE_SKIP_OPEN:-0}" != "1" ]]; then
  open "$target_app"
fi
