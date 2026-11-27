#!/bin/bash

# ============================================================================
# Build the APK (arm64 by default) in two steps that each stay under the
# 60 s action cap. A cold `flutter build apk` after a Dart change is ~65 s:
# the Dart AOT compile (~35 s) and the Gradle packaging (~26 s) together.
# Splitting them lets step 2 find the AOT output up to date.
#
# Every step first runs `flutter build apk --config-only` (~1 s, no build),
# doing the setup plain gradlew skips: pub get, app/android/local.properties
# (flutter.sdk, versionCode), the gradlew wrapper,
# GeneratedPluginRegistrant.java and .flutter-plugins-dependencies.
#
# Release:
#   scripts/build_apk.sh aot [android-arm64|android-x64]
#   scripts/build_apk.sh apk [android-arm64|android-x64]
#   scripts/build_apk.sh native [android-arm64|android-x64]
#
# Debug:
#   scripts/build_apk.sh aot-debug [android-arm64|android-x64]
#   scripts/build_apk.sh apk-debug [android-arm64|android-x64]
#   scripts/build_apk.sh native-debug [android-arm64|android-x64]
#
# After a dependency change (a new plugin or native library, e.g. pdfium) run
# `native` or `native-debug` between the two: it compiles the plugins and
# merges the native libraries (~10 s warm), which otherwise pushes `apk` to
# ~55 s.
#
# An optional second argument picks another platform, e.g. android-x64 for
# the emulator: `scripts/build_apk.sh aot android-x64`.
#
# Why not `flutter build apk` directly: it adds `-Pdart-defines=...` and
# `-Ptree-shake-icons=true` (release) / `false` (debug) which differ from
# the plain gradlew AOT step, so `apk` recompiles the AOT (~35 s) on top of
# packaging (~26 s) = 64 s (perf.heavybuild). This script builds ONE shared
# property array per mode so every gradlew call uses identical inputs.
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

# Plain gradlew skips the setup `flutter build apk` does first; this ~1 s
# config-only pass builds nothing but regenerates it. Runs before the
# gradlew call of every step because it creates the gradlew wrapper.
flutter_config() {
    (cd "$APP" && capped flutter build apk --config-only --"$1" --target-platform "$PLATFORM")
}

# Fill the global PROPS array with the shared gradle properties for the mode.
# PROPS is a global array the function fills, not a local one, so callers
# read it directly after the call.
gradle_props() {
    local mode="$1"
    local tree_shake
    if [[ "$mode" == "Release" ]]; then
        tree_shake=true
    else
        tree_shake=false
    fi
    PROPS=(
        -Ptarget-platform="$PLATFORM"
        -Ptarget=lib/main.dart
        -Pbase-application-name=android.app.Application
        -Pdart-obfuscation=false
        -Ptrack-widget-creation=true
        -Ptree-shake-icons="$tree_shake"
        -Penable-hcpp=false
    )
}

# Copy the assembled APK to where `flutter build apk` puts it (deploy.sh
# and agents read that path); fails loudly if the source is missing.
copy_apk() {
    local src dst
    if [[ "$1" == "release" ]]; then
        src="$APP/build/app/outputs/apk/release/app-release.apk"
        dst="$APP/build/app/outputs/flutter-apk/app-release.apk"
    else
        src="$APP/build/app/outputs/apk/debug/app-debug.apk"
        dst="$APP/build/app/outputs/flutter-apk/app-debug.apk"
    fi
    mkdir -p "$(dirname "$dst")"
    [[ -f "$src" ]] || { echo "build_apk: APK not found at $src" >&2; exit 1; }
    cp "$src" "$dst"
}

case "${1:-}" in
    aot)
        flutter_config release
        gradle_props Release
        JAVA_HOME="$(flutter_jdk)" capped "$APP/android/gradlew" -p "$APP/android" -q :app:compileFlutterBuildRelease "${PROPS[@]}"
        ;;
    native)
        flutter_config release
        gradle_props Release
        JAVA_HOME="$(flutter_jdk)" capped "$APP/android/gradlew" -p "$APP/android" -q :app:mergeReleaseNativeLibs :app:compileReleaseJavaWithJavac "${PROPS[@]}"
        ;;
    apk)
        flutter_config release
        gradle_props Release
        JAVA_HOME="$(flutter_jdk)" capped "$APP/android/gradlew" -p "$APP/android" -q :app:assembleRelease "${PROPS[@]}"
        copy_apk release
        ;;
    aot-debug)
        flutter_config debug
        gradle_props Debug
        JAVA_HOME="$(flutter_jdk)" capped "$APP/android/gradlew" -p "$APP/android" -q :app:compileFlutterBuildDebug "${PROPS[@]}"
        ;;
    native-debug)
        flutter_config debug
        gradle_props Debug
        JAVA_HOME="$(flutter_jdk)" capped "$APP/android/gradlew" -p "$APP/android" -q :app:mergeDebugNativeLibs :app:compileDebugJavaWithJavac "${PROPS[@]}"
        ;;
    apk-debug)
        flutter_config debug
        gradle_props Debug
        JAVA_HOME="$(flutter_jdk)" capped "$APP/android/gradlew" -p "$APP/android" -q :app:assembleDebug "${PROPS[@]}"
        copy_apk debug
        ;;
    *)
        echo "usage: $0 aot|native|apk|aot-debug|native-debug|apk-debug [android-arm64|android-x64]" >&2
        exit 2
        ;;
esac
