#!/usr/bin/env bash
set -euo pipefail

# Run against the installed signed app with both desktop widgets already added.
# This test opens the real app normally. It never changes extension registration,
# resets data, restarts widget services, or replaces an application bundle.
app_path="${1:-}"
widget_bundle_id="personal.SpotPriceWidget.SpotPriceWidgetFinland"
fail() { printf 'Widget startup integration test failed: %s\n' "$1" >&2; exit 1; }
[[ -n "$app_path" && -d "$app_path" && "$app_path" == /*.app ]] \
  || fail "pass the absolute path to the installed signed app with both widgets added"
codesign --verify --deep --strict "$app_path" || fail "invalid nested app signature"
app_path="$(cd "$app_path" && pwd -P)"
app_executable="$app_path/Contents/MacOS/SpotPriceWidget"
widget_extension="$app_path/Contents/PlugIns/SpotPriceWidgetFinlandExtension.appex"
widget_executable="$widget_extension/Contents/MacOS/SpotPriceWidgetFinlandExtension"
test_output="$(mktemp -d "${TMPDIR:-/tmp}/spotprice-widget-startup.XXXXXX")"
trap 'rm -rf -- "$test_output"' EXIT

exact_pids() {
  ps -axo pid=,comm= | awk -v executable="$1" '
    { pid=$1; sub(/^[[:space:]]*[0-9]+[[:space:]]+/, ""); if ($0 == executable) print pid }
  '
}
registration_uuid() {
  pluginkit -m -A -D -v -i "$widget_bundle_id" 2>/dev/null \
    | awk -F '\t' -v expected="$widget_extension" 'NF>=4 {records++; if ($NF == expected) uuid=$2} END {if (records==1 && uuid!="") print uuid}'
}
quit_host() {
  local pid
  for pid in $(exact_pids "$app_executable"); do kill -TERM "$pid"; done
  for _ in {1..40}; do
    [[ -z "$(exact_pids "$app_executable")" ]] && return
    sleep 0.25
  done
  fail "the exact host app did not exit"
}

# Allow one-time build preparation to finish before measuring healthy relaunches.
quit_host
open -n -a "$app_path"
sleep 15
for launch_number in 1 2; do
  quit_host
  start_time="$(date '+%Y-%m-%d %H:%M:%S')"
  # Resolve the already registered host, as Launchpad or Spotlight would.
  # Reopening by file URL can cause LS to replace its record in a multi-copy test.
  open -n -b personal.SpotPriceWidget
  # Launch Services can create a fresh trusted record while opening the host.
  # Measure the old five-second repair window after that normal registration.
  sleep 2
  [[ -n "$(exact_pids "$app_executable")" ]] || fail "the exact candidate host did not launch"
  original_uuid="$(registration_uuid)"
  [[ -n "$original_uuid" && "$original_uuid" != *$'\n'* ]] || fail "canonical registration is not unique"
  widget_pid="$(exact_pids "$widget_executable" | head -1)"
  [[ -n "$widget_pid" ]] || fail "WidgetKit is not running the tested extension; check its selected app path"
  sleep 13
  [[ "$(registration_uuid)" == "$original_uuid" ]] || fail "startup replaced the widget registration"
  exact_pids "$widget_executable" | grep -Fxq "$widget_pid" || fail "startup did not preserve the resident widget process"
  /usr/bin/log show --start "$start_time" --style compact --info \
    --predicate "(subsystem == 'personal.SpotPriceWidget' AND category == 'WidgetStartup') OR ((process == 'chronod' OR process == 'NotificationCenter') AND eventMessage CONTAINS 'personal.SpotPriceWidget') OR (processID == $widget_pid AND subsystem == 'com.apple.chrono' AND category == 'timeline')" \
    > "$test_output/launch-$launch_number.log"
  log_path="$test_output/launch-$launch_number.log"
  grep -Fq 'Requested widget timelines; registration preserved' "$log_path" || fail "startup reload was not observed"
  if grep -E 'Prepared widget process|Widget build preparation failed|extensionNotFound|Unknown extension process|Unable to find this application extension record|Mandatory reload failed|reload: failed' "$log_path"; then
    fail "healthy startup disrupted the widget"
  fi
  for kind in FinlandSpotElectricityRates FinlandGridForecast; do
    grep -Eq "SpotPriceWidgetFinlandExtension\[$widget_pid:.*Request ended for $kind:.*success" "$log_path" || fail "no successful $kind provider result from the exact candidate PID"
    grep -Eq "$kind.*reload: succeeded" "$log_path" || fail "no fresh timeline observed for $kind"
  done
  printf 'Launch %s: registration %s and widget PID %s preserved; both timelines refreshed.\n' "$launch_number" "$original_uuid" "$widget_pid"
  # Compact native evidence remains in the calling managed validation log.
  grep -E 'Requested widget timelines; registration preserved|reload: succeeded|Content load successful' "$log_path"
done
printf 'Widget startup integration passed without uninstall, reinstall, data reset, or widget-service restart.\n'
