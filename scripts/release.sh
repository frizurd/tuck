#!/bin/zsh
# Builds, signs with Developer ID, notarizes and staples Tuck, then writes the Homebrew cask.
# Usage: TUCK_SIGNING_IDENTITY="Developer ID Application: …" TUCK_NOTARY_PROFILE=profile scripts/release.sh
set -euo pipefail
cd "${0:A:h}/.."
: "${TUCK_SIGNING_IDENTITY:?Set your Developer ID Application identity}"
: "${TUCK_NOTARY_PROFILE:?Set the notarytool keychain profile name}"
version="$(sed -nE 's/^version="\$\{TUCK_VERSION:-(.*)\}"/\1/p' build.sh)"
[[ -n "$version" ]] || { print "Could not read the version from build.sh"; exit 1 }

swift test
./build.sh
app="$PWD/build/Tuck.app"
archive="$PWD/build/Tuck-$version.zip"

ditto -c -k --keepParent "$app" "$archive"
xcrun notarytool submit "$archive" --keychain-profile "$TUCK_NOTARY_PROFILE" --wait
xcrun stapler staple "$app"
xcrun stapler validate "$app"
codesign --verify --strict "$app"
spctl --assess --type execute --verbose "$app"
# Zip again so the shipped archive contains the stapled ticket.
rm -f "$archive"
ditto -c -k --keepParent "$app" "$archive"

sha="$(shasum -a 256 "$archive" | cut -d' ' -f1)"
sed -e "s/@VERSION@/$version/" -e "s/@SHA256@/$sha/" packaging/tuck.rb.in > build/tuck.rb
print "Archive: $archive"
print "SHA-256: $sha"
print "Cask:    build/tuck.rb"
