#!/usr/bin/env bash
set -euo pipefail

pub_cache="${PUB_CACHE:-$HOME/.pub-cache}"

if [[ ! -d "$pub_cache" ]]; then
  echo "PUB_CACHE not found: $pub_cache"
  exit 0
fi

while IFS= read -r -d '' gradle_file; do
  perl -0pi -e 's/compileSdk\s*=\s*flutter\.compileSdkVersion/compileSdk = 36/g; s/compileSdkVersion\s+flutter\.compileSdkVersion/compileSdkVersion 36/g; s/compileSdk\s*=\s*\d+/compileSdk = 36/g; s/compileSdkVersion\s+\d+/compileSdkVersion 36/g' "$gradle_file"
done < <(find "$pub_cache" -path "*/android/build.gradle*" -print0)

echo "Android plugin Gradle files patched to compileSdk 36."
