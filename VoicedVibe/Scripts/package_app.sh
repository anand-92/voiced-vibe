#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

source "$PROJECT_DIR/version.env"

BUILD_DIR="$PROJECT_DIR/build"
APP_BUNDLE="$BUILD_DIR/${APP_NAME}.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES_DIR="$CONTENTS/Resources"

echo "==> Building $APP_NAME..."
cd "$PROJECT_DIR"
swift build -c release 2>&1

BINARY_PATH=$(swift build -c release --show-bin-path)/"$APP_NAME"

if [ ! -f "$BINARY_PATH" ]; then
    echo "ERROR: Binary not found at $BINARY_PATH"
    exit 1
fi

echo "==> Assembling .app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BINARY_PATH" "$MACOS_DIR/$APP_NAME"

# Copy resources that SPM bundled
RESOURCE_BUNDLE=$(find "$(swift build -c release --show-bin-path)" -name "VoicedVibe_VoicedVibe.bundle" 2>/dev/null || true)
if [ -n "$RESOURCE_BUNDLE" ] && [ -d "$RESOURCE_BUNDLE" ]; then
    cp -R "$RESOURCE_BUNDLE" "$RESOURCES_DIR/"
fi

# Also copy backend directory directly for the fallback path
if [ -d "Sources/VoicedVibe/Resources/backend" ]; then
    cp -R "Sources/VoicedVibe/Resources/backend" "$RESOURCES_DIR/"
fi

# Generate Info.plist
cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>Voiced Vibe</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>Voiced Vibe needs microphone access for voice input to the AI assistant.</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticTermination</key>
    <false/>
</dict>
</plist>
PLIST

# Sign with hardened runtime + entitlements (enables mic permission dialog without sandbox restrictions)
echo "==> Signing with hardened runtime..."
codesign --force --sign - --options runtime --entitlements "$PROJECT_DIR/VoicedVibe.entitlements" "$MACOS_DIR/$APP_NAME"
codesign --force --sign - --options runtime --entitlements "$PROJECT_DIR/VoicedVibe.entitlements" "$APP_BUNDLE"

echo "==> Built: $APP_BUNDLE"
echo "==> Binary size: $(du -sh "$MACOS_DIR/$APP_NAME" | cut -f1)"
echo "==> Bundle size: $(du -sh "$APP_BUNDLE" | cut -f1)"
