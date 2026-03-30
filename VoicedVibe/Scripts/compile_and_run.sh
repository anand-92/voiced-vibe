#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

source "$PROJECT_DIR/version.env"

APP_BUNDLE="$PROJECT_DIR/build/${APP_NAME}.app"

# Kill existing instance
pkill -f "${APP_NAME}.app/Contents/MacOS/${APP_NAME}" 2>/dev/null || true
sleep 0.5

# Build and package
"$SCRIPT_DIR/package_app.sh"

# Launch
echo "==> Launching ${APP_NAME}..."
open "$APP_BUNDLE"
