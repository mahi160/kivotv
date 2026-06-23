#!/bin/bash
# deploy.sh: build and deploy to Kivo TV

set -eo pipefail

TARGET="192.168.0.70:5555"
PACKAGE="com.kivo.tv"
APK="build/app/outputs/flutter-apk/app-release.apk" # Standard location
export PATH="$PATH:$HOME/Library/Android/sdk/platform-tools"

echo "Building..."
flutter build apk --release --target-platform android-arm || { echo "Build failed"; exit 1; }

echo "Connecting to $TARGET..."
adb kill-server && adb start-server
adb connect "$TARGET" >/dev/null

if [[ "$(adb -s "$TARGET" get-state 2>/dev/null)" != "device" ]]; then
    echo "Error: $TARGET not detected"
    exit 1
fi

echo "Installing..."
adb -s "$TARGET" install -r "$APK"

echo "Launching..."
adb -s "$TARGET" shell monkey -p "$PACKAGE" -c android.intent.category.LEANBACK_LAUNCHER 1 >/dev/null

sleep 6
echo "Focus:"
adb -s "$TARGET" shell dumpsys window | grep mCurrentFocus