#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
artifact_path="${1:-}"
signature_path="${2:-${artifact_path}.sig}"

[[ -f "$artifact_path" ]] || { printf 'Missing update artifact: %s\n' "$artifact_path" >&2; exit 1; }
[[ -f "$signature_path" ]] || { printf 'Missing update signature: %s\n' "$signature_path" >&2; exit 1; }

module_cache="$(mktemp -d "${TMPDIR:-/tmp}/spotprice-update-signature.XXXXXX")"
cleanup() {
  rm -rf -- "$module_cache"
}
trap cleanup EXIT

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

xcrun swift \
  -module-cache-path "$module_cache" \
  "$repo_root/script/verify-update-signature.swift" \
  "$artifact_path" \
  "$signature_path"
