#!/bin/zsh
set -euo pipefail

# Create the free-to-distribute development build described in README.md.
# It is Apple Development-signed, deliberately not notarized, and must not
# contain a development provisioning profile. Do not use this script for a
# Developer ID release.

root="$(cd "$(dirname "$0")/.." && pwd)"
derived_data="$(mktemp -d "$root/build/pre-anything-development-derived.XXXXXX")"
products="$derived_data/Build/Products/Release"
app="$products/Pre-Anything.app"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$root/Sources/PreAnything/Info.plist")"
stage="$(mktemp -d "$root/build/pre-anything-development-dmg.XXXXXX")"
dmg="$root/build/Pre-Anything-${version}-development-universal.dmg"
lsregister='/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister'

cleanup() {
    # xcodebuild registers every produced .app with Launch Services.  This
    # product lives in a temporary derived-data directory, so unregister it
    # before removing that directory; otherwise it can linger as a ghost
    # entry in Launchpad even after the package build has finished.
    if [[ -d "$app" && -x "$lsregister" ]]; then
        "$lsregister" -u "$app" >/dev/null 2>&1 || true
    fi
    /bin/rm -rf "$stage"
    /bin/rm -rf "$derived_data"
}
trap cleanup EXIT

cd "$root"
xcodegen generate
xcodebuild \
    -project PreAnything.xcodeproj \
    -scheme PreAnything \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "$derived_data" \
    ONLY_ACTIVE_ARCH=NO \
    ARCHS='arm64 x86_64' \
    build

if [[ ! -d "$app" ]]; then
    print -u2 -- "error: expected app bundle not found at $app"
    exit 1
fi

/usr/bin/codesign --verify --deep --strict --verbose=2 "$app"
signature="$(/usr/bin/codesign -dv --verbose=2 "$app" 2>&1)"
if ! print -r -- "$signature" | /usr/bin/grep -q 'Authority=Apple Development:'; then
    print -u2 -- 'error: the App is not signed with an Apple Development certificate'
    exit 1
fi

for extension in "$app"/Contents/PlugIns/*.appex; do
    /usr/bin/codesign --verify --strict --verbose=2 "$extension"
done

if /usr/bin/find "$app" -name embedded.provisionprofile -type f -print -quit | /usr/bin/grep -q .; then
    print -u2 -- 'error: development provisioning profiles are not valid for this GitHub build'
    exit 1
fi

/usr/bin/ditto "$app" "$stage/Pre-Anything.app"
/bin/ln -s /Applications "$stage/Applications"
/usr/bin/hdiutil create \
    -volname "Pre-Anything ${version} Development" \
    -srcfolder "$stage" \
    -ov \
    -format UDZO \
    "$dmg"
/usr/bin/hdiutil verify "$dmg"
/usr/bin/shasum -a 256 "$dmg"
print -- "Created: $dmg"
