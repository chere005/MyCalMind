#!/bin/sh
# Deploy MyCalMind. There is no server and no web instance — the phone IS
# production — so "deploy" means: gate, prebuild, build a Release against the
# connected iPhone, and install it. The watch app installs separately at the
# end (devicectl, straight onto the watch) and this prints that command.
#
#   sh tools/deploy-device.sh              auto-detect the one connected iPhone
#   sh tools/deploy-device.sh <udid>       name the device
#   sh tools/deploy-device.sh --dry-run    print the plan, touch nothing
#
# The traps this script is shaped around (AGENTS.md has the stories):
#   · LANG must be UTF-8 or CocoaPods dies in unicode_normalize
#   · -destination 'platform=iOS,id=…', NEVER -sdk — -sdk overrides SDKROOT
#     for every target and compiles the watch against the iOS SDK
#   · build and install are TWO steps — devicectl installs onto a locked
#     phone; only a LAUNCH needs it awake. `expo run:ios --device` hangs there.
#   · no `… && echo done` endings — every step's own status is checked, so a
#     failed build cannot be reported as a deploy
set -e
cd "$(dirname "$0")/.."
ROOT="$(pwd)"

DRY=0; UDID=""
for a in "$@"; do
  case "$a" in
    --dry-run) DRY=1 ;;
    -*) echo "unknown flag: $a" >&2; exit 1 ;;
    *) UDID="$a" ;;
  esac
done

if [ "$DRY" = 1 ]; then
  echo "would: typecheck + core suite"
  echo "would: (cd app && LANG=en_US.UTF-8 npx expo prebuild --platform ios --clean)"
  echo "would: xcodebuild -workspace app/ios/*.xcworkspace -scheme <from workspace name>"
  echo "       -configuration Release -destination 'platform=iOS,id=<udid>'"
  echo "       -derivedDataPath app/ios/derived-dtp -allowProvisioningUpdates build"
  echo "would: xcrun devicectl device install app --device <udid> <MyCalMind.app>"
  exit 0
fi

# ------------------------------------------------------------------- the gates
echo "==> typecheck"
npm run -s typecheck || { echo "typecheck failed — not deploying" >&2; exit 1; }
echo "==> core"
npm run -s test:core -- --reporter=dot >/dev/null 2>&1 \
  || { echo "core tests failed — not deploying" >&2; exit 1; }

# ------------------------------------------------------------------ the device
# devicectl's table output changes between Xcode versions; the JSON does not.
if [ -z "$UDID" ]; then
  DEVJSON=$(mktemp -t mycalmind-devices)
  xcrun devicectl list devices --json-output "$DEVJSON" >/dev/null 2>&1 \
    || { echo "devicectl cannot list devices — is Xcode installed?" >&2; exit 1; }
  UDID=$(python3 - "$DEVJSON" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
phones = []
for dev in d.get('result', {}).get('devices', []):
    hw = dev.get('hardwareProperties', {})
    conn = dev.get('connectionProperties', {})
    if hw.get('platform') != 'iOS':
        continue
    if conn.get('tunnelState') in ('connected', 'available'):
        phones.append((dev.get('identifier', ''), dev.get('deviceProperties', {}).get('name', '?')))
if len(phones) == 1:
    print(phones[0][0])
else:
    for udid, name in phones:
        print(f'  {udid}  {name}', file=sys.stderr)
PY
)
  rm -f "$DEVJSON"
  if [ -z "$UDID" ]; then
    echo "refusing: no single connected iPhone found. Plug one in, or name it:" >&2
    echo "  sh tools/deploy-device.sh <udid>     (xcrun devicectl list devices)" >&2
    exit 1
  fi
fi
echo "==> device: $UDID"

# ----------------------------------------------------------------- the prebuild
# --clean, because app/ios is disposable prebuild output and a stale project
# is how a renamed app ships under its old name. LANG is not optional.
echo "==> prebuild (ios, clean)"
( cd app && LANG=en_US.UTF-8 npx expo prebuild --platform ios --clean ) \
  || { echo "prebuild failed — not deploying" >&2; exit 1; }

WS=$(ls -d "$ROOT"/app/ios/*.xcworkspace 2>/dev/null | head -1)
[ -n "$WS" ] || { echo "prebuild produced no xcworkspace under app/ios" >&2; exit 1; }
SCHEME=$(basename "$WS" .xcworkspace)
echo "==> workspace: $(basename "$WS")  scheme: $SCHEME"

# -------------------------------------------------------------------- the build
DERIVED="$ROOT/app/ios/derived-dtp"
echo "==> xcodebuild Release -> $DERIVED"
LOG=$(mktemp -t mycalmind-build)
if ! xcodebuild -workspace "$WS" -scheme "$SCHEME" -configuration Release \
    -destination "platform=iOS,id=$UDID" \
    -derivedDataPath "$DERIVED" -allowProvisioningUpdates build >"$LOG" 2>&1; then
  echo "build failed — last lines:" >&2
  tail -25 "$LOG" >&2
  echo "full log: $LOG" >&2
  exit 1
fi
rm -f "$LOG"

APP="$DERIVED/Build/Products/Release-iphoneos/$SCHEME.app"
[ -d "$APP" ] || { echo "the build reported success but $APP does not exist" >&2; exit 1; }

# ------------------------------------------------------------------ the install
# devicectl installs onto a locked phone; only launching needs it awake.
echo "==> install -> $UDID"
xcrun devicectl device install app --device "$UDID" "$APP" \
  || { echo "the install failed — is the phone paired with this Mac?" >&2; exit 1; }

echo "==> installed $SCHEME.app on $UDID"
WATCHAPP=$(ls -d "$APP"/Watch/*.app 2>/dev/null | head -1)
if [ -n "$WATCHAPP" ]; then
  echo "    the watch app installs separately, straight onto the watch:"
  echo "      xcrun devicectl list devices                # find the watch udid"
  echo "      xcrun devicectl device install app --device <watch-udid> \"$WATCHAPP\""
fi
