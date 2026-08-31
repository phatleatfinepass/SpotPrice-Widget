#!/usr/bin/env bash
set -euo pipefail

app_path="${1:-}"

fail() {
  printf 'Uninstaller integration test failed: %s\n' "$1" >&2
  exit 1
}

[[ -n "$app_path" && -d "$app_path" ]] \
  || fail "pass the path to a signed Debug Finland Electricity Rates.app"

case "$app_path" in
  *.app) ;;
  *) fail "the test input must be an application bundle" ;;
esac

helper_path="$app_path/Contents/XPCServices/SpotPriceWidgetUninstaller.xpc"
[[ -d "$helper_path" ]] || fail "the app does not contain the uninstall helper"

codesign --verify --deep --strict "$app_path" \
  || fail "the input app has an invalid nested signature"

host_entitlements="$(mktemp "${TMPDIR:-/tmp}/spotprice-host-entitlements.XXXXXX")"
helper_entitlements="$(mktemp "${TMPDIR:-/tmp}/spotprice-helper-entitlements.XXXXXX")"
scratch_root="$(mktemp -d "${TMPDIR:-/tmp}/spotprice-uninstall-integration.XXXXXX")"
test_app="$scratch_root/Finland Electricity Rates.app"
output_path="$scratch_root/uninstall-output.txt"
destination_path=""
destination_is_test_artifact=false

cleanup() {
  if [[ "$destination_is_test_artifact" == true && -n "$destination_path" && -e "$destination_path" ]]; then
    rm -rf -- "$destination_path"
  fi
  rm -f -- "$host_entitlements" "$helper_entitlements"
  rm -rf -- "$scratch_root"
}
trap cleanup EXIT

codesign -d --entitlements :- "$app_path" >"$host_entitlements" 2>/dev/null
[[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.app-sandbox' "$host_entitlements" 2>/dev/null || true)" == "true" ]] \
  || fail "the host app is not sandboxed"

codesign -d --entitlements :- "$helper_path" >"$helper_entitlements" 2>/dev/null || true
[[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.app-sandbox' "$helper_entitlements" 2>/dev/null || true)" != "true" ]] \
  || fail "the uninstall helper must not have the app-sandbox entitlement"

ditto "$app_path" "$test_app"

SPOTPRICE_TEST_UNINSTALL=1 "$test_app/Contents/MacOS/SpotPriceWidget" >"$output_path" 2>&1 &
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
  fail "the app did not finish its uninstall request within 30 seconds"
fi
wait "$app_pid" 2>/dev/null || true

if grep -Fq 'UNINSTALL_ERROR=' "$output_path"; then
  sed -n '/UNINSTALL_ERROR=/p' "$output_path" >&2
  fail "the embedded helper rejected or failed the request"
fi

destination_path="$(sed -n 's/^UNINSTALL_DESTINATION=//p' "$output_path" | tail -1)"
if [[ -z "$destination_path" ]]; then
  sed -n '1,120p' "$output_path" >&2
  fail "the app did not report a Trash destination"
fi
[[ ! -e "$test_app" ]] || fail "the disposable app copy still exists at its original path"
[[ -d "$destination_path" ]] || fail "the reported Trash destination does not exist"

trash_root="$(osascript -e 'POSIX path of (path to trash folder)')"
case "$destination_path" in
  "$trash_root"Finland\ Electricity\ Rates*.app) ;;
  *) fail "the helper returned a destination outside the current user’s Trash" ;;
esac

[[ "$(plutil -extract CFBundleIdentifier raw "$destination_path/Contents/Info.plist")" == "personal.SpotPriceWidget" ]] \
  || fail "the helper moved an unexpected application bundle"
destination_is_test_artifact=true

printf 'Uninstaller integration test passed: a disposable signed app moved itself to the Trash.\n'
