#!/bin/sh
# The platform builds this repo ships for itself: the Mac Catalyst app into
# /Applications, an iOS Release BUILD CHECK (never an install), and an Android
# build installed and launched on the local emulator. The watch companion app
# builds inside the iOS bundle; nothing here installs that either.
#
#   sh tools/build-platforms.sh              all three
#   sh tools/build-platforms.sh --mac        just the Mac Catalyst bundle
#   sh tools/build-platforms.sh --ios        just the iOS build check
#   sh tools/build-platforms.sh --android    just the emulator
#   sh tools/build-platforms.sh --dry-run    print the plan
#
# Flags compose, and naming none means all three — the same positive selection
# the rest of the suite uses, because zeroing the OTHERS per flag does not
# compose past two.
#
# WHY THIS LIVES HERE. These builds were rows in CoreMind's table-driven
# bin/build-platforms.sh, and this repo's own lane shipped the phone install
# and nothing else. Sean, 2026-08-23: "all apps should have a deploy on their
# own mechanism inside their repo" — so the machinery is HERE, the dtp lane
# runs it, and CoreMind orchestrates ACROSS apps by calling each app's own
# lane rather than reaching into it. This is a copy-down, like packages/core —
# CoreMind's script is the origin and its comments are the record of what each
# line cost to learn; tools/patch-rndeps-catalyst.js is copied from there
# VERBATIM for the same reason (its "bin/" self-reference means CoreMind's
# bin, where the origin lives).
#
# What is deliberate about this app's rows:
#   · macOS is a REAL Mac Catalyst build — an iOS product run on macOS, not a
#     Tauri shell; there is no web export for one to stage, because MyCalMind
#     has no web instance at all. Proven working 2026-08-22 after a 26-attempt
#     chase (AGENTS.md has the full story).
#   · iOS builds and STOPS. Apple's free team caps the phone at 3 installed
#     apps, that budget is spent on CalMind/ChefMind/AcctMind, and Sean keeps
#     MyCalMind off the phone on purpose. tools/deploy-device.sh is the
#     explicit install path for the day it should take a slot — nothing here
#     may spend one as a side effect of a release.
set -e
cd "$(dirname "$0")/.."
ROOT="$(pwd)"
APPDIR="app"

# ------------------------------------------------------------------- argv
DRY=0; PICKED=0; WANT_MAC=0; WANT_IOS=0; WANT_ANDROID=0
while [ $# -gt 0 ]; do
  case "$1" in
    --mac)        WANT_MAC=1;     PICKED=1 ;;
    --ios)        WANT_IOS=1;     PICKED=1 ;;
    --android)    WANT_ANDROID=1; PICKED=1 ;;
    --dry-run)    DRY=1 ;;
    *) echo "unknown flag: $1" >&2; exit 1 ;;
  esac
  shift
done
[ "$PICKED" = 1 ] || { WANT_MAC=1; WANT_IOS=1; WANT_ANDROID=1; }

# Xcode derivedData and gradle's home stay on the INTERNAL disk, deliberately.
# A scratch volume mounted exFAT was tried on 2026-08-22 and reverted: exFAT
# cannot store the extended attributes codesign needs, so any signed product
# gets a "._<name>" AppleDouble sidecar that codesign then tries to sign as a
# subcomponent and fails on. The same root cause broke gradle's cache there in
# the same session. Large and untracked is a real cost; it has to be paid.
BUILD_SCRATCH="$ROOT/$APPDIR/ios"

if [ "$DRY" = 1 ]; then
  [ "$WANT_MAC" = 1 ]     && echo "would: clean source-build prebuild (ios), patch-rndeps-catalyst.js, xcodebuild for 'platform=macOS,variant=Mac Catalyst,arch=arm64', install to /Applications"
  [ "$WANT_IOS" = 1 ]     && echo "would: prebuild $APPDIR (ios), xcodebuild Release for generic/platform=iOS — BUILD ONLY, not installed"
  [ "$WANT_ANDROID" = 1 ] && echo "would: prebuild $APPDIR (android), gradlew assembleRelease, adb install"
  exit 0
