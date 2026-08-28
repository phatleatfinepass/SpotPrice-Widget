#!/usr/bin/env bash
set -euo pipefail

repository="${SPOT_PRICE_REPOSITORY:-phatleatfinepass/SpotPrice-Widget}"
install_dir="${SPOT_PRICE_INSTALL_DIR:-${HOME}/Applications}"
release_base_url="${SPOT_PRICE_RELEASE_BASE_URL:-https://github.com/${repository}/releases/latest/download}"
app_bundle_name="Finland Electricity Rates.app"
legacy_app_bundle_name="SpotPriceWidget.app"
dmg_name="Finland-Electricity-Rates.dmg"
checksum_name="${dmg_name}.sha256"
widget_bundle_id="personal.SpotPriceWidget.SpotPriceWidgetFinland"

fail() {
  printf 'Finland Electricity Rates installer: %s\n' "$1" >&2
  exit 1
}

case "$install_dir" in
  ""|"/") fail "refusing unsafe install directory: '$install_dir'" ;;
esac

for command_name in curl shasum hdiutil codesign ditto; do
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

printf 'Downloading the latest notarized release…\n'
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

codesign --verify --deep --strict "$source_app" \
  || fail "the downloaded app has an invalid code signature"
spctl --assess --type execute --verbose=2 "$source_app" >/dev/null 2>&1 \
  || fail "Gatekeeper did not accept the downloaded app"

mkdir -p "$install_dir"
target_app="$install_dir/$app_bundle_name"
legacy_app="$install_dir/$legacy_app_bundle_name"
timestamp="$(date +%Y%m%d-%H%M%S)-$$"
target_backup=""
legacy_backup=""

if [[ -e "$target_app" ]]; then
  target_backup="$install_dir/${app_bundle_name}.backup-$timestamp"
  mv "$target_app" "$target_backup"
fi

if [[ -e "$legacy_app" && "$legacy_app" != "$target_app" ]]; then
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
  fail "copy failed; the previous installation was restored"
fi

codesign --verify --deep --strict "$target_app" \
  || fail "the installed app failed signature verification"
spctl --assess --type execute --verbose=2 "$target_app" >/dev/null 2>&1 \
  || fail "the installed app failed Gatekeeper verification"

hdiutil detach "$mount_point" -quiet
mounted=0

lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
if [[ -x "$lsregister" ]]; then
  "$lsregister" -f -R "$target_app"
fi

installed_extension="$target_app/Contents/PlugIns/SpotPriceWidgetFinlandExtension.appex"
if command -v pluginkit >/dev/null 2>&1 && [[ -d "$installed_extension" ]]; then
  pluginkit -a "$installed_extension" || true
fi

printf 'Installed Finland Electricity Rates at %s\n' "$target_app"
if [[ -n "$target_backup" ]]; then
  printf 'Previous installation backed up at %s\n' "$target_backup"
fi
if [[ -n "$legacy_backup" ]]; then
  printf 'Legacy installation backed up at %s\n' "$legacy_backup"
fi
printf 'Widget bundle registered as %s\n' "$widget_bundle_id"

if [[ "${SPOT_PRICE_SKIP_OPEN:-0}" != "1" ]]; then
  open "$target_app"
fi
