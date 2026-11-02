#!/bin/zsh
# Builds build/Tuck.app (universal: Apple silicon + Intel).
# Set TUCK_SIGNING_IDENTITY to sign with a real identity (also keeps the Accessibility grant across rebuilds); otherwise ad-hoc.
set -euo pipefail
cd "${0:A:h}"

version="${TUCK_VERSION:-1.1.0}"
build_number="1"
app="$PWD/build/Tuck.app"

xcrun swift build -c release --arch arm64 --arch x86_64
binary="$(xcrun swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/Tuck"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary" "$app/Contents/MacOS/Tuck"

iconset="$PWD/build/AppIcon.iconset"
rm -rf "$iconset" && mkdir -p "$iconset"
for size in 16 32 128 256 512; do
  sips -z $size $size Assets/AppIcon.png --out "$iconset/icon_${size}x${size}.png" >/dev/null
  sips -z $((size * 2)) $((size * 2)) Assets/AppIcon.png --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$app/Contents/Resources/AppIcon.icns"

cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>Tuck</string>
  <key>CFBundleIdentifier</key><string>com.frizurd.tuck</string>
  <key>CFBundleName</key><string>Tuck</string>
  <key>CFBundleDisplayName</key><string>Tuck</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleShortVersionString</key><string>$version</string>
  <key>CFBundleVersion</key><string>$build_number</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>MIT License</string>
  <key>CFBundleURLTypes</key>
  <array><dict>
    <key>CFBundleURLName</key><string>com.frizurd.tuck</string>
    <key>CFBundleURLSchemes</key><array><string>tuck</string></array>
  </dict></array>
</dict></plist>
PLIST

if [[ -n "${TUCK_SIGNING_IDENTITY:-}" ]]; then
  codesign --force --options runtime --timestamp --sign "$TUCK_SIGNING_IDENTITY" "$app"
else
  codesign --force --sign - "$app"
fi
codesign --verify --strict "$app"
print "Built $app"
