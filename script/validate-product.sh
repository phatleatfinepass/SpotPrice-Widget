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
  "$repo_root/script/package-release.sh" \
  "$repo_root/script/sign-release-update.sh" \
  "$repo_root/script/test-grid-conditions.sh" \
  "$repo_root/script/test-product-maintenance.sh" \
  "$repo_root/script/test-software-update.sh" \
  "$repo_root/script/test-update-handoff.sh" \
  "$repo_root/script/test-uninstaller-integration.sh" \
  "$repo_root/script/test-uninstaller-target.sh" \
  "$repo_root/script/verify-update-signature.sh" \
  "$repo_root/script/verify-grid-emissions-relay.sh"; do
  bash -n "$script_path" || fail "invalid shell syntax in $script_path"
done

versions="$(awk -F ' = ' '/MARKETING_VERSION = / { gsub(/;/, "", $2); print $2 }' "$project_file" | sort -u)"
version_count="$(printf '%s\n' "$versions" | awk 'NF { count += 1 } END { print count + 0 }')"
[[ "$version_count" == "1" ]] || fail "all app targets must use the same marketing version"
[[ "$versions" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
  || fail "marketing version must use semantic versioning"

build_versions="$(awk -F ' = ' '/CURRENT_PROJECT_VERSION = / { gsub(/;/, "", $2); print $2 }' "$project_file" | sort -u)"
build_version_count="$(printf '%s\n' "$build_versions" | awk 'NF { count += 1 } END { print count + 0 }')"
[[ "$build_version_count" == "1" && "$build_versions" =~ ^[0-9]+$ ]] \
  || fail "all app targets must use one numeric build version"

product_name_count="$(grep -Fc 'PRODUCT_NAME = "Finland Electricity Rates";' "$project_file" || true)"
executable_name_count="$(grep -Fc 'EXECUTABLE_NAME = SpotPriceWidget;' "$project_file" || true)"
[[ "$product_name_count" == "2" && "$executable_name_count" == "2" ]] \
  || fail "the host app must use the product-facing bundle name and stable executable name"

for required_path in \
  "$repo_root/Shared/PrivacyInfo.xcprivacy" \
  "$repo_root/Shared/WidgetDataStore.swift" \
  "$repo_root/PRIVACY.md" \
  "$repo_root/SUPPORT.md" \
  "$repo_root/CHANGELOG.md" \
  "$repo_root/docs/RELEASE.md" \
  "$repo_root/docs/DIRECT-DISTRIBUTION.txt" \
  "$repo_root/docs/RELEASE-NOTES.md" \
  "$repo_root/SpotPriceWidget/ProductMaintenanceLogic.swift" \
  "$repo_root/SpotPriceWidget/ProductManagementSections.swift" \
  "$repo_root/SpotPriceWidget/SoftwareUpdateConfiguration.swift" \
  "$repo_root/SpotPriceWidget/SoftwareUpdateService.swift" \
  "$repo_root/SpotPriceWidgetUninstaller/Info.plist" \
  "$repo_root/SpotPriceWidgetUninstaller/UninstallSecurity.swift" \
  "$repo_root/SpotPriceWidgetUninstaller/UninstallServiceProtocol.swift" \
  "$repo_root/SpotPriceWidgetUninstaller/UninstallTarget.swift" \
  "$repo_root/SpotPriceWidgetUninstaller/UpdateHostLifecycle.swift" \
  "$repo_root/SpotPriceWidgetUninstaller/UpdateInstaller.swift" \
  "$repo_root/SpotPriceWidgetUninstaller/UpdateTrust.swift" \
  "$repo_root/SpotPriceWidgetUninstaller/WidgetRegistrationPaths.swift" \
  "$repo_root/SpotPriceWidgetUninstaller/main.swift" \
  "$repo_root/script/test-update-handoff.sh" \
  "$repo_root/script/sign-release-update.sh" \
  "$repo_root/script/verify-update-signature.sh" \
  "$repo_root/script/verify-update-signature.swift" \
  "$repo_root/backend/grid-emissions-relay/package-lock.json" \
  "$repo_root/backend/grid-emissions-relay/src/index.ts" \
  "$repo_root/backend/grid-emissions-relay/wrangler.jsonc"; do
  [[ -f "$required_path" ]] || fail "missing required product file: $required_path"
done

plutil -lint "$repo_root/Shared/PrivacyInfo.xcprivacy" >/dev/null
plutil -lint "$repo_root/SpotPriceWidget/SpotPriceWidget.entitlements" >/dev/null
plutil -lint "$repo_root/SpotPriceWidgetFinland/SpotPriceWidgetFinland.entitlements" >/dev/null
plutil -lint "$repo_root/SpotPriceWidgetUninstaller/Info.plist" >/dev/null

if grep -Fq 'com.apple.security.application-groups' \
  "$repo_root/SpotPriceWidget/SpotPriceWidget.entitlements" \
  "$repo_root/SpotPriceWidgetFinland/SpotPriceWidgetFinland.entitlements"; then
  fail "the ad-hoc direct build must not declare an unavailable App Group"
fi
if grep -Fq 'com.apple.security.files.user-selected.read-write' \
  "$repo_root/SpotPriceWidget/SpotPriceWidget.entitlements"; then
  fail "the host must not retain user-selected file access after moving uninstall into the bounded helper"
fi

[[ "$(grep -Fc 'ENABLE_APP_SANDBOX = YES;' "$project_file")" == "4" ]] \
  || fail "the host and widget targets must remain sandboxed in Debug and Release"
[[ "$(grep -Fc 'ENABLE_APP_SANDBOX = NO;' "$project_file")" == "2" ]] \
  || fail "only the uninstall helper may run outside the app sandbox"
grep -Fq 'productType = "com.apple.product-type.xpc-service";' "$project_file" \
  || fail "the project must include the XPC uninstall service target"
grep -Fq 'dstPath = "$(CONTENTS_FOLDER_PATH)/XPCServices";' "$project_file" \
  || fail "the host must embed the helper only in Contents/XPCServices"

grep -Fq 'https://api.github.com/repos/phatleatfinepass/SpotPrice-Widget/releases/latest' \
  "$repo_root/SpotPriceWidget/SoftwareUpdateConfiguration.swift" \
  || fail "the in-app updater must check the fixed official repository"
grep -Fq 'Finland-Electricity-Rates.dmg.sig' \
  "$repo_root/SpotPriceWidget/SoftwareUpdateService.swift" \
  || fail "the updater must require an Ed25519 signature asset"
grep -Fq 'Curve25519.Signing.PublicKey' \
  "$repo_root/SpotPriceWidget/SoftwareUpdateConfiguration.swift" \
  || fail "the sandboxed host must verify the update signature"
grep -Fq 'ProductUpdaterClient.install' \
  "$repo_root/SpotPriceWidget/SoftwareUpdateService.swift" \
  || fail "the sandboxed host must delegate replacement to the bounded helper"
grep -Fq 'UpdateTrust.verify' \
  "$repo_root/SpotPriceWidgetUninstaller/UpdateInstaller.swift" \
  || fail "the update helper must independently verify the update signature"
grep -Fq 'kSecCSCheckNestedCode' \
  "$repo_root/SpotPriceWidgetUninstaller/UpdateInstaller.swift" \
  || fail "the update helper must validate the complete nested signature tree"
host_update_key="$(sed -n 's/.*publicKeyBase64 = "\([^"]*\)".*/\1/p' "$repo_root/SpotPriceWidget/SoftwareUpdateConfiguration.swift")"
helper_update_key="$(sed -n 's/.*publicKeyBase64 = "\([^"]*\)".*/\1/p' "$repo_root/SpotPriceWidgetUninstaller/UpdateTrust.swift")"
[[ -n "$host_update_key" && "$host_update_key" == "$helper_update_key" ]] \
  || fail "the host and helper must pin the same update-signing public key"
grep -Fq 'ProductUninstallerClient.moveContainingAppToTrash' \
  "$repo_root/SpotPriceWidget/ProductManagementSections.swift" \
  || fail "the sandboxed host must delegate uninstall to the embedded XPC service"
if grep -Fq 'NSOpenPanel' "$repo_root/SpotPriceWidget/ProductManagementSections.swift"; then
  fail "uninstall must not require a user-selected app path"
fi
grep -Fq 'NSWorkspace.shared.recycle([appURL])' \
  "$repo_root/SpotPriceWidgetUninstaller/main.swift" \
  || fail "the helper must use Finder-compatible Trash semantics"
grep -Fq 'func moveContainingAppToTrash(' \
  "$repo_root/SpotPriceWidgetUninstaller/UninstallServiceProtocol.swift" \
  || fail "the helper protocol must expose only its fixed containing-app operation"
grep -Fq 'connection.effectiveUserIdentifier == geteuid()' \
  "$repo_root/SpotPriceWidgetUninstaller/UninstallSecurity.swift" \
  || fail "the helper must reject callers from another user"
grep -Fq 'kSecCodeInfoIdentifier' \
  "$repo_root/SpotPriceWidgetUninstaller/UninstallSecurity.swift" \
  || fail "the helper must verify the caller’s signing identifier"
grep -Fq 'callerAppURL' \
  "$repo_root/SpotPriceWidgetUninstaller/UninstallSecurity.swift" \
  || fail "the helper must verify that its caller is the exact containing app"
if grep -Eq 'moveContainingAppToTrash\([^)]*(path|url|URL)' \
  "$repo_root/SpotPriceWidgetUninstaller/UninstallServiceProtocol.swift"; then
  fail "the helper protocol must never accept an arbitrary filesystem target"
fi

if git -C "$repo_root" grep -En \
  '(FINGRID_API_KEY|x-api-key)[[:space:]]*[:=][[:space:]]*[A-Za-z0-9_-]{16,}' \
  -- . ':(exclude)*.png' ':(exclude)SpotPriceWidget.xcodeproj/project.pbxproj' \
  >/dev/null; then
  fail "a credential-shaped Fingrid value appears in the repository"
fi

grep -Fq '<key>GridEmissionsRelayURL</key>' \
  "$repo_root/SpotPriceWidgetFinland/Info.plist" \
  || fail "the widget extension must declare its public emissions relay"
grep -Fq '.dev.vars' "$repo_root/.gitignore" \
  || fail "local Worker secret files must be ignored"
grep -Fq 'node_modules/' "$repo_root/.gitignore" \
  || fail "Worker dependencies must not be committed"

grep -Fq 'distribution="${SPOT_PRICE_DISTRIBUTION:-direct}"' \
  "$repo_root/script/package-release.sh" \
  || fail "release packaging must default to direct distribution"
grep -Fq 'staged_uninstaller="$staged_app/Contents/XPCServices/SpotPriceWidgetUninstaller.xpc"' \
  "$repo_root/script/package-release.sh" \
  || fail "release packaging must validate and sign the embedded uninstall helper"
grep -Fq -- '--identifier personal.SpotPriceWidget.Uninstaller' \
  "$repo_root/script/package-release.sh" \
  || fail "release packaging must pin the helper signing identifier"
grep -Eq 'SPOT_PRICE_DISTRIBUTION: direct' \
  "$repo_root/.github/workflows/release.yml" \
  || fail "the public release workflow must explicitly select direct distribution"
grep -Fq 'ENABLE_DEBUG_DYLIB="$DEBUG_DYLIB_FOR_PLATFORM"' \
  "$repo_root/.github/workflows/ci.yml" \
  || fail "the macOS integration build must avoid an ad-hoc Hardened Runtime Debug dylib"
grep -Fq 'ENABLE_DEBUG_DYLIB=NO' \
  "$repo_root/.github/workflows/release.yml" \
  || fail "the release-gate integration build must avoid an ad-hoc Hardened Runtime Debug dylib"
grep -Fq 'SPOT_PRICE_UPDATE_PRIVATE_KEY: ${{ secrets.SPOT_PRICE_UPDATE_PRIVATE_KEY }}' \
  "$repo_root/.github/workflows/release.yml" \
  || fail "the release workflow must read the update private key only from the provider secret store"
grep -Fq 'dist/Finland-Electricity-Rates.dmg.sig' \
  "$repo_root/.github/workflows/release.yml" \
  || fail "the public release workflow must publish the detached update signature"
grep -Fq 'SparkleUpdateTools/bin/sign_update' \
  "$repo_root/.github/workflows/release.yml" \
  || fail "the release workflow must use the verified archive's actual signing-tool path"
grep -Fq -- '--repo "$GITHUB_REPOSITORY"' \
  "$repo_root/.github/workflows/release.yml" \
  || fail "the checkout-free publisher must name its GitHub repository explicitly"

for installer_path in \
  "$repo_root/script/install.sh" \
  "$repo_root/script/install-from-source.sh"; do
  grep -Fq 'unregister_competing_apps "$target_app"' "$installer_path" \
    || fail "installers must remove competing Launch Services registrations"
done

update_reply_line="$(grep -nF 'reply(preparedUpdate.expectedVersion, nil)' \
  "$repo_root/SpotPriceWidgetUninstaller/main.swift" | cut -d: -f1)"
update_commit_line="$(grep -nF '_ = try await UpdateInstaller.commit(' \
  "$repo_root/SpotPriceWidgetUninstaller/main.swift" | cut -d: -f1)"
[[ -n "$update_reply_line" && -n "$update_commit_line" && "$update_reply_line" -lt "$update_commit_line" ]] \
  || fail "the updater must hand control back to the host before committing the replacement"

host_exit_line="$(grep -nF 'try await UpdateHostLifecycle.waitForExit' \
  "$repo_root/SpotPriceWidgetUninstaller/UpdateInstaller.swift" | cut -d: -f1)"
replacement_line="$(grep -nF 'try fileManager.moveItem(at: prepared.currentApp, to: prepared.backupApp)' \
  "$repo_root/SpotPriceWidgetUninstaller/UpdateInstaller.swift" | cut -d: -f1)"
[[ -n "$host_exit_line" && -n "$replacement_line" && "$host_exit_line" -lt "$replacement_line" ]] \
  || fail "the updater must wait for the authenticated host to exit before replacing its bundle"

grep -Fq 'try UpdateRegistration.register(appURL: prepared.currentApp)' \
  "$repo_root/SpotPriceWidgetUninstaller/UpdateInstaller.swift" \
  || fail "the updater must register the replacement widget before relaunching"

if git -C "$repo_root" grep -En \
  '(spctl[[:space:]]+--master-disable|xattr[[:space:]]+-[a-zA-Z]*d[^[:space:]]*[[:space:]]+com\.apple\.quarantine)' \
  -- script docs README.md >/dev/null; then
  fail "installation materials must not disable Gatekeeper or remove quarantine"
fi

printf 'Product metadata and release scripts are valid.\n'
