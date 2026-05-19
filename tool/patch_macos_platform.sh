#!/usr/bin/env bash
set -euo pipefail

runner_dir="macos/Runner"
project_file="macos/Runner.xcodeproj/project.pbxproj"
info_plist="$runner_dir/Info.plist"

if [[ ! -d "$runner_dir" || ! -f "$project_file" ]]; then
  echo "macOS Runner not found. Run flutter create . --platforms=macos first." >&2
  exit 1
fi

set_plist_string() {
  local file="$1"
  local key="$2"
  local value="$3"

  if plutil -extract "$key" raw "$file" >/dev/null 2>&1; then
    plutil -replace "$key" -string "$value" "$file"
  else
    plutil -insert "$key" -string "$value" "$file"
  fi
}

set_entitlement() {
  local file="$1"
  local key="$2"

  if /usr/libexec/PlistBuddy -c "Print :$key" "$file" >/dev/null 2>&1; then
    /usr/libexec/PlistBuddy -c "Set :$key true" "$file"
  else
    /usr/libexec/PlistBuddy -c "Add :$key bool true" "$file"
  fi
}

if [[ -f "$info_plist" ]]; then
  set_plist_string "$info_plist" "CFBundleName" "MaoQiu Transfer"
  set_plist_string "$info_plist" "CFBundleDisplayName" "毛球互传"
fi

perl -0pi -e 's/PRODUCT_BUNDLE_IDENTIFIER = [^;]+;/PRODUCT_BUNDLE_IDENTIFIER = com.maoqiu.transfer;/g' "$project_file"

for entitlements in "$runner_dir/DebugProfile.entitlements" "$runner_dir/Release.entitlements"; do
  if [[ ! -f "$entitlements" ]]; then
    continue
  fi

  set_entitlement "$entitlements" "com.apple.security.app-sandbox"
  set_entitlement "$entitlements" "com.apple.security.network.client"
  set_entitlement "$entitlements" "com.apple.security.network.server"
  set_entitlement "$entitlements" "com.apple.security.files.downloads.read-write"
  set_entitlement "$entitlements" "com.apple.security.files.user-selected.read-write"
done

echo "macOS platform files patched for MaoQiu Transfer."
