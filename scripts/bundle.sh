#!/usr/bin/env bash
# Builds OmniIsland and wraps the binary in a minimal .app bundle so that it
# runs as a menu-bar-only (LSUIElement) app.
#
# macOS keeps the Accessibility permission only while the app's signature
# stays the same. Sign every build with the same certificate (see
# scripts/create-signing-cert.sh) and the permission survives updates.
#
# Usage:
#   scripts/bundle.sh            # build/OmniIsland.app
#   scripts/bundle.sh --install  # also copy to /Applications and launch it
#
# Environment:
#   OMNI_ISLAND_VERSION        marketing version, default: latest v* tag or 0.0.0
#   OMNI_ISLAND_BUILD          build number, default: commit count
#   OMNI_ISLAND_SIGN_IDENTITY  codesign identity (name or SHA-1). Default: the
#                              "OmniIsland Signing" certificate if it is in a
#                              keychain, otherwise ad-hoc ("-").
#   OMNI_ISLAND_KEYCHAIN       keychain that holds the identity (optional)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/OmniIsland.app"
BUNDLE_ID="io.github.jadewisemann.omni-island"
CERT_NAME="OmniIsland Signing"

cd "$ROOT"

latest_tag="$(git describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null || true)"
VERSION="${OMNI_ISLAND_VERSION:-${latest_tag#v}}"
VERSION="${VERSION:-0.0.0}"
BUILD="${OMNI_ISLAND_BUILD:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"

KEYCHAIN_ARGS=()
if [[ -n "${OMNI_ISLAND_KEYCHAIN:-}" ]]; then
  KEYCHAIN_ARGS=(--keychain "$OMNI_ISLAND_KEYCHAIN")
fi

SIGN_IDENTITY="${OMNI_ISLAND_SIGN_IDENTITY:-}"
if [[ -z "$SIGN_IDENTITY" ]]; then
  # A self-signed certificate is not "valid" for Gatekeeper, so do not pass -v.
  SIGN_IDENTITY="$(security find-identity -p codesigning ${OMNI_ISLAND_KEYCHAIN:+"$OMNI_ISLAND_KEYCHAIN"} 2>/dev/null \
    | awk -v name="\"$CERT_NAME\"" 'index($0, name) { print $2; exit }')"
fi
if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="-"
  echo "warning: '$CERT_NAME' certificate not found; signing ad-hoc." >&2
  echo "warning: macOS will ask for Accessibility permission again after every update." >&2
fi

swift build -c release --arch arm64
BIN="$(swift build -c release --arch arm64 --show-bin-path)/OmniIsland"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/OmniIsland"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>OmniIsland</string>
  <key>CFBundleDisplayName</key><string>OmniIsland</string>
  <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
  <key>CFBundleExecutable</key><string>OmniIsland</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${BUILD}</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSCalendarsFullAccessUsageDescription</key><string>아일랜드에 다음 일정을 보여 주고 일정이 시작되기 전에 알려 주려고 캘린더를 읽습니다.</string>
  <key>NSCalendarsUsageDescription</key><string>아일랜드에 다음 일정을 보여 주고 일정이 시작되기 전에 알려 주려고 캘린더를 읽습니다.</string>
</dict>
</plist>
PLIST

codesign --force --sign "$SIGN_IDENTITY" ${KEYCHAIN_ARGS[@]+"${KEYCHAIN_ARGS[@]}"} \
  --identifier "$BUNDLE_ID" "$APP"
codesign --display --requirements - "$APP" 2>&1 | sed -n 's/^designated => /designated requirement: /p'
echo "Built $APP (version $VERSION, build $BUILD)"

if [[ "${1:-}" == "--install" ]]; then
  DEST="/Applications/OmniIsland.app"
  osascript -e 'quit app id "'"$BUNDLE_ID"'"' 2>/dev/null || true
  sleep 0.5
  rm -rf "$DEST"
  cp -R "$APP" "$DEST"
  open "$DEST"
  echo "Installed and launched $DEST"
fi
