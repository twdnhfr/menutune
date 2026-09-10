#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
binary_dir="$(swift build -c release --show-bin-path)"
app_dir="$PWD/build/MenuTune.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$binary_dir/MenuTune" "$app_dir/Contents/MacOS/MenuTune"
cp Support/Info.plist "$app_dir/Contents/Info.plist"
ditto "$binary_dir/MenuTune_MenuTune.bundle" "$app_dir/Contents/Resources/MenuTune_MenuTune.bundle"
codesign --force --sign - "$app_dir"
codesign --verify --strict "$app_dir"
printf 'App erstellt: %s\n' "$app_dir"
