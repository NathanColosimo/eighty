#!/bin/sh
# Builds Eighty.app (menu bar app with the eighty CLI inside) into .build/.
#   scripts/build-app.sh            build only
#   scripts/build-app.sh --zip      also zip it: .build/Eighty-<version>.zip
#   scripts/build-app.sh --install  also copy it to /Applications and open it
# Signs ad hoc unless EIGHTY_SIGN_IDENTITY names a certificate (EIGHTY_KEYCHAIN
# optionally says which keychain holds it). Releases sign with DEVELOPER_ID from
# scripts/release.env, then scripts/notarize.sh notarizes the result.
set -eu
cd "$(dirname "$0")/.."
. scripts/release.env
version=$(sed -n 's/.*eightyVersion = "\(.*\)"/\1/p' Sources/EightyKit/Version.swift)

swift build -c release --product EightyBar
swift build -c release --product eighty

app=.build/Eighty.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Helpers" "$app/Contents/Resources" "$app/Contents/Library/LaunchDaemons"
cp .build/release/EightyBar "$app/Contents/MacOS/Eighty"
cp .build/release/eighty "$app/Contents/Helpers/eighty"

iconset=$(mktemp -d)/AppIcon.iconset
mkdir -p "$iconset"
swift scripts/make-icon.swift "$iconset/icon_512x512@2x.png"
for size in 16 32 128 256 512; do
  sips -z $size $size "$iconset/icon_512x512@2x.png" --out "$iconset/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  [ $double -le 512 ] && sips -z $double $double "$iconset/icon_512x512@2x.png" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$app/Contents/Resources/AppIcon.icns"

cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Eighty</string>
  <key>CFBundleDisplayName</key><string>Eighty</string>
  <key>CFBundleIdentifier</key><string>dev.eighty.menubar</string>
  <key>CFBundleExecutable</key><string>Eighty</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$version</string>
  <key>CFBundleVersion</key><string>$version</string>
  <key>LSMinimumSystemVersion</key><string>$MIN_MACOS</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

# The background service, which the app registers with SMAppService. launchd
# runs the CLI from inside the app, so it needs no copy and upgrades with it.
# Paths.daemonLabel in Sources/EightyKit/System.swift names it.
cat > "$app/Contents/Library/LaunchDaemons/dev.eighty.daemon.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>dev.eighty.daemon</string>
  <key>BundleProgram</key><string>Contents/Helpers/eighty</string>
  <key>ProgramArguments</key><array><string>eighty</string><string>daemon</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ProcessType</key><string>Background</string>
</dict>
</plist>
PLIST

# Inside first, then the app. A real identity also gets the hardened runtime
# and a secure timestamp, which notarization requires.
identity=${EIGHTY_SIGN_IDENTITY:--}
sign() {
  if [ "$identity" = - ]; then
    codesign --force --sign - "$1"
  else
    codesign --force --options runtime --timestamp --sign "$identity" ${EIGHTY_KEYCHAIN:+--keychain "$EIGHTY_KEYCHAIN"} "$1"
  fi
}
sign "$app/Contents/Helpers/eighty"
sign "$app"
echo "Built $app ($version)"

case "${1:-}" in
--zip)
  zip=".build/Eighty-$version.zip"
  rm -f "$zip"
  ditto -c -k --keepParent "$app" "$zip"
  echo "Zipped $zip"
  ;;
--install)
  osascript -e 'quit app "Eighty"' 2>/dev/null || true
  rm -rf /Applications/Eighty.app
  cp -R "$app" /Applications/Eighty.app
  open /Applications/Eighty.app
  echo "Installed /Applications/Eighty.app"
  ;;
esac
