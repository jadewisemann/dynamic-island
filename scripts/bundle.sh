#!/usr/bin/env bash
# Builds OmniIsland and wraps the binary in a minimal .app bundle so that it
# runs as a menu-bar-only (LSUIElement) app and macOS remembers its
# Accessibility permission under a stable bundle identifier.
#
# Usage:
#   scripts/bundle.sh            # build/OmniIsland.app
#   scripts/bundle.sh --install  # also copy to ~/Applications and launch it
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/OmniIsland.app"
BUNDLE_ID="${OMNI_ISLAND_BUNDLE_ID:-io.github.jadewisemann.omni-island}"
SIGN_IDENTITY="${OMNI_ISLAND_SIGN_IDENTITY:--}"

cd "$ROOT"
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
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Ad-hoc signature by default. With a real identity (OMNI_ISLAND_SIGN_IDENTITY)
# the Accessibility grant survives rebuilds.
codesign --force --deep --sign "$SIGN_IDENTITY" "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  DEST="$HOME/Applications/OmniIsland.app"
  mkdir -p "$HOME/Applications"
  pkill -x OmniIsland 2>/dev/null || true
  rm -rf "$DEST"
  cp -R "$APP" "$DEST"
  open "$DEST"
  echo "Installed and launched $DEST"
fi
