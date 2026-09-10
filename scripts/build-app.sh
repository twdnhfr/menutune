#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
binary_dir="$(swift build -c release --show-bin-path)"
app_dir="$PWD/build/MenuTune.app"
iconset="$PWD/build/MenuTune.iconset"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources" "$iconset"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" Support/Brand/menutune-logo.png --out "$iconset/icon_${size}x${size}.png" >/dev/null
    retina_size=$((size * 2))
    sips -z "$retina_size" "$retina_size" Support/Brand/menutune-logo.png --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$app_dir/Contents/Resources/MenuTune.icns"
cp "$binary_dir/MenuTune" "$app_dir/Contents/MacOS/MenuTune"
cp Support/Info.plist "$app_dir/Contents/Info.plist"
ditto "$binary_dir/MenuTune_MenuTune.bundle" "$app_dir/Contents/Resources/MenuTune_MenuTune.bundle"
codesign --force --sign - "$app_dir"
codesign --verify --strict "$app_dir"
printf 'App erstellt: %s\n' "$app_dir"
