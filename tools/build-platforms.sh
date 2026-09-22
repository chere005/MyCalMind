#!/bin/sh
# The platform builds this repo ships for itself: the Mac Catalyst app into
# /Applications, an iOS Release built once and installed on every phone
# MyCalMind belongs on, and an Android build installed and launched on the
# local emulator. The watch companion app builds inside the iOS bundle;
# nothing here installs that — it is reported, and the watch install stays
# the explicit devicectl line in ARCHITECTURE.md.
#
#   sh tools/build-platforms.sh              all three
#   sh tools/build-platforms.sh --mac        just the Mac Catalyst bundle
#   sh tools/build-platforms.sh --ios        just the iOS build and its installs
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
#   · iOS BUILDS AND INSTALLS, since 2026-09-21. It used to build and stop,
#     and the reason was sound while it held: Apple's FREE team caps one
#     physical device at 3 installed apps, that budget went to
#     CalMind/ChefMind/AcctMind, and a release was not allowed to spend a
#     slot as a side effect of shipping. The reason has expired. The team
#     (2LGYTL3FSJ, "Sean Cheren") is PAID — its Xcode-managed profile carries
#     TimeToLive 365 where a personal team's carries 7 — so the 3-app cap
#     does not apply to it at all, and MyCalMind is in fact already sitting
#     on Sean's phone at 1.8.0. Sean, 2026-09-21: "no more caps per phone".
#     Any comment anywhere in this file that still rations installs against
#     that cap is stale and should be fixed, not worked around.
#     tools/deploy-device.sh remains the one-phone, run-it-yourself install
#     with its own gates in front; it is no longer the only way this app may
#     reach a handset.
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
  [ "$WANT_IOS" = 1 ]     && echo "would: prebuild $APPDIR (ios), xcodebuild Release against the first of this app's phones devicectl reports, then devicectl install that one bundle onto each of them"
  [ "$WANT_ANDROID" = 1 ] && echo "would: prebuild $APPDIR (android), gradlew assembleRelease, adb install"
  exit 0
fi

