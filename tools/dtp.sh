#!/bin/sh
# dtp — deploy, tag, push. The release gesture for MyCalMind.
# tdtp — the same lane with the full test run in front: tools/tdtp.sh, which
# calls this with --full. (Sean's shorthand, 2026-08-22: dtp = deploy, tag,
# push; tdtp = test, deploy, tag, push.)
#
# There is no server and no web instance — "deploy" here is
# tools/deploy-device.sh: a Release build installed on the connected iPhone.
# (The old rule "CalMind-Local is not tagged" was about sharing CalMind's tag
# namespace; in its own repo, its own tags are the point.)
#
# What a run does, in order:
#   0. refuse a tree with uncommitted TRACKED changes — the tag must name
#      exactly what shipped
#   1. (--full only) typecheck + core suite up front (the deploy runs its own
#      gates as well; today the two lanes converge, and anything slower lands
#      in the full lane the day it exists)
#   2. version: if the current version is tagged, bump the MINOR
#      (x.y.0 → x.(y+1).0) in package.json + app/app.json and RESTART
#      ios.buildNumber/android.versionCode at 1 — a dtp is what puts a build
#      on the phone, and the build number is how two installs are told apart.
#      If the current version is still UNTAGGED (an earlier run failed before
#      tagging), reuse it and bump only the build number: a second build of
#      the same release is leaving the machine.
#   3. deploy: tools/deploy-device.sh [udid]
#   4. tag vX.Y.0 (annotated); 5. git push --follow-tags
#   A failed deploy stops everything — never tag around one.
set -e
cd "$(dirname "$0")/.."

FULL=0; UDID=""
for a in "$@"; do
  case "$a" in
    --full) FULL=1 ;;
    -*) echo "unknown flag: $a" >&2; exit 1 ;;
    *) UDID="$a" ;;
  esac
done

if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
  echo "refusing: uncommitted tracked changes — commit your work first, so the" >&2
  echo "tag names exactly what shipped:" >&2
  git status --porcelain --untracked-files=no | sed 's/^/  /' >&2
  exit 1
fi

if git remote get-url origin >/dev/null 2>&1; then
  git pull --autostash --quiet
fi

if [ "$FULL" = 1 ]; then
  echo "==> tdtp: the full run, before anything is touched"
  npm run -s typecheck || { echo "typecheck failed — nothing shipped" >&2; exit 1; }
  npm run -s test:core -- --reporter=dot || { echo "core suite failed — nothing shipped" >&2; exit 1; }
fi

# ------------------------------------------------------------------ the version
CUR=$(node -p "require('./package.json').version")
case "$CUR" in
  *[!0-9.]*|.*|*.|*..*) echo "package.json version '$CUR' is not x.y.z" >&2; exit 1 ;;
esac

BUILD=$(node -p "require('./app/app.json').expo.ios.buildNumber")
if git rev-parse -q --verify "refs/tags/v$CUR" >/dev/null; then
  NEW=$(echo "$CUR" | awk -F. '{printf "%d.%d.0", $1, $2+1}')
  NEWBUILD=1
  echo "==> version: $CUR (tagged) -> $NEW, build number restarts at 1"
else
  NEW="$CUR"
  NEWBUILD=$((BUILD + 1))
  echo "==> version: $CUR is still untagged from an earlier run — reusing it; build $BUILD -> $NEWBUILD"
fi

# Each substitution is VERIFIED below — a sed that matches nothing reports
# success (AcctMind's hard-learned lesson, not a hypothetical).
if [ "$NEW" != "$CUR" ]; then
  perl -i -pe "s|\"version\": \"\Q$CUR\E\"|\"version\": \"$NEW\"|" package.json app/app.json
fi
perl -i -pe "s|\"buildNumber\": \"\Q$BUILD\E\"|\"buildNumber\": \"$NEWBUILD\"|" app/app.json
perl -i -pe "s|\"versionCode\": \Q$BUILD\E,|\"versionCode\": $NEWBUILD,|" app/app.json
for F in package.json app/app.json; do
  grep -q "\"version\": \"$NEW\"" "$F" || { echo "guard: $F does not carry $NEW" >&2; exit 1; }
done
grep -q "\"buildNumber\": \"$NEWBUILD\"" app/app.json \
  || { echo "guard: app.json does not carry build $NEWBUILD" >&2; exit 1; }
grep -q "\"versionCode\": $NEWBUILD," app/app.json \
  || { echo "guard: app.json does not carry versionCode $NEWBUILD" >&2; exit 1; }

if ! git diff --quiet -- package.json app/app.json; then
  git add package.json app/app.json
  git commit -q -m "MyCalMind $NEW (build $NEWBUILD)"
  echo "==> committed the bump"
fi

# ------------------------------------------------------------------- the deploy
sh tools/deploy-device.sh $UDID

# ----------------------------------------------------------------- tag and push
git tag -a "v$NEW" -m "MyCalMind $NEW"
git push --follow-tags origin main
echo "==> dtp done: v$NEW (build $NEWBUILD) is on the phone and pushed"