fi

# --------------------------------------------------------------- the iOS project
# Shared by the catalyst step AND the iOS build check, both of which build out
# of the same generated ios/ directory. $1, if given, is extra "VAR=val" env
# exported just for the prebuild command. LANG is not optional: CocoaPods dies
# in unicode_normalize without a UTF-8 locale, naming nothing useful.
IOS_WS=""
run_prebuild() {
  ( cd "$ROOT/$APPDIR" && eval "${1:-}" LANG=en_US.UTF-8 npx expo prebuild --platform ios --clean ) \
    || { echo "prebuild failed" >&2; return 1; }
  IOS_WS=$(ls -d "$ROOT/$APPDIR"/ios/*.xcworkspace 2>/dev/null | head -1)
  [ -n "$IOS_WS" ] || { echo "prebuild produced no xcworkspace" >&2; return 1; }
}
prebuild_ios() {
  [ -n "$IOS_WS" ] && return 0
  IOS_WS=$(ls -d "$ROOT/$APPDIR"/ios/*.xcworkspace 2>/dev/null | head -1)
  [ -n "$IOS_WS" ] && return 0
  run_prebuild ""
}

# ------------------------------------------------------------------- macOS
if [ "$WANT_MAC" = 1 ]; then
  echo "==> macOS (Mac Catalyst)"
  # ALWAYS a clean prebuild here, even when app/ios already exists. Expo's
  # prebuilt XCFrameworks (ExpoModulesCore and friends) carry NO maccatalyst
  # slice at all in this SDK version — confirmed via ExpoModulesCore's own
  # Info.plist, which lists only ios-arm64 and ios-arm64_x86_64-simulator —
  # so every module must build FROM SOURCE, and RCT_USE_PREBUILT_RNCORE=0
  # does the same for React Native's own core. Both variables act at
  # POD-INSTALL time: a workspace left behind by a PLAIN prebuild (which
  # tools/deploy-device.sh makes on every run) references the prebuilt
  # frameworks and fails this build deterministically, in linker errors that
  # name none of this. Reusing it is the trap; the clean prebuild is the
  # cost. The project-side enabling (SUPPORTS_MACCATALYST on app and widget,
  # the watch targets filtered out) is app/plugins/withMacCatalyst.js —
  # committed, so it survives every prebuild.
  run_prebuild "EXPO_USE_PRECOMPILED_MODULES=0 RCT_USE_PREBUILT_RNCORE=0" || exit 1
  SCHEME=$(basename "$IOS_WS" .xcworkspace)
  DERIVED="$BUILD_SCRATCH/derived-mac"
  echo "    workspace: $(basename "$IOS_WS")  scheme: $SCHEME"

  # ReactNativeDependencies.xcframework (folly/glog/boost — React Native's
  # third-party C++ deps) has NO source-build option and DOES ship a
  # maccatalyst slice, but that slice's bundle is malformed and codesign
  # refuses it as shipped. Worse, the "[CP-User] [RNDeps] Replace React
  # Native Dependencies" phase is alwaysOutOfDate and re-extracts the
  # pristine broken bundle on EVERY build, so a repair applied before
  # xcodebuild is wiped moments later — the fix is patched INTO that phase
  # of the generated Pods pbxproj instead, re-applied after every prebuild.
  # tools/patch-rndeps-catalyst.js carries the full story.
  node "$ROOT/tools/patch-rndeps-catalyst.js" "$ROOT/$APPDIR/ios/Pods/Pods.xcodeproj/project.pbxproj" \
    || { echo "could not patch ReactNativeDependencies' Catalyst bundle" >&2; exit 1; }

  LOG=$(mktemp -t mycalmind-mac)
  # arm64-only: there is no x86_64 Catalyst slice anywhere upstream (see the
  # ExpoModulesCore note above), so an x86_64 attempt fails deterministically,
  # not intermittently. This machine is Apple Silicon; arm64-only is the
  # correct scope, not a workaround.
  if ! xcodebuild -workspace "$IOS_WS" -scheme "$SCHEME" -configuration Release \
      -destination "platform=macOS,variant=Mac Catalyst,arch=arm64" \
      -derivedDataPath "$DERIVED" ARCHS=arm64 \
      -allowProvisioningUpdates build >"$LOG" 2>&1; then
    echo "the macOS (Mac Catalyst) build failed — last lines:" >&2
    tail -25 "$LOG" >&2; echo "full log: $LOG" >&2; exit 1
  fi
  rm -f "$LOG"

  MACAPP="$DERIVED/Build/Products/Release-maccatalyst/$SCHEME.app"
  [ -d "$MACAPP" ] || { echo "the build succeeded and produced no $SCHEME.app" >&2; exit 1; }
  echo "    built: $MACAPP"
  # INSTALL IT. A build sitting in derivedData is not a deploy — it is the
  # thing nobody looks at while the app in /Applications goes stale.
  rm -rf "/Applications/$SCHEME.app"
  cp -R "$MACAPP" /Applications/ \
    || { echo "copying $SCHEME.app into /Applications failed" >&2; exit 1; }
  echo "    installed: /Applications/$SCHEME.app"
fi

# --------------------------------------------------------------------- iOS
if [ "$WANT_IOS" = 1 ]; then
  # Prove the iOS build compiles and stop there — see the header for why
  # nothing here may touch the phone.
  echo "==> iOS — BUILD ONLY, not installed (the free-team device slot is spent on purpose)"
  prebuild_ios || exit 1
  SCHEME=$(basename "$IOS_WS" .xcworkspace)
  DERIVED="$BUILD_SCRATCH/derived-platforms"
  echo "    workspace: $(basename "$IOS_WS")  scheme: $SCHEME"
  LOG=$(mktemp -t mycalmind-ios)
  # -destination generic/platform=iOS, never -sdk: -sdk overrides SDKROOT for
  # every target in the scheme, so the watch complication compiles against the
  # iOS SDK and dies on code that is perfectly correct.
  if ! xcodebuild -workspace "$IOS_WS" -scheme "$SCHEME" -configuration Release \
      -destination "generic/platform=iOS" -derivedDataPath "$DERIVED" \
      -allowProvisioningUpdates build >"$LOG" 2>&1; then
    echo "the iOS build failed — last lines:" >&2
    tail -25 "$LOG" >&2; echo "full log: $LOG" >&2; exit 1
  fi
  rm -f "$LOG"
  BUNDLE="$DERIVED/Build/Products/Release-iphoneos/$SCHEME.app"
  [ -d "$BUNDLE" ] || { echo "the build succeeded and produced no $SCHEME.app" >&2; exit 1; }
  echo "    built: $BUNDLE"
  # The watch companion rides inside the iOS bundle, so this build check
  # proves it too — and installing it is just as deliberate as the phone.
  WATCHAPP=$(ls -d "$BUNDLE"/Watch/*.app 2>/dev/null | head -1)
  [ -n "$WATCHAPP" ] && echo "    built (watch companion): $WATCHAPP"
  echo "    NOT installed — the phone slot is managed by tools/deploy-device.sh;"
  echo "    run that if MyCalMind should go on the phone"
fi

# ----------------------------------------------------------------- Android
if [ "$WANT_ANDROID" = 1 ]; then
  echo "==> Android"
  export ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
  export ANDROID_SDK_ROOT="$ANDROID_HOME"
  export PATH="$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$PATH"
  [ -d "$ANDROID_HOME" ] || { echo "no Android SDK at \$ANDROID_HOME ($ANDROID_HOME)" >&2; exit 1; }
  command -v adb >/dev/null || { echo "adb not on PATH under \$ANDROID_HOME" >&2; exit 1; }

  # A device already reachable — real hardware or an emulator someone left
  # running — wins outright; nothing here boots a second one on top of it.
  SERIAL=$(adb devices | awk 'NR>1 && $2=="device" {print $1; exit}')
  if [ -z "$SERIAL" ]; then
    AVD="${ANDROID_AVD:-}"
    if [ -z "$AVD" ]; then
      # `avdmanager` reports a system image as installed from its OWN
      # metadata, which can be stale — one on this machine names a directory
      # that does not exist. Each candidate is checked on DISK.
      for CAND in $(emulator -list-avds 2>/dev/null); do
        IMG=$(sed -n 's/^image\.sysdir\.1=//p' "$HOME/.android/avd/$CAND.avd/config.ini" 2>/dev/null)
        if [ -n "$IMG" ] && [ -d "$ANDROID_HOME/$IMG" ]; then AVD="$CAND"; break; fi
      done
    fi
    [ -n "$AVD" ] || { echo "no Android emulator running and no bootable AVD found" >&2; exit 1; }
    echo "    booting $AVD"
    nohup emulator -avd "$AVD" -no-snapshot-load -no-boot-anim -netdelay none -netspeed full \
      >"/tmp/mycalmind-emulator-$AVD.log" 2>&1 &
    disown 2>/dev/null || true
    i=0
    while [ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" != "1" ]; do
      sleep 5; i=$((i + 1))
      [ "$i" -le 72 ] || { echo "$AVD did not finish booting within 6 minutes" >&2; exit 1; }
    done
    SERIAL=$(adb devices | awk 'NR>1 && $2=="device" {print $1; exit}')
    [ -n "$SERIAL" ] || { echo "$AVD booted but adb sees no device" >&2; exit 1; }
  fi
  echo "    device: $SERIAL"

  ( cd "$ROOT/$APPDIR" && LANG=en_US.UTF-8 npx expo prebuild --platform android --clean ) \
    || { echo "android prebuild failed" >&2; exit 1; }

  # assembleRelease, not debug: gradle here signs BOTH build types with the
  # auto-generated debug keystore (there is no release keystore in the suite),
  # so release installs exactly as easily and is what a real release uses.
  # A build killed by a full disk leaves a Gradle LOCK behind and the next run
  # fails in under a second — `./gradlew --stop` and remove app/android/.gradle.
  ( cd "$ROOT/$APPDIR/android" && ANDROID_HOME="$ANDROID_HOME" ./gradlew assembleRelease ) \
    || { echo "the Android build failed" >&2; exit 1; }

  APK=$(find "$ROOT/$APPDIR/android/app/build/outputs/apk" -name "*.apk" 2>/dev/null | head -1)
  [ -n "$APK" ] || { echo "the Android build produced no APK" >&2; exit 1; }

  # Package and launch activity read OFF THE BUILT APK via aapt, not guessed
  # from app.json — the source of truth for what just got built.
  AAPT=$(ls "$ANDROID_HOME"/build-tools/*/aapt 2>/dev/null | sort -V | tail -1)
  [ -n "$AAPT" ] || { echo "no aapt under \$ANDROID_HOME/build-tools" >&2; exit 1; }
  BADGING=$("$AAPT" dump badging "$APK")
  PKG=$(printf '%s\n' "$BADGING" | sed -n "s/^package: name='\([^']*\)'.*/\1/p")
  ACTIVITY=$(printf '%s\n' "$BADGING" | sed -n "s/^launchable-activity: name='\([^']*\)'.*/\1/p")
  [ -n "$PKG" ] && [ -n "$ACTIVITY" ] \
    || { echo "could not read package/activity from the built APK" >&2; exit 1; }

  adb -s "$SERIAL" install -r "$APK" || { echo "adb install failed" >&2; exit 1; }
  adb -s "$SERIAL" shell am start -n "$PKG/$ACTIVITY" >/dev/null \
    || { echo "the app installed but would not launch" >&2; exit 1; }
  # Polled, not one sleep-then-check: a cold RN launch loads a dozen native
  # libraries before the process is fully up, and 5 seconds flat once reported
  # "not running" for a process ps showed alive a moment later.
  RUNNING=0
  for _ in 1 2 3 4 5 6; do
    if adb -s "$SERIAL" shell "ps -A" 2>/dev/null | grep -q "$PKG"; then RUNNING=1; break; fi
    sleep 3
  done
  [ "$RUNNING" = 1 ] || { echo "installed and launched but never showed up running" >&2; exit 1; }
  echo "    installed and running: $PKG on $SERIAL"
fi
