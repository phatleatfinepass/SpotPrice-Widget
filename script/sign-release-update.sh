#!/usr/bin/env bash
set -euo pipefail
set +x

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
artifact_path="${1:-$repo_root/dist/Finland-Electricity-Rates.dmg}"
signature_path="${artifact_path}.sig"
sign_tool="${SPOT_PRICE_SIGN_UPDATE_TOOL:-}"
keychain_account="${SPOT_PRICE_UPDATE_SIGNING_ACCOUNT:-}"

[[ -f "$artifact_path" ]] || { printf 'Missing update artifact: %s\n' "$artifact_path" >&2; exit 1; }
[[ -x "$sign_tool" ]] || { printf 'SPOT_PRICE_SIGN_UPDATE_TOOL must name Sparkle sign_update 2.9.6.\n' >&2; exit 1; }

temporary_signature="$(mktemp "${TMPDIR:-/tmp}/spotprice-update-signature.XXXXXX")"
cleanup() {
  rm -f -- "$temporary_signature"
}
trap cleanup EXIT

if [[ -n "${SPOT_PRICE_UPDATE_PRIVATE_KEY:-}" ]]; then
  printf '%s' "$SPOT_PRICE_UPDATE_PRIVATE_KEY" \
    | "$sign_tool" --ed-key-file - -p "$artifact_path" >"$temporary_signature"
  unset SPOT_PRICE_UPDATE_PRIVATE_KEY
elif [[ -n "$keychain_account" ]]; then
  "$sign_tool" --account "$keychain_account" -p "$artifact_path" >"$temporary_signature"
else
  printf 'Provide the private key through SPOT_PRICE_UPDATE_PRIVATE_KEY or a local Keychain account.\n' >&2
  exit 1
fi

mv "$temporary_signature" "$signature_path"
trap - EXIT
"$repo_root/script/verify-update-signature.sh" "$artifact_path" "$signature_path"
printf 'Signed update artifact: %s\n' "$signature_path"
