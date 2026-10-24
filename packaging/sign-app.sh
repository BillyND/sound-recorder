#!/usr/bin/env bash
# Sign "Sound Recorder.app" and its embedded Sparkle.framework, inner code first, with one identity.
# Usage: packaging/sign-app.sh <app> <identity>
# macOS keeps the Screen & System Audio Recording and Microphone permissions across builds and Sparkle
# accepts an update only while the designated requirement (bundle id + certificate) stays the same, so
# releases need the stable identity. Local builds without it fall back to ad-hoc signing, unless
# REQUIRE_IDENTITY=1 (set by packaging/release.sh).
set -euo pipefail
APP="$1"
IDENTITY="$2"

if ! security find-identity -p codesigning | grep -q "\"$IDENTITY\""; then
  if [ "${REQUIRE_IDENTITY:-0}" = 1 ]; then
    echo "missing code signing identity \"$IDENTITY\" (a release must keep the same signature)" >&2; exit 1
  fi
  echo "warning: signing identity \"$IDENTITY\" not found; ad-hoc signing (permissions reset on every build, updates refused)" >&2
  IDENTITY=-
fi

sign() { codesign --force --timestamp=none --sign "$IDENTITY" "$@"; }
FW="$APP/Contents/Frameworks/Sparkle.framework"
sign "$FW/Versions/B/XPCServices/Installer.xpc"
sign --preserve-metadata=entitlements "$FW/Versions/B/XPCServices/Downloader.xpc"
sign "$FW/Versions/B/Autoupdate"
sign "$FW/Versions/B/Updater.app"
sign "$FW"
sign "$APP"
codesign --verify --deep --strict "$APP"
echo "signed with: $IDENTITY"
