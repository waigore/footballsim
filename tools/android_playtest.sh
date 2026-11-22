#!/bin/bash
# Build + install + launch the Android debug APK and report in-engine PERF lines.
# Usage: tools/android_playtest.sh [seconds]
#
# Install is streamed (not incremental) and fatal: an incremental install on a
# full emulator data partition fails without a non-zero status, and the run that
# follows then measures the previous APK.
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$PATH:$HOME/Library/Android/sdk/platform-tools"
export JAVA_HOME=/opt/homebrew/opt/openjdk@21
export ANDROID_HOME="$HOME/Library/Android/sdk"
export ANDROID_SDK_ROOT="$HOME/Library/Android/sdk"
export GODOT_ANDROID_KEYSTORE_DEBUG_PATH="$PWD/export/android/debug.keystore"
export GODOT_ANDROID_KEYSTORE_DEBUG_USER=androiddebugkey
export GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD=android

mkdir -p build/android
echo "== export =="
godot --headless --path . --export-debug "Android Debug" build/android/footballsim-debug.apk 2>&1 | grep -iE "^ERROR|DONE.*export" | tail -3

echo "== install =="
adb install -r --no-incremental build/android/footballsim-debug.apk > /tmp/apk_install.log 2>&1 || true
tail -2 /tmp/apk_install.log
if ! grep -q "Success" /tmp/apk_install.log; then
  echo "install failed — the next launch would run the previous APK" >&2
  cat /tmp/apk_install.log >&2
  exit 1
fi

adb shell am force-stop com.waigore.footballsim.debug
adb logcat -c
adb shell am start -n com.waigore.footballsim.debug/com.godot.game.GodotAppLauncher >/dev/null
sleep "${1:-14}"

echo "== godot log =="
adb logcat -d -s godot:V | grep -E "DEVICE|PERF|ERROR|SCRIPT" | tail -20
