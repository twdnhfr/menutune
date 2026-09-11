#!/bin/bash
# Produces a notarised, stapled universal DMG ready to put on a website.
#
#   bash scripts/release.sh
#   bash scripts/release.sh --skip-notarize     everything except the Apple round trip
#   bash scripts/release.sh --allow-dirty       release from an uncommitted tree
#
# Credentials are never read by this script. Store them once with:
#   xcrun notarytool store-credentials menutune --apple-id <ID> --team-id <TEAM>
# Override the defaults with MENUTUNE_SIGN_IDENTITY and MENUTUNE_NOTARY_PROFILE.
set -euo pipefail
cd "$(dirname "$0")/.."

notarize=true
allow_dirty=false
while [ $# -gt 0 ]; do
    case "$1" in
        --skip-notarize) notarize=false ;;
        --allow-dirty) allow_dirty=true ;;
        *) printf 'Fehler: unbekanntes Argument %s\n' "$1" >&2; exit 2 ;;
    esac
    shift
done

step() { printf '\n==> %s\n' "$1"; }
fail() { printf 'Fehler: %s\n' "$1" >&2; exit 1; }

profile="${MENUTUNE_NOTARY_PROFILE:-menutune}"
identity="${MENUTUNE_SIGN_IDENTITY:-}"
if [ -z "$identity" ]; then
    identity="$(security find-identity -v -p codesigning \
        | grep 'Developer ID Application' | head -1 | sed -E 's/.*"(.*)".*/\1/')"
fi

step "Vorprüfung"
[ -n "$identity" ] || fail "Kein 'Developer ID Application'-Zertifikat gefunden. Ohne das ist keine Veröffentlichung möglich."
printf 'Signatur-Identität: %s\n' "$identity"

if ! $allow_dirty && [ -n "$(git status --porcelain)" ]; then
    fail "Das Arbeitsverzeichnis ist nicht sauber. Ein Release soll aus einem Commit reproduzierbar sein. Mit --allow-dirty überspringen."
fi

if $notarize; then
    # Checked before the long build so a missing credential costs seconds, not minutes.
    if ! xcrun notarytool history --keychain-profile "$profile" --limit 1 >/dev/null 2>&1; then
        fail "Kein nutzbares notarytool-Profil '$profile'. Einmalig anlegen mit:
  xcrun notarytool store-credentials $profile --apple-id <deine Apple-ID> --team-id <dein Team>
Oder mit --skip-notarize alles andere bauen."
    fi
    printf 'notarytool-Profil:  %s\n' "$profile"
fi

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Support/Info.plist)"
revision="$(git rev-parse --short HEAD)"
printf 'Version:            %s (%s)\n' "$version" "$revision"

step "Tests"
swift test

step "Universal-Build und Signatur"
bash scripts/build-app.sh --universal --sign "$identity"

app_dir="$PWD/build/MenuTune.app"
out_dir="$PWD/build/release/MenuTune-$version-$revision"
dmg="$out_dir/MenuTune-$version-universal.dmg"
rm -rf "$out_dir"
mkdir -p "$out_dir"

archs="$(lipo -archs "$app_dir/Contents/MacOS/MenuTune")"
case "$archs" in
    *x86_64*arm64*|*arm64*x86_64*) ;;
    *) fail "Das Binary ist nicht universal, gefunden: $archs" ;;
esac

if $notarize; then
    step "App notarisieren"
    # The app carries its own ticket too, so an installation stays verifiable
    # offline once it has been dragged out of the disk image.
    zip="$out_dir/MenuTune.zip"
    ditto -c -k --keepParent "$app_dir" "$zip"
    xcrun notarytool submit "$zip" --keychain-profile "$profile" --wait
    xcrun stapler staple "$app_dir"
    rm -f "$zip"
fi

step "Disk-Image bauen"
staging="$PWD/build/dmg-staging"
rm -rf "$staging"
mkdir -p "$staging"
ditto "$app_dir" "$staging/MenuTune.app"
ln -s /Applications "$staging/Applications"
hdiutil create -volname "MenuTune $version" -srcfolder "$staging" -ov -format UDZO "$dmg" >/dev/null
rm -rf "$staging"
codesign --force --sign "$identity" --timestamp "$dmg"

if $notarize; then
    step "Disk-Image notarisieren"
    xcrun notarytool submit "$dmg" --keychain-profile "$profile" --wait
    xcrun stapler staple "$dmg"
fi

step "Abschlussprüfung"
codesign --verify --strict --deep "$app_dir"
codesign --verify --strict "$dmg"
if $notarize; then
    # This is the verdict a visitor's Mac will reach after downloading.
    spctl -a -vvv -t exec "$app_dir"
    spctl -a -vvv -t open --context context:primary-signature "$dmg"
    printf '\nGatekeeper akzeptiert App und Disk-Image.\n'
else
    printf '\nOhne Notarisierung gebaut: Gatekeeper weist das Ergebnis ab. Nicht veröffentlichen.\n'
fi

printf '\nFertig: %s\n' "$dmg"
printf 'Größe:  %s\n' "$(du -h "$dmg" | cut -f1)"
