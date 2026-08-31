#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_output="$(mktemp -d "${TMPDIR:-/tmp}/spotprice-maintenance-tests.XXXXXX")"
trap 'rm -rf "$test_output"' EXIT

developer_dir="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
swiftc_path="$(DEVELOPER_DIR="$developer_dir" xcrun --find swiftc)"
sdk_path="$(DEVELOPER_DIR="$developer_dir" xcrun --sdk macosx --show-sdk-path)"
"$swiftc_path" \
  -parse-as-library \
  -sdk "$sdk_path" \
  -module-cache-path "$test_output/ModuleCache" \
  "$repo_root/SpotPriceWidget/ProductMaintenanceLogic.swift" \
  "$repo_root/Tests/ProductMaintenanceLogicTests.swift" \
  -o "$test_output/ProductMaintenanceLogicTests"

"$test_output/ProductMaintenanceLogicTests"
