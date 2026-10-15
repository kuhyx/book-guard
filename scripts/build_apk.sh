#!/bin/bash

# ============================================================================
# Build the release APK (arm64 by default) in two steps that each stay under the
# 60 s action cap. A cold `flutter build apk` after a Dart change is ~65 s:
# the Dart AOT compile (~35 s) and the Gradle packaging (~26 s) together.
# Splitting them lets step 2 find the AOT output up to date.
#
#   scripts/build_apk.sh aot   # Dart AOT snapshot only (gradle task)
#   scripts/build_apk.sh apk   # package + sign; reuses the AOT output
#
# After a dependency change (a new plugin or native library, e.g. pdfium) run
# `native` between the two: it compiles the plugins and merges the native
# libraries (~10 s warm), which otherwise pushes `apk` to ~55 s.
#
# An optional second argument picks another platform, e.g. android-x64 for
# the emulator: `scripts/build_apk.sh aot android-x64`.
# ============================================================================

set -euo pipefail

APP="$(cd "$(dirname "$0")/../app" && pwd)"
readonly APP
readonly CAPPED="$HOME/.claude/scripts/capped.sh"
readonly PLATFORM="${2:-android-arm64}"

capped() {
    CAP_MEM=4G CAP_CPU_PCT=20 "$CAPPED" "$@"
}

# Plain gradlew needs the JDK flutter is configured with (`flutter build`
# passes it itself); the system default breaks the plugins' jlink transform.
flutter_jdk() {
    flutter config --list 2>/dev/null | sed -n 's/^ *jdk-dir: *//p'
}

case "${1:-}" in
    aot)
        capped "$APP/android/gradlew" -p "$APP/android" -q \
            :app:compileFlutterBuildRelease -Ptarget-platform="$PLATFORM"
        ;;
    native)
        JAVA_HOME="$(flutter_jdk)" capped "$APP/android/gradlew" -p "$APP/android" -q \
            :app:mergeReleaseNativeLibs :app:compileReleaseJavaWithJavac \
            -Ptarget-platform="$PLATFORM"
        ;;
    apk)
        cd "$APP"
        capped flutter build apk --release --target-platform "$PLATFORM"
        ;;
    *)
        echo "usage: $0 aot|native|apk [android-arm64|android-x64]" >&2
        exit 2
        ;;
esac
