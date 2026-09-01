#!/usr/bin/env bash
set -euo pipefail

app_path="${1:-}"
widget_bundle_id="personal.SpotPriceWidget.SpotPriceWidgetFinland"
lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

fail() {
  printf 'Widget registration integration test failed: %s\n' "$1" >&2
  exit 1
}

[[ -n "$app_path" && -d "$app_path" && "$app_path" == *.app ]] \
  || fail "pass the path to a signed Debug Finland Electricity Rates.app"
codesign --verify --deep --strict "$app_path" \
  || fail "the input app has an invalid nested signature"

scratch_root="$(mktemp -d "${TMPDIR:-/tmp}/spotprice-widget-registration.XXXXXX")"
test_app="$scratch_root/Finland Electricity Rates.app"
test_executable="$test_app/Contents/MacOS/SpotPriceWidget"
test_extension="$test_app/Contents/PlugIns/SpotPriceWidgetFinlandExtension.appex"
output_path="$scratch_root/registration-output.txt"
original_paths="$scratch_root/original-registration-paths.txt"

registered_extension_paths() {
  pluginkit -m -A -D -v -i "$widget_bundle_id" 2>/dev/null \
    | awk -F '\t' 'NF >= 4 { print $NF }'
}

canonical_path() {
  local input_path="$1"
  local parent_path
  parent_path="$(cd "$(dirname "$input_path")" && pwd -P)"
  printf '%s/%s\n' "$parent_path" "$(basename "$input_path")"
}

registered_extension_paths >"$original_paths"

cleanup() {
  while IFS= read -r process_line; do
    process_id="${process_line%% *}"
    process_command="${process_line#* }"
    if [[ "$process_id" =~ ^[0-9]+$ && "$process_command" == "$test_executable" ]]; then
      kill "$process_id" 2>/dev/null || true
    fi
  done < <(ps -axo pid=,command= | sed -E 's/^[[:space:]]+//')

  pluginkit -r "$test_extension" >/dev/null 2>&1 || true
  "$lsregister" -u "$test_app" >/dev/null 2>&1 || true

  while IFS= read -r original_extension; do
    if [[ "$original_extension" == /* && -d "$original_extension" ]]; then
      original_app="$(dirname "$(dirname "$(dirname "$original_extension")")")"
      if [[ -d "$original_app" ]]; then
        "$lsregister" -f -R "$original_app" >/dev/null 2>&1 || true
        pluginkit -a "$original_extension" >/dev/null 2>&1 || true
      fi
    fi
  done <"$original_paths"

  rm -rf -- "$scratch_root"
}
trap cleanup EXIT

ditto "$app_path" "$test_app"

SPOTPRICE_TEST_WIDGET_REGISTRATION=1 "$test_executable" >"$output_path" 2>&1 &
app_pid=$!

for _ in {1..120}; do
  if ! kill -0 "$app_pid" 2>/dev/null; then
    break
  fi
  sleep 0.25
done

if kill -0 "$app_pid" 2>/dev/null; then
  kill "$app_pid" 2>/dev/null || true
  wait "$app_pid" 2>/dev/null || true
  sed -n '1,120p' "$output_path" >&2
  fail "the app did not finish its registration request within 30 seconds"
fi
wait "$app_pid" 2>/dev/null || true

if grep -Fq 'WIDGET_REGISTRATION_ERROR=' "$output_path"; then
  sed -n '/WIDGET_REGISTRATION_ERROR=/p' "$output_path" >&2
  fail "the embedded helper rejected or failed the registration request"
fi
grep -Fq 'WIDGET_REGISTRATION_REPAIRED=1' "$output_path" \
  || fail "the app did not report a completed registration repair"

registered_path="$(registered_extension_paths | head -1)"
[[ -n "$registered_path" && "$(canonical_path "$registered_path")" == "$(canonical_path "$test_extension")" ]] \
  || fail "WidgetKit registered an unexpected path: ${registered_path:-none}"

printf 'Widget registration integration test passed for the exact containing app.\n'
