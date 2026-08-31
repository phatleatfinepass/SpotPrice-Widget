#!/usr/bin/env bash
set -euo pipefail

relay_url="${1:-}"

fail() {
  printf 'Grid-emissions relay verification failed: %s\n' "$1" >&2
  exit 1
}

[[ "$relay_url" =~ ^https://[A-Za-z0-9.-]+/v1/finland/emissions/current$ ]] \
  || fail "expected the fixed HTTPS current-emissions endpoint"

for command_name in curl mktemp plutil; do
  command -v "$command_name" >/dev/null 2>&1 \
    || fail "required command is missing: $command_name"
done

payload_file="$(mktemp "${TMPDIR:-/tmp}/spotprice-relay-response.XXXXXX")"
cleanup() {
  rm -f -- "$payload_file"
}
trap cleanup EXIT

curl --fail --silent --show-error \
  --retry 3 \
  --retry-all-errors \
  --connect-timeout 10 \
  --max-time 30 \
  --output "$payload_file" \
  "$relay_url"

plutil -convert xml1 "$payload_file" >/dev/null \
  || fail "response is not valid JSON"

dataset_id="$(plutil -extract datasetId raw "$payload_file" 2>/dev/null || true)"
schema_version="$(plutil -extract schemaVersion raw "$payload_file" 2>/dev/null || true)"
unit="$(plutil -extract unit raw "$payload_file" 2>/dev/null || true)"
value="$(plutil -extract value raw "$payload_file" 2>/dev/null || true)"
measurement_end="$(plutil -extract measurementEnd raw "$payload_file" 2>/dev/null || true)"
stale="$(plutil -extract stale raw "$payload_file" 2>/dev/null || true)"

[[ "$schema_version" == "1" ]] || fail "unexpected schema version"
[[ "$dataset_id" == "396" ]] || fail "unexpected dataset"
[[ "$unit" == "gCO2/kWh" ]] || fail "unexpected unit"
[[ "$value" =~ ^[0-9]+([.][0-9]+)?$ ]] || fail "missing numeric emissions value"
[[ -n "$measurement_end" ]] || fail "missing measurement timestamp"
[[ "$stale" == "false" ]] || fail "relay has not produced a fresh measurement"

printf 'Grid-emissions relay returned dataset 396 with a live payload.\n'