# --------------------------------------------------------------- the iOS project
# Shared by the catalyst step AND the iOS step, both of which build out of
# the same generated ios/ directory. $1, if given, is extra "VAR=val" env
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
      -allowProvisioningUpdates -allowProvisioningDeviceRegistration build >"$LOG" 2>&1; then
    echo "the macOS (Mac Catalyst) build failed — last lines:" >&2
    tail -25 "$LOG" >&2; echo "full log: $LOG" >&2; exit 1
  fi
  rm -f "$LOG"

  MACAPP="$DERIVED/Build/Products/Release-maccatalyst/$SCHEME.app"
  [ -d "$MACAPP" ] || { echo "the build succeeded and produced no $SCHEME.app" >&2; exit 1; }
  echo "    built: $MACAPP"

  # WAS IT OPEN? Sean, 2026-09-21: "make sure to reopen already opened apps in
  # a dtp.. i was looking at an old acctmind". Replacing the bundle under a
  # RUNNING app changes nothing he can see: macOS still has the old
  # executable and the old JS bundle mapped into the process it started, so
  # the window in front of him keeps showing the previous release for as long
  # as he leaves it open. That is how he spent an afternoon reading a stale
  # AcctMind while the very build he was waiting for was already live on the
  # web, on his phone AND in /Applications. Copying over a live bundle is the
  # other half of it — a half-replaced app bundle is its own kind of broken —
  # so the app is asked to quit BEFORE the rm/cp and put back afterwards.
  #
  # MATCH ON THE BUNDLE PATH, NEVER THE APP NAME. The executable inside a
  # bundle is not named after the bundle: AcctMind.app runs
  # Contents/MacOS/acctmind-desktop, so `pgrep -x AcctMind` finds nothing and
  # a feature written that way would silently do nothing for ever, which is
  # indistinguishable from the bug it was meant to fix. The path is derived
  # from $SCHEME — the same variable the install below uses — so the two
  # cannot end up disagreeing about which app this is.
  #
  # NONE OF THIS MAY FAIL THE RELEASE. Every step here is best-effort: the
  # release is the point, and a window that did not come back is a smaller
  # problem than a lane that went red over one.
  MACAPP_PROC="/Applications/$SCHEME.app/Contents/MacOS/"
  WAS_RUNNING=0
  if pgrep -f "$MACAPP_PROC" >/dev/null 2>&1; then
    WAS_RUNNING=1
    echo "    $SCHEME is running — quitting it so this release is what he sees"
    # A REQUEST, not a kill, and it never escalates to one. This app's
    # snapshot is the only copy of its data (AGENTS.md, "Ask what happens
    # when a write fails"), so a release has no business destroying unsaved
    # state to save itself a few seconds. If it will not go, say so and
    # install anyway — a stale window beats a skipped deploy.
    osascript -e "quit app \"$SCHEME\"" >/dev/null 2>&1 || true
    QWAIT=0
    while pgrep -f "$MACAPP_PROC" >/dev/null 2>&1; do
      sleep 1
      QWAIT=$((QWAIT + 1))
      [ "$QWAIT" -lt 8 ] || {
        echo "    WARNING: $SCHEME would not quit within 8s — installing over it anyway;" >&2
        echo "      quit it yourself and reopen it, or you are still looking at the old build" >&2
        break
      }
    done
  fi

  # INSTALL IT. A build sitting in derivedData is not a deploy — it is the
  # thing nobody looks at while the app in /Applications goes stale.
  rm -rf "/Applications/$SCHEME.app"
  cp -R "$MACAPP" /Applications/ \
    || { echo "copying $SCHEME.app into /Applications failed" >&2; exit 1; }
  echo "    installed: /Applications/$SCHEME.app"

  # AND GIVE HIM HIS WINDOW BACK — only if this run took it away. An app he
  # had CLOSED stays closed: a release that conjures windows onto his desktop
  # is its own annoyance, and the ask was to reopen "already opened apps",
  # not to launch everything it ships.
  if [ "$WAS_RUNNING" = 1 ]; then
    # ONLY A PROCESS THAT ACTUALLY WENT CAN BE BROUGHT BACK. If it ignored the
    # quit above it is still on screen running the PREVIOUS build, and `open`
    # would simply raise that stale window and exit 0 — so the lane log would
    # end on a cheerful "reopened" directly under its own warning, which is the
    # same false all-clear this whole block exists to kill. Re-check here
    # rather than trust the wait above: an app that took a second longer than
    # the timeout has still gone, and still deserves its window back.
    if pgrep -f "$MACAPP_PROC" >/dev/null 2>&1; then
      echo "    WARNING: $SCHEME never quit, so what is on screen is STILL the" >&2
      echo "      pre-release build — quit it and reopen it to see this one" >&2
    elif open -a "/Applications/$SCHEME.app" >/dev/null 2>&1; then
      echo "    reopened: $SCHEME — it was running before this release"
    else
      echo "    WARNING: could not reopen $SCHEME; the install itself is fine" >&2
    fi
  fi
fi

# --------------------------------------------------------------------- iOS
if [ "$WANT_IOS" = 1 ]; then
  echo "==> iOS"

  # THE PHONES THIS APP BELONGS ON. A release is not "install to the phone",
  # and it is not "install to every phone" either. Sean, 2026-09-21, after a
  # release reached one handset and stopped: "you should have dtp to all
  # platforms and all 3 phones and my watch", then the routing itself — "the
  # only apps installed on autumn's phone are ChefMind and CalMind",
  # "patricia's phone only gets CalMind", "my phone gets all 6 (including the
  # test ones)". Which handsets an app belongs on is therefore a FACT ABOUT
  # THE APP, written down here where the app ships from, and not a
  # consequence of which phone happened to answer devicectl this afternoon.
  # MyCalMind is a test build of the suite's own app, so it belongs on Sean's
  # phone and nowhere else.
  #
  # UDIDS, NEVER NAMES. Two of the three phones in the suite carry an
  # apostrophe in their name and one of those apostrophes is the CURLY
  # U+2018, which is exactly the sort of thing that matches in a test and
  # then not on the day; the udid is the one identifier devicectl, xcodebuild
  # and the provisioning profile all spell the same way. Everything after a
  # '#' on these lines is for the reader — the parse below drops it.
  #
  # IOS_PHONES in the environment replaces the list outright, for the run
  # where a handset is being brought up or taken out of service and nobody
  # wants to edit a released script to do it.
  if [ -z "${IOS_PHONES:-}" ]; then
    IOS_PHONES='
