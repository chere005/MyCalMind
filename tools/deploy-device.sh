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
  # THE UDID, not the identifier. devicectl reports both — `identifier` is the
  # CoreDevice UUID (6C4D04C6-…) and `hardwareProperties.udid` is the device's
  # own (00008130-…) — and they are not interchangeable: xcodebuild's
  # `-destination 'platform=iOS,id=…'` matches a physical device by UDID, so
  # handing it the CoreDevice UUID fails to find any destination. devicectl
  # itself takes either, which is exactly what would have made this look fine
  # right up until the build step.
  DEVINFO=$(python3 - "$DEVJSON" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
ios, reachable = [], []
for dev in d.get('result', {}).get('devices', []):
    hw = dev.get('hardwareProperties', {})
    if hw.get('platform') != 'iOS':
        continue
    udid = hw.get('udid')
    if not udid:
        continue
    name = dev.get('deviceProperties', {}).get('name', '?')
    ios.append((udid, name))
    # tunnelState: a paired phone that is merely idle lists as 'disconnected'
    # until something warms the tunnel — treating that as unreachable skipped
    # the iOS step of CalMind 1.17.0 with the phone sitting right there
    # (2026-08-30). Only 'unavailable' is a genuinely absent device.
    if dev.get('connectionProperties', {}).get('tunnelState') in ('connected', 'available', 'disconnected'):
        reachable.append((udid, name))
if len(reachable) == 1:
    print('%s\t%s' % reachable[0])
else:
    # Nothing on stdout means "choose one yourself"; these go to the operator.
    for udid, name in (reachable or ios):
        print('  %s  %s' % (udid, name), file=sys.stderr)
    if not ios:
        print('  (devicectl knows no iOS device at all)', file=sys.stderr)
    elif not reachable:
        print('  (devicectl reports each of them unavailable — plug one in and unlock it)', file=sys.stderr)
PY
)
  rm -f "$DEVJSON"
  if [ -z "$DEVINFO" ]; then
    echo "refusing: no single reachable iPhone. Pick one from above and name it:" >&2
    echo "  sh tools/deploy-device.sh <udid>" >&2
    exit 1
  fi
  UDID=${DEVINFO%%	*}
  DEVNAME=${DEVINFO#*	}
fi
echo "==> device: $UDID${DEVNAME:+ ($DEVNAME)}"

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
