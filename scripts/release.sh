#!/usr/bin/env bash
#
# release.sh — build, Developer-ID sign, notarize, staple and zip ProfessorNotch
# for warning-free distribution outside the App Store.
#
# ── ONE-TIME SETUP (after you join the Apple Developer Program) ────────────────
# 1. In Xcode → Settings → Accounts, add your Apple ID and let it create a
#    "Developer ID Application" certificate (or create it at developer.apple.com).
# 2. Find your signing identity:
#       security find-identity -v -p codesigning
#    Copy the "Developer ID Application: Your Name (TEAMID)" string into DEV_ID below.
# 3. Store notarization credentials once (uses an app-specific password from
#    appleid.apple.com, NOT your login password):
#       xcrun notarytool store-credentials "ProfessorNotch" \
#         --apple-id "you@example.com" --team-id "TEAMID" --password "app-specific-pw"
#    Then set NOTARY_PROFILE="ProfessorNotch" below.
# ──────────────────────────────────────────────────────────────────────────────
#
# Usage:  ./scripts/release.sh
# Output: dist/ProfessorNotch.zip  (notarized + stapled, ready to upload to GitHub Releases)

set -euo pipefail

# ── CONFIG — fill these in after you have the Developer ID ────────────────────
DEV_ID="Developer ID Application: YOUR NAME (TEAMID)"   # from step 2
NOTARY_PROFILE="ProfessorNotch"                          # from step 3
APP_NAME="ProfessorNotch"
SCHEME="DiskSync"
PROJECT="DiskSync.xcodeproj"
ENTITLEMENTS="DiskSync.entitlements"
# ──────────────────────────────────────────────────────────────────────────────

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
BUILD_DIR="$ROOT/build"
DIST_DIR="$ROOT/dist"
rm -rf "$BUILD_DIR" "$DIST_DIR"
mkdir -p "$DIST_DIR"

echo "▸ Building Release…"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
  -derivedDataPath "$BUILD_DIR" \
  CODE_SIGN_IDENTITY="$DEV_ID" \
  clean build | xcpretty 2>/dev/null || xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
  -configuration Release -derivedDataPath "$BUILD_DIR" CODE_SIGN_IDENTITY="$DEV_ID" clean build

BUILT_APP="$BUILD_DIR/Build/Products/Release/$SCHEME.app"
APP="$DIST_DIR/$APP_NAME.app"
cp -R "$BUILT_APP" "$APP"

echo "▸ Signing with Developer ID + hardened runtime…"
codesign --force --deep --options runtime --timestamp \
  --entitlements "$ENTITLEMENTS" \
  --sign "$DEV_ID" "$APP"
codesign --verify --strict --verbose=2 "$APP"

echo "▸ Zipping for notarization…"
ZIP="$DIST_DIR/$APP_NAME.zip"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "▸ Submitting to Apple for notarization (this can take a few minutes)…"
xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait

echo "▸ Stapling the ticket…"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

echo "▸ Re-zipping the stapled app for distribution…"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "✅ Done → $ZIP  (upload this to GitHub Releases)"
