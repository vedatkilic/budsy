#!/bin/bash
set -euo pipefail

# Release build for direct distribution (GitHub, Homebrew): builds Budsy.app,
# signs it with the Developer ID identity (hardened runtime, timestamp),
# notarizes and staples it, then wraps it in a drag-to-Applications .dmg that
# is itself signed, notarized and stapled, plus a zip of the stapled app for
# the Nix flake. Gatekeeper opens the result without
# the "Apple could not verify…" dialog that used to send the app to the Trash.
#
# Needs, once per Mac:
#   - the "Developer ID Application" identity in the login keychain
#     (~/.claude/secrets/budsy.sh restore)
#   - a notarytool keychain profile:
#     xcrun notarytool store-credentials nivorbit --key AuthKey.p8 --key-id … --issuer …
#
# SKIP_NOTARIZE=1 produces a signed-but-unnotarized build for local checks.

APP_NAME="Budsy"
VERSION="${1:-1.0.0}"
DIST="dist"
STAGE="$DIST/stage"
DMG="$DIST/Budsy-$VERSION.dmg"
IDENTITY="${SIGN_IDENTITY:-Developer ID Application: NIVORBIT TEKNOLOJI LIMITED SIRKETI (79S4TUX86W)}"
PROFILE="${NOTARY_PROFILE:-nivorbit}"

echo "==> Building…"
bash build.sh

echo "==> Signing $APP_NAME.app with Developer ID…"
codesign --force --options runtime --timestamp \
  --entitlements Signing/Budsy-Direct.entitlements \
  --sign "$IDENTITY" "$APP_NAME.app"
codesign --verify --deep --strict "$APP_NAME.app"

mkdir -p "$DIST"
if [ -z "${SKIP_NOTARIZE:-}" ]; then
  echo "==> Notarizing $APP_NAME.app…"
  ditto -c -k --keepParent "$APP_NAME.app" "$DIST/$APP_NAME.zip"
  xcrun notarytool submit "$DIST/$APP_NAME.zip" --keychain-profile "$PROFILE" --wait
  xcrun stapler staple "$APP_NAME.app"
  rm -f "$DIST/$APP_NAME.zip"
fi

# The stapled app as a zip, for package managers that can't mount an APFS dmg
# (the Nix flake unpacks this one). ditto keeps symlinks and the signature.
ZIP="$DIST/Budsy-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP_NAME.app" "$ZIP"

echo "==> Staging $APP_NAME.app…"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP_NAME.app" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Applications"

echo "==> Creating .dmg…"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGE" \
  -ov -format UDZO \
  "$DMG"
rm -rf "$STAGE"
codesign --force --timestamp --sign "$IDENTITY" "$DMG"

if [ -z "${SKIP_NOTARIZE:-}" ]; then
  echo "==> Notarizing ${DMG}…"
  xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
  xcrun stapler staple "$DMG"
  echo "==> Gatekeeper check:"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG" 2>&1 | tail -1
fi

echo "==> Done: $DMG"
echo "    SHA256: $(shasum -a 256 "$DMG" | awk '{print $1}')"
echo "==> Done: $ZIP"
echo "    SRI (flake.nix): sha256-$(openssl dgst -sha256 -binary "$ZIP" | base64)"
