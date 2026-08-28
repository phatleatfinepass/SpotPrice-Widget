#!/usr/bin/env bash
set -euo pipefail

repository="${SPOT_PRICE_REPOSITORY:-phatleatfinepass/SpotPrice-Widget}"
install_dir="${SPOT_PRICE_INSTALL_DIR:-${HOME}/Applications}"
release_base_url="${SPOT_PRICE_RELEASE_BASE_URL:-https://github.com/${repository}/releases/latest/download}"
app_bundle_name="Finland Electricity Rates.app"
legacy_app_bundle_name="SpotPriceWidget.app"
dmg_name="Finland-Electricity-Rates.dmg"
checksum_name="${dmg_name}.sha256"
app_bundle_id="personal.SpotPriceWidget"
widget_bundle_id="personal.SpotPriceWidget.SpotPriceWidgetFinland"

fail() {
  printf 'Finland Electricity Rates installer: %s\n' "$1" >&2
  exit 1
}

case "$install_dir" in
  ""|"/") fail "refusing unsafe install directory: '$install_dir'" ;;
esac

for command_name in awk curl shasum hdiutil codesign ditto plutil; do
  command -v "$command_name" >/dev/null 2>&1 \
    || fail "required command is missing: $command_name"
done

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/finland-electricity-rates.XXXXXX")"
mount_point="$work_dir/mount"
mounted=0

cleanup() {
  if [[ "$mounted" == "1" ]]; then
    hdiutil detach "$mount_point" -quiet || true
  fi
  if [[ -d "$work_dir" ]]; then
    rm -rf -- "$work_dir"
  fi
}
trap cleanup EXIT

dmg_path="$work_dir/$dmg_name"
checksum_path="$work_dir/$checksum_name"

printf 'Downloading the latest direct release…\n'
curl -fL --retry 3 --retry-delay 2 "$release_base_url/$dmg_name" -o "$dmg_path"
curl -fL --retry 3 --retry-delay 2 "$release_base_url/$checksum_name" -o "$checksum_path"

expected_checksum="$(awk 'NR == 1 { print $1 }' "$checksum_path")"
actual_checksum="$(shasum -a 256 "$dmg_path" | awk '{ print $1 }')"
[[ -n "$expected_checksum" && "$expected_checksum" == "$actual_checksum" ]] \
  || fail "release checksum verification failed"

mkdir -p "$mount_point"
hdiutil attach "$dmg_path" -nobrowse -readonly -mountpoint "$mount_point" -quiet
mounted=1

source_app="$mount_point/$app_bundle_name"
[[ -d "$source_app" ]] || fail "release does not contain $app_bundle_name"
source_extension="$source_app/Contents/PlugIns/SpotPriceWidgetFinlandExtension.appex"
[[ -d "$source_extension" ]] || fail "release does not contain the Finland widget extension"
[[ "$(plutil -extract CFBundleName raw "$source_app/Contents/Info.plist")" == "Finland Electricity Rates" ]] \
  || fail "release app bundle name is incorrect"
[[ "$(plutil -extract CFBundleDisplayName raw "$source_extension/Contents/Info.plist")" == "Finland Electricity Rates" ]] \
  || fail "release widget display name is incorrect"
[[ -f "$source_app/Contents/Resources/AppIcon.icns" ]] \
  || fail "release does not contain the product icon"

codesign --verify --deep --strict "$source_app" \
  || fail "the downloaded app has an invalid code signature"
gatekeeper_accepted=0
if spctl --assess --type execute --verbose=2 "$source_app" >/dev/null 2>&1; then
  gatekeeper_accepted=1
fi

mkdir -p "$install_dir"
target_app="$install_dir/$app_bundle_name"
legacy_app="$install_dir/$legacy_app_bundle_name"
timestamp="$(date +%Y%m%d-%H%M%S)-$$"
target_backup=""
legacy_backup=""
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

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

pkill -x SpotPriceWidget >/dev/null 2>&1 || true
pkill -x SpotPriceWidgetFinlandExtension >/dev/null 2>&1 || true

if [[ -e "$target_app" ]]; then
  old_extension="$target_app/Contents/PlugIns/SpotPriceWidgetFinlandExtension.appex"
  if command -v pluginkit >/dev/null 2>&1 && [[ -d "$old_extension" ]]; then
    pluginkit -r "$old_extension" >/dev/null 2>&1 || true
  fi
  if [[ -x "$lsregister" ]]; then
    "$lsregister" -u "$target_app" >/dev/null 2>&1 || true
  fi
  target_backup="$install_dir/${app_bundle_name}.backup-$timestamp"
  mv "$target_app" "$target_backup"