00008130-000E3D060E20001C   # iPhoooooone, Sean
'
  fi
  PHONES=$(printf '%s\n' "$IOS_PHONES" | sed 's/#.*//' | tr -s '[:space:]' '\n' | sed '/^$/d')
  [ -n "$PHONES" ] || { echo "IOS_PHONES is set to nothing — name at least one udid" >&2; exit 1; }

  # devicectl's table output changes between Xcode versions; the JSON does
  # not. What comes back is the UDID, not the CoreDevice identifier: devicectl
  # reports both, `identifier` being the CoreDevice UUID (6C4D04C6-…) and
  # `hardwareProperties.udid` the device's own (00008130-…), and they are not
  # interchangeable — xcodebuild's -destination matches a physical device by
  # udid and finds no destination at all when handed the other one, while
  # devicectl takes either, which is what would make the mistake look fine
  # right up until the build.
  DEVJSON=$(mktemp -t mycalmind-devices)
  xcrun devicectl list devices --json-output "$DEVJSON" >/dev/null 2>&1 \
    || { echo "devicectl cannot list devices — is Xcode installed?" >&2; exit 1; }
  SEEN=$(python3 - "$DEVJSON" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    raise SystemExit
for x in d.get('result', {}).get('devices', []):
    hw = x.get('hardwareProperties', {})
    if hw.get('platform') != 'iOS' or not hw.get('udid'):
        continue
    # tunnelState: a paired phone that is merely idle lists as 'disconnected'
    # until something warms the tunnel, and treating that as unreachable
    # skipped the iOS step of CalMind 1.17.0 with the phone sitting right
    # there (2026-08-30). Only 'unavailable' is a genuinely absent device.
    if x.get('connectionProperties', {}).get('tunnelState') not in ('connected', 'available', 'disconnected'):
        continue
    print('%s\t%s' % (hw['udid'], x.get('deviceProperties', {}).get('name', '?')))
PY
)
  rm -f "$DEVJSON"
  phone_name() { printf '%s\n' "$SEEN" | awk -F'\t' -v u="$1" '$1 == u { print $2; exit }'; }
  phone_seen() { printf '%s\n' "$SEEN" | cut -f1 | grep -qx "$1"; }

  # IOS_DEVICE wins over the list and narrows the whole step — build and
  # install — to the one reachable handset with that name. It is spelled the
  # same in every app's lane so that one command line aims any of them at one
  # phone; this lane gained it with the list, 2026-09-21. By NAME on purpose:
  # a name is what you have when someone hands you a phone, so it is how a
  # first build is aimed at a handset the team has never seen, and how a build
  # goes somewhere off the list without editing a released script. Copy the
  # name out of `xcrun devicectl list devices`; it is matched character for
  # character, curly apostrophe and all.
  #
  # Two reachable phones answering to one name is a refusal and not a coin
  # toss. Taking the first would put this app on somebody else's handset,
  # which is the single thing the list above exists to prevent.
  if [ -n "${IOS_DEVICE:-}" ]; then
    ONE=''; ONEN=0
    for _U in $(printf '%s\n' "$SEEN" | awk -F'\t' -v n="$IOS_DEVICE" '$2 == n { print $1 }'); do
      ONE="$_U"; ONEN=$((ONEN + 1))
    done
    [ "$ONEN" = 1 ] || {
      echo "IOS_DEVICE='$IOS_DEVICE' matches $ONEN reachable iPhones:" >&2
      printf '%s\n' "$SEEN" | awk -F'\t' 'NF { print "    seen: " $2 }' >&2
      exit 1
    }
    PHONES="$ONE"
  fi

  # Roll call before anything is built. A listed phone that devicectl does
  # not report, or reports as 'unavailable', is switched off or off the
  # network — a normal Tuesday, not a broken release — so it is noted and
  # skipped rather than failing the step. The note is the point: an absence
  # nobody printed is an absence nobody notices.
  TARGETS=""
  for U in $PHONES; do
    if phone_seen "$U"; then
      TARGETS="$TARGETS $U"
    else
      echo "    skipping $U — devicectl does not report it reachable (powered off, or off the network)"
    fi
  done
  [ -n "$TARGETS" ] || {
    echo "no phone from this app's list answered devicectl — nothing to build against" >&2
    echo "  Plug one in and unlock it, or name another: IOS_DEVICE='Some iPhone' sh tools/build-platforms.sh --ios" >&2
    exit 1
  }

  prebuild_ios || exit 1
  SCHEME=$(basename "$IOS_WS" .xcworkspace)
  DERIVED="$BUILD_SCRATCH/derived-platforms"
  echo "    workspace: $(basename "$IOS_WS")  scheme: $SCHEME"

  # ONE BUILD, and that one bundle goes to every phone below. The build has
  # to name a real handset rather than generic/platform=iOS, because building
  # against a device is what registers it: a phone the team has never seen is
  # refused by devicectl with a provisioning error, and after one build
  # against it its udid is in every profile Xcode-managed signing regenerates
  # from then on, so a plain install works.
  #
  # WHICH of the already-registered phones it builds against does not matter:
  # they are all in that same regenerated profile, the signed product is
  # identical either way, and the first one that answered is all the thought
  # it deserves. The case where it does matter is a handset nobody has built
  # against yet, and that is what IOS_DEVICE is for — one
  # `IOS_DEVICE='<its name>' sh tools/build-platforms.sh --ios` registers it,
  # once, and every run after that reaches it from the list.
  BUILD_UDID=$(printf '%s\n' $TARGETS | head -1)
  echo "    building against: $(phone_name "$BUILD_UDID") ($BUILD_UDID)"
  LOG=$(mktemp -t mycalmind-ios)
  # -destination with a specific device, never -sdk: -sdk overrides SDKROOT
  # for every target in the scheme, so the watch complication compiles
  # against the iOS SDK and dies on code that is perfectly correct.
  if ! xcodebuild -workspace "$IOS_WS" -scheme "$SCHEME" -configuration Release \
      -destination "platform=iOS,id=$BUILD_UDID" -derivedDataPath "$DERIVED" \
      -allowProvisioningUpdates build >"$LOG" 2>&1; then
    echo "the iOS build failed — last lines:" >&2
    tail -25 "$LOG" >&2; echo "full log: $LOG" >&2; exit 1
  fi
  rm -f "$LOG"
  BUNDLE="$DERIVED/Build/Products/Release-iphoneos/$SCHEME.app"
  [ -d "$BUNDLE" ] || { echo "the build succeeded and produced no $SCHEME.app" >&2; exit 1; }
  echo "    built: $BUNDLE"

  # NOW THAT ONE BUNDLE GOES ONTO EVERY PHONE THAT ANSWERED. devicectl
  # installs onto a LOCKED phone; only a launch needs it awake, which is why
  # build and install are two steps here and why `expo run:ios --device` hangs
  # (tools/deploy-device.sh's header). A refusal here is therefore never "the
  # screen was off". It is one of two things: the phone is not paired and
  # trusted with this Mac, or the team has never seen it and the profile
  # inside this bundle does not carry its udid, which devicectl reports as a
  # provisioning error. The second has the one-time cure described above,
  # which is the other reason a refusal warns and carries on rather than
  # taking a good release down with it.
  #
  # Retried ONCE per phone: the first call routinely times out while devicectl
  # brings up developer disk image services on a handset that has been idle,
  # and the second call, against the services the first one just started, goes
  # straight through.
  INSTALLED=0
  for U in $TARGETS; do
    PNAME=$(phone_name "$U")
    if xcrun devicectl device install app --device "$U" "$BUNDLE" \
       || xcrun devicectl device install app --device "$U" "$BUNDLE"; then
      INSTALLED=$((INSTALLED + 1))
      echo "    installed $SCHEME.app on $PNAME ($U)"
    else
      echo "    WARNING: $PNAME ($U) would not take $SCHEME.app — carrying on" >&2
      echo "      pair and trust this Mac on it, or register it once with" >&2
      echo "      IOS_DEVICE='$PNAME' sh tools/build-platforms.sh --ios, then:" >&2
      echo "      xcrun devicectl device install app --device $U \"$BUNDLE\"" >&2
    fi
  done

  # The watch companion rides inside the iOS bundle, so it belongs to the
  # BUILD and not to any one install — reported once, out here, whatever the
  # phones did. Installing it onto a watch is still its own devicectl call
  # (ARCHITECTURE.md, "Running it"); nothing in this lane does it.
  WATCHAPP=$(ls -d "$BUNDLE"/Watch/*.app 2>/dev/null | head -1)
  [ -n "$WATCHAPP" ] && echo "    built (watch companion): $WATCHAPP"

  # THE FAILURE IS "NOT ONE PHONE TOOK IT", not "a phone did not take it".
  # A release that reached two of three handsets shipped, and failing the
  # step over the third would hide that; a release that reached none is the
  # thing the old single install check was there to catch.
  [ "$INSTALLED" -gt 0 ] || {
    echo "no phone took $SCHEME.app — the build is at $BUNDLE" >&2
    exit 1
  }
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
