#!/usr/bin/env bash
set -euo pipefail

version="$(awk '/^version: / {print $2; exit}' pubspec.yaml | cut -d+ -f1)"
if [[ -z "$version" ]]; then
  echo "Unable to resolve version from pubspec.yaml" >&2
  exit 1
fi

flutter config --enable-macos-desktop
flutter create . --platforms=macos
./tool/patch_macos_platform.sh
flutter pub get
flutter build macos --release

mkdir -p dist
app_path="$(find build/macos/Build/Products/Release -maxdepth 1 -name '*.app' | head -n 1)"
if [[ -z "$app_path" ]]; then
  echo "macOS app bundle not found" >&2
  exit 1
fi

hdiutil create \
  -volname "MaoQiu Transfer" \
  -srcfolder "$app_path" \
  -ov \
  -format UDZO \
  "dist/maoqiu-transfer-v${version}-macos.dmg"

pkgbuild \
  --install-location /Applications \
  --component "$app_path" \
  "dist/maoqiu-transfer-v${version}-macos.pkg"

echo "Built dist/maoqiu-transfer-v${version}-macos.dmg"
echo "Built dist/maoqiu-transfer-v${version}-macos.pkg"