fi

if [[ -e "$legacy_app" && "$legacy_app" != "$target_app" ]]; then
  legacy_extension="$legacy_app/Contents/PlugIns/SpotPriceWidgetFinlandExtension.appex"
  if command -v pluginkit >/dev/null 2>&1 && [[ -d "$legacy_extension" ]]; then
    pluginkit -r "$legacy_extension" >/dev/null 2>&1 || true
  fi
  if [[ -x "$lsregister" ]]; then
    "$lsregister" -u "$legacy_app" >/dev/null 2>&1 || true
  fi
  legacy_backup="$install_dir/${legacy_app_bundle_name}.backup-$timestamp"
  mv "$legacy_app" "$legacy_backup"
fi

if ! ditto "$source_app" "$target_app"; then
  if [[ -e "$target_app" ]]; then
    mv "$target_app" "$work_dir/failed-install.app"
  fi
  if [[ -n "$target_backup" && -e "$target_backup" ]]; then
    mv "$target_backup" "$target_app"
  fi
  if [[ -n "$legacy_backup" && -e "$legacy_backup" ]]; then
    mv "$legacy_backup" "$legacy_app"
  fi
  for restored_app in "$target_app" "$legacy_app"; do
    if [[ -d "$restored_app" ]]; then
      if [[ -x "$lsregister" ]]; then
        "$lsregister" -f -R "$restored_app" >/dev/null 2>&1 || true
      fi
      restored_extension="$restored_app/Contents/PlugIns/SpotPriceWidgetFinlandExtension.appex"
      if command -v pluginkit >/dev/null 2>&1 && [[ -d "$restored_extension" ]]; then
        pluginkit -a "$restored_extension" >/dev/null 2>&1 || true
      fi
    fi
  done
  fail "copy failed; the previous installation was restored"
fi

codesign --verify --deep --strict "$target_app" \
  || fail "the installed app failed signature verification"

unregister_competing_apps "$target_app"

hdiutil detach "$mount_point" -quiet
mounted=0

if [[ -x "$lsregister" ]]; then
  "$lsregister" -f -R "$target_app"
fi

installed_extension="$target_app/Contents/PlugIns/SpotPriceWidgetFinlandExtension.appex"
if command -v pluginkit >/dev/null 2>&1 && [[ -d "$installed_extension" ]]; then
  while IFS= read -r registered_extension; do
    if [[ "$registered_extension" == /* && "$registered_extension" != "$installed_extension" ]]; then
      pluginkit -r "$registered_extension" >/dev/null 2>&1 || true
    fi
  done < <(pluginkit -m -A -D -v -i "$widget_bundle_id" 2>/dev/null | awk -F '\t' 'NF >= 4 { print $NF }')
  pluginkit -a "$installed_extension"
  registered_extension="$(pluginkit -m -A -D -v -i "$widget_bundle_id" 2>/dev/null | awk -F '\t' 'NF >= 4 { print $NF; exit }')"
  [[ "$registered_extension" == "$installed_extension" ]] \
    || fail "WidgetKit registered an unexpected extension path: ${registered_extension:-none}"
fi

pkill -x NotificationCenter >/dev/null 2>&1 || true
pkill -x chronod >/dev/null 2>&1 || true

printf 'Installed Finland Electricity Rates at %s\n' "$target_app"
if [[ -n "$target_backup" ]]; then
  printf 'Previous installation backed up at %s\n' "$target_backup"
fi
if [[ -n "$legacy_backup" ]]; then
  printf 'Legacy installation backed up at %s\n' "$legacy_backup"
fi
printf 'Widget bundle registered as %s\n' "$widget_bundle_id"

if [[ "$gatekeeper_accepted" == "0" ]]; then
  printf '\nThis free direct release is ad-hoc signed and is not Apple-notarized.\n'
  printf 'On first launch, macOS may block it as an unidentified developer app.\n'
  printf 'To approve this exact app: try opening it once, then open System Settings > Privacy & Security and select Open Anyway.\n'
  printf 'The installer does not disable Gatekeeper or remove macOS quarantine protection.\n\n'
fi

if [[ "${SPOT_PRICE_SKIP_OPEN:-0}" != "1" ]]; then
  open "$target_app"
fi
