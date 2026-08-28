#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
project_file="$repo_root/SpotPriceWidget.xcodeproj/project.pbxproj"

fail() {
  printf 'Product validation failed: %s\n' "$1" >&2
  exit 1
}

for command_name in awk bash git grep plutil sort; do
  command -v "$command_name" >/dev/null 2>&1 \
    || fail "required validation command is missing: $command_name"
done

for script_path in \
  "$repo_root/script/install.sh" \
  "$repo_root/script/install-from-source.sh" \
  "$repo_root/script/package-release.sh"; do
  bash -n "$script_path" || fail "invalid shell syntax in $script_path"
done

versions="$(awk -F ' = ' '/MARKETING_VERSION = / { gsub(/;/, "", $2); print $2 }' "$project_file" | sort -u)"
version_count="$(printf '%s\n' "$versions" | awk 'NF { count += 1 } END { print count + 0 }')"
[[ "$version_count" == "1" ]] || fail "all app targets must use the same marketing version"
[[ "$versions" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
  || fail "marketing version must use semantic versioning"

for required_path in \
  "$repo_root/Shared/PrivacyInfo.xcprivacy" \
  "$repo_root/PRIVACY.md" \
  "$repo_root/SUPPORT.md" \
  "$repo_root/CHANGELOG.md" \
  "$repo_root/docs/RELEASE.md" \
  "$repo_root/docs/DIRECT-DISTRIBUTION.txt" \
  "$repo_root/docs/RELEASE-NOTES.md"; do
  [[ -f "$required_path" ]] || fail "missing required product file: $required_path"
done

plutil -lint "$repo_root/Shared/PrivacyInfo.xcprivacy" >/dev/null
plutil -lint "$repo_root/SpotPriceWidget/SpotPriceWidget.entitlements" >/dev/null
plutil -lint "$repo_root/SpotPriceWidgetFinland/SpotPriceWidgetFinland.entitlements" >/dev/null

if git -C "$repo_root" grep -En \
  '(FINGRID_API_KEY|x-api-key)[[:space:]]*[:=][[:space:]]*[A-Za-z0-9_-]{16,}' \
  -- . ':(exclude)*.png' ':(exclude)SpotPriceWidget.xcodeproj/project.pbxproj' \
  >/dev/null; then
  fail "a credential-shaped Fingrid value appears in the repository"
fi

grep -Fq 'distribution="${SPOT_PRICE_DISTRIBUTION:-direct}"' \
  "$repo_root/script/package-release.sh" \
  || fail "release packaging must default to direct distribution"
grep -Eq 'SPOT_PRICE_DISTRIBUTION: direct' \
  "$repo_root/.github/workflows/release.yml" \
  || fail "the public release workflow must explicitly select direct distribution"

if git -C "$repo_root" grep -En \
  '(spctl[[:space:]]+--master-disable|xattr[[:space:]]+-[a-zA-Z]*d[^[:space:]]*[[:space:]]+com\.apple\.quarantine)' \
  -- script docs README.md >/dev/null; then
  fail "installation materials must not disable Gatekeeper or remove quarantine"
fi

printf 'Product metadata and release scripts are valid.\n'
