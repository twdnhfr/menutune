#!/bin/bash
# Assembles build/MenuTune.app.
#
#   bash scripts/build-app.sh                     local build, current arch, ad-hoc signed
#   bash scripts/build-app.sh --universal --sign "Developer ID Application: …"
#
# scripts/release.sh drives the second form, so the bundle layout lives here
# only once and the two paths cannot drift apart.
set -euo pipefail
cd "$(dirname "$0")/.."

universal=false
identity="-"
hardened=false
while [ $# -gt 0 ]; do
    case "$1" in
        --universal) universal=true ;;
        --sign)
            [ $# -ge 2 ] || { printf 'Fehler: --sign braucht eine Identität.\n' >&2; exit 2; }
            identity="$2"
            hardened=true
            shift
            ;;
        *) printf 'Fehler: unbekanntes Argument %s\n' "$1" >&2; exit 2 ;;
    esac
    shift
done

build_args=(-c release)
if $universal; then
    build_args+=(--arch arm64 --arch x86_64)
fi

swift build "${build_args[@]}"
binary_dir="$(swift build "${build_args[@]}" --show-bin-path)"
app_dir="$PWD/build/MenuTune.app"
iconset="$PWD/build/MenuTune.iconset"

# A rebuild must not inherit files from an older layout that nothing overwrites.
rm -rf "$app_dir" "$iconset"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources" "$iconset"

for size in 16 32 128 256 512; do
    sips -z "$size" "$size" Support/Brand/menutune-logo.png --out "$iconset/icon_${size}x${size}.png" >/dev/null
    retina_size=$((size * 2))
    sips -z "$retina_size" "$retina_size" Support/Brand/menutune-logo.png --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$app_dir/Contents/Resources/MenuTune.icns"

cp "$binary_dir/MenuTune" "$app_dir/Contents/MacOS/MenuTune"
cp Support/Info.plist "$app_dir/Contents/Info.plist"
# SwiftPM's Bundle.module resolves only next to the executable or at an absolute
# build path, so the app carries the packaged resources in its own Resources
# directory, where Bundle.main finds them.
ditto Sources/MenuTune/Resources "$app_dir/Contents/Resources"

# A monotonic build number per commit, so every release carries a distinct one.
if build_number="$(git rev-list --count HEAD 2>/dev/null)"; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build_number" "$app_dir/Contents/Info.plist"
fi

sign_args=(--force --sign "$identity")
if $hardened; then
    # Notarisation requires both: the hardened runtime and a secure timestamp.
    sign_args+=(--options runtime --timestamp)
fi
codesign "${sign_args[@]}" "$app_dir"
codesign --verify --strict "$app_dir"

printf 'App erstellt: %s\n' "$app_dir"
printf 'Architektur:  %s\n' "$(lipo -archs "$app_dir/Contents/MacOS/MenuTune")"
printf 'Signatur:     %s\n' "$([ "$identity" = "-" ] && echo "ad hoc" || echo "$identity")"
