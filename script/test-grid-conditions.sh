#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_output="$(mktemp -d "${TMPDIR:-/tmp}/spotprice-grid-tests.XXXXXX")"
trap 'rm -rf "$test_output"' EXIT

developer_dir="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
swiftc_path="$(DEVELOPER_DIR="$developer_dir" xcrun --find swiftc)"
sdk_path="$(DEVELOPER_DIR="$developer_dir" xcrun --sdk macosx --show-sdk-path)"
"$swiftc_path" \
  -parse-as-library \
  -sdk "$sdk_path" \
  -module-cache-path "$test_output/ModuleCache" \
  "$repo_root/Shared/WidgetDataStore.swift" \
  "$repo_root/Shared/SpotPriceCore.swift" \
  "$repo_root/Shared/FinlandTime.swift" \
  "$repo_root/Shared/GridEmissionsCore.swift" \
  "$repo_root/Shared/FinlandRenewableBaseline.swift" \
  "$repo_root/Shared/GridForecastCore.swift" \
  "$repo_root/Shared/GridConditionsCore.swift" \
  "$repo_root/Tests/GridConditionsSignalTests.swift" \
  -o "$test_output/GridConditionsSignalTests"

"$test_output/GridConditionsSignalTests"
