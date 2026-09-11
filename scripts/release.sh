#!/bin/bash
# Produces a notarised, stapled universal DMG ready to put on a website.
#
#   bash scripts/release.sh
#   bash scripts/release.sh --skip-notarize     everything except the Apple round trip
#   bash scripts/release.sh --allow-dirty       release from an uncommitted tree
#
# Settings live in scripts/release.env, which stays out of the repository;
# scripts/release.env.example is the template. An environment variable of the
# same name wins over the file. Credentials themselves are never read here:
# notarytool keeps them in the keychain under the profile named below.
#
#   SIGN_IDENTITY   "Developer ID Application: … (TEAMID)"; without it the first
#                   matching identity from the keychain is used
#   NOTARY_PROFILE  name of the notarytool keychain profile; without it a
#                   notarising run stops with instructions
set -euo pipefail
cd "$(dirname "$0")/.."

# Deliberately not "source": the file is parsed, never executed.
load_release_config() {
    local file="$1" line key value
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line#"${line%%[![:space:]]*}"}"
        case "$line" in ''|'#'*) continue ;; esac
        line="${line#export }"
        key="${line%%=*}"
        if [ "$key" = "$line" ]; then
            printf '%s: skipped a line without "=": %s\n' "$file" "$line" >&2
            continue
        fi
        value="${line#*=}"
        key="${key%"${key##*[![:space:]]}"}"
        value="${value#"${value%%[![:space:]]*}"}"
        value="${value%"${value##*[![:space:]]}"}"
        case "$value" in
            \"*\") value="${value#\"}"; value="${value%\"}" ;;
            \'*\') value="${value#\'}"; value="${value%\'}" ;;
        esac
        case "$key" in
            SIGN_IDENTITY|NOTARY_PROFILE) ;;
            *) printf '%s: ignoring unknown key %s\n' "$file" "$key" >&2; continue ;;
        esac
        [ -n "${!key+set}" ] || export "$key=$value"
    done < "$file"
}

release_config="${MENUTUNE_RELEASE_ENV:-$PWD/scripts/release.env}"
[ -f "$release_config" ] && load_release_config "$release_config"

notarize=true
allow_dirty=false
while [ $# -gt 0 ]; do
    case "$1" in
        --skip-notarize) notarize=false ;;
        --allow-dirty) allow_dirty=true ;;
        *) printf 'Error: unknown argument %s\n' "$1" >&2; exit 2 ;;
    esac
    shift
done

step() { printf '\n==> %s\n' "$1"; }
fail() { printf 'Error: %s\n' "$1" >&2; exit 1; }

profile="${NOTARY_PROFILE:-}"
identity="${SIGN_IDENTITY:-}"
if [ -z "$identity" ]; then
    identity="$(security find-identity -v -p codesigning \
        | grep 'Developer ID Application' | head -1 | sed -E 's/.*"(.*)".*/\1/')"
fi

step "Preflight"
[ -n "$identity" ] || fail "No 'Developer ID Application' certificate found. Publishing is not possible without one."
printf 'Signing identity:  %s\n' "$identity"

if ! $allow_dirty && [ -n "$(git status --porcelain)" ]; then
    fail "The working tree is not clean. A release should be reproducible from a commit. Use --allow-dirty to skip this check."
fi

if $notarize; then
    [ -n "$profile" ] || fail "NOTARY_PROFILE is not set. Copy the template and fill it in:
  cp scripts/release.env.example scripts/release.env
Create a profile once with:
  xcrun notarytool store-credentials <name> --apple-id <your Apple ID> --team-id <your team>
Or build everything else with --skip-notarize."
    # Checked before the long build so a bad credential costs seconds, not minutes.
    if ! xcrun notarytool history --keychain-profile "$profile" >/dev/null 2>&1; then
        fail "The notarytool profile '$profile' is not usable. Create or refresh it with:
  xcrun notarytool store-credentials $profile --apple-id <your Apple ID> --team-id <your team>"
    fi
    printf 'notarytool profile: %s\n' "$profile"
fi

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Support/Info.plist)"
revision="$(git rev-parse --short HEAD)"
printf 'Version:           %s (%s)\n' "$version" "$revision"

step "Tests"
swift test

step "Universal build and signature"
bash scripts/build-app.sh --universal --sign "$identity"

app_dir="$PWD/build/MenuTune.app"
# An unnotarised build must not be able to sit next to a real one under a name
# that looks just as publishable.
if $notarize; then
    out_dir="$PWD/build/release/MenuTune-$version-$revision"
else
    out_dir="$PWD/build/release/MenuTune-$version-$revision-unnotarized"
fi
dmg="$out_dir/MenuTune-$version-universal.dmg"
rm -rf "$out_dir"
mkdir -p "$out_dir"

archs="$(lipo -archs "$app_dir/Contents/MacOS/MenuTune")"
case "$archs" in
    *x86_64*arm64*|*arm64*x86_64*) ;;
    *) fail "The binary is not universal, found: $archs" ;;
esac

if $notarize; then
    step "Notarise the app"
    # The app carries its own ticket too, so an installation stays verifiable
    # offline once it has been dragged out of the disk image.
    zip="$out_dir/MenuTune.zip"
    ditto -c -k --keepParent "$app_dir" "$zip"
    xcrun notarytool submit "$zip" --keychain-profile "$profile" --wait
    xcrun stapler staple "$app_dir"
    rm -f "$zip"
fi

step "Build the disk image"
staging="$PWD/build/dmg-staging"
rm -rf "$staging"
mkdir -p "$staging"
ditto "$app_dir" "$staging/MenuTune.app"
ln -s /Applications "$staging/Applications"
hdiutil create -volname "MenuTune $version" -srcfolder "$staging" -ov -format UDZO "$dmg" >/dev/null
rm -rf "$staging"
codesign --force --sign "$identity" --timestamp "$dmg"

if $notarize; then
    step "Notarise the disk image"
    xcrun notarytool submit "$dmg" --keychain-profile "$profile" --wait
    xcrun stapler staple "$dmg"
fi

step "Final check"
codesign --verify --strict --deep "$app_dir"
codesign --verify --strict "$dmg"
if $notarize; then
    # This is the verdict a visitor's Mac will reach after downloading.
    spctl -a -vvv -t exec "$app_dir"
    spctl -a -vvv -t open --context context:primary-signature "$dmg"
    printf '\nGatekeeper accepts both the app and the disk image.\n'
else
    printf '\nBuilt without notarisation: Gatekeeper rejects this. Do not publish it.\n'
fi

printf '\nDone:  %s\n' "$dmg"
printf 'Size:  %s\n' "$(du -h "$dmg" | cut -f1)"
