#!/bin/zsh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
test_output="$(mktemp -d "${TMPDIR:-/tmp}/spotprice-update-handoff.XXXXXX")"
trap 'rm -rf "$test_output"' EXIT

developer_dir="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
swiftc_path="$(DEVELOPER_DIR="$developer_dir" xcrun --find swiftc)"
sdk_path="$(DEVELOPER_DIR="$developer_dir" xcrun --sdk macosx --show-sdk-path)"
"$swiftc_path" \
  -parse-as-library \
  -sdk "$sdk_path" \
  -module-cache-path "$test_output/ModuleCache" \
  "$repo_root/SpotPriceWidgetUninstaller/UpdateHostLifecycle.swift" \
  "$repo_root/SpotPriceWidgetUninstaller/WidgetRegistrationPaths.swift" \
  "$repo_root/Tests/UpdateHostLifecycleTests.swift" \
  -o "$test_output/UpdateHostLifecycleTests"

"$test_output/UpdateHostLifecycleTests"
