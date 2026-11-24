#!/bin/sh
# Notarizes and staples .build/Eighty.app (built and signed by build-app.sh),
# then zips it as .build/Eighty-<version>.zip.
# Needs an App Store Connect API key: NOTARY_KEY (path to the .p8 file),
# NOTARY_KEY_ID, and NOTARY_ISSUER.
set -eu
cd "$(dirname "$0")/.."
version=$(sed -n 's/.*eightyVersion = "\(.*\)"/\1/p' Sources/EightyKit/Version.swift)
app=.build/Eighty.app
zip=".build/Eighty-$version.zip"

rm -f "$zip"
ditto -c -k --keepParent "$app" "$zip"
result=$(xcrun notarytool submit "$zip" --key "$NOTARY_KEY" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER" \
  --wait --timeout 30m --output-format json)
status=$(printf '%s' "$result" | plutil -extract status raw -)
if [ "$status" != Accepted ]; then
  echo "Notarization finished with status: $status" >&2
  id=$(printf '%s' "$result" | plutil -extract id raw -)
  xcrun notarytool log "$id" --key "$NOTARY_KEY" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER" >&2
  exit 1
fi

# Staple the ticket so Gatekeeper accepts the app offline, then zip the stapled app.
xcrun stapler staple "$app"
rm "$zip"
ditto -c -k --keepParent "$app" "$zip"
spctl --assess --type execute --verbose "$app"
echo "Notarized $zip"
