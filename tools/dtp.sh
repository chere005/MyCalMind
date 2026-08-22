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
#   4. tag X.Y.0 (BARE — no v) (annotated); 5. git push --follow-tags
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

# ---------------------------------------------------------------- the branch
# The push below names main explicitly, so a lane run from any other branch
# would deploy and tag a tree it then does not push — while printing
# "pushed" and exiting 0.
BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$BRANCH" != "main" ]; then
  echo "refusing: this lane ships main, and HEAD is on '$BRANCH'" >&2
  exit 1
fi

# ------------------------------------------------------- the tree, then a pull
# The dirty check runs FIRST and again AFTER the pull. `git pull --autostash`
# exits 0 even when the autostash pop CONFLICTS — proven, not assumed — so a
# pull that goes first can leave conflict markers in the tree with set -e none
# the wiser, and the lane would deploy them.
refuse_dirty() {
  if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
    echo "refusing: $1" >&2
    git status --porcelain --untracked-files=no | sed 's/^/  /' >&2
    exit 1
  fi
}
refuse_dirty "uncommitted tracked changes — commit your work first, so the tag names exactly what shipped"

if git remote get-url origin >/dev/null 2>&1; then
  git pull --autostash --quiet
  refuse_dirty "the pull left the tree dirty — a conflicted autostash pop exits 0, so this is the check that catches it"
fi

if [ "$FULL" = 1 ]; then
  echo "==> tdtp: the full run, before anything is touched"
  npm run -s typecheck || { echo "typecheck failed — nothing shipped" >&2; exit 1; }
  npm run -s test:core -- --reporter=dot || { echo "core suite failed — nothing shipped" >&2; exit 1; }
fi

# ------------------------------------------------------------------ the version
CUR=$(node -p "require('./package.json').version")
# x.y.z, three digit parts, nothing else. The glob this replaces claimed to
# reject anything else and accepted '', '1', '1.2' and '1.2.3.4' — and an
# EMPTY version flowed on into `git rev-parse refs/tags/v` and a tag named `v`.
printf '%s\n' "$CUR" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$' \
  || { echo "package.json version '$CUR' is not x.y.z" >&2; exit 1; }

BUILD=$(node -p "require('./app/app.json').expo.ios.buildNumber")
# android.versionCode is its OWN number, read on its own. It was patched using
# the iOS build number as the match source, which is only correct while the two
# happen to agree — and the day they drift, that substitution matches nothing,
# reports success, and ships an Android build whose code never moved.
VCODE=$(node -p "require('./app/app.json').expo.android.versionCode")
# `$((BUILD + 1))` is arithmetic, and /bin/sh DIES on it (exit 127, "invalid
# arithmetic operator") if the value is dotted — "3.1" is a legal
# CFBundleVersion — while a missing key arrives as the string "undefined" and
# evaluates to 0, silently. Both are refused here, where the message can name
# the field.
for N in "$BUILD:ios.buildNumber" "$VCODE:android.versionCode"; do
  case "${N%%:*}" in
    ''|*[!0-9]*) echo "refusing: ${N#*:} is '${N%%:*}' — this lane needs a plain integer" >&2; exit 1 ;;
  esac
done
if git rev-parse -q --verify "refs/tags/$CUR" >/dev/null; then
  NEW=$(echo "$CUR" | awk -F. '{printf "%d.%d.0", $1, $2+1}')
  NEWBUILD=1
  NEWCODE=1
  echo "==> version: $CUR (tagged) -> $NEW, build number restarts at 1"
else
  NEW="$CUR"
  NEWBUILD=$((BUILD + 1))
  NEWCODE=$((VCODE + 1))
  echo "==> version: $CUR is still untagged from an earlier run — reusing it; build $BUILD -> $NEWBUILD"
fi

# A leftover $NEW would make `git tag -a` fail AFTER the deploy has already
# shipped. Checked HERE, while nothing has been touched yet.
if git rev-parse -q --verify "refs/tags/$NEW" >/dev/null; then
  echo "refusing: the tag $NEW already exists — nothing has shipped yet." >&2
  echo "  It is the residue of an interrupted lane: look at it, then delete it" >&2
  echo "  or move the version on." >&2
  exit 1
fi

# Each substitution is VERIFIED below — a sed that matches nothing reports
# success (AcctMind's hard-learned lesson, not a hypothetical).
if [ "$NEW" != "$CUR" ]; then
  perl -i -pe "s|\"version\": \"\Q$CUR\E\"|\"version\": \"$NEW\"|" package.json app/app.json
fi
perl -i -pe "s|\"buildNumber\": \"\Q$BUILD\E\"|\"buildNumber\": \"$NEWBUILD\"|" app/app.json
perl -i -pe "s|(\"versionCode\":\s*)\Q$VCODE\E\b|\${1}$NEWCODE|" app/app.json
for F in package.json app/app.json; do
  grep -q "\"version\": \"$NEW\"" "$F" || { echo "guard: $F does not carry $NEW" >&2; exit 1; }
done
grep -q "\"buildNumber\": \"$NEWBUILD\"" app/app.json \
  || { echo "guard: app.json does not carry build $NEWBUILD" >&2; exit 1; }
grep -qE "\"versionCode\":\s*$NEWCODE\b" app/app.json \
  || { echo "guard: app.json does not carry versionCode $NEWCODE" >&2; exit 1; }

# The lock mirrors these version numbers, and npm rewrites it on the next
# install if they disagree — which lands as "uncommitted tracked changes" in
# the NEXT lane, about a file nobody edited. The diff is bounded here because
# a script that rewrites a 300KB lock deserves a check that it changed only
# what it said it would.
echo "==> package-lock.json"
node tools/sync-lock-versions.mjs
LOCKDIFF=$(git diff --numstat -- package-lock.json | awk '{print $1 + $2}')
if [ -n "$LOCKDIFF" ] && [ "$LOCKDIFF" -gt 30 ]; then
  echo "guard: the lock sync changed $LOCKDIFF lines — that is more than version fields" >&2
  git checkout -- package-lock.json
  exit 1
fi

if ! git diff --quiet -- package.json app/app.json package-lock.json; then
  git add package.json app/app.json package-lock.json
  git commit -q -m "MyCalMind $NEW (build $NEWBUILD)"
  echo "==> committed the bump"
fi

# ------------------------------------------------------------------- the deploy
sh tools/deploy-device.sh $UDID

# ----------------------------------------------------------------- tag and push
git tag -a "$NEW" -m "MyCalMind $NEW"
# --atomic, because `git push --follow-tags` is per-ref: when origin/main has
# moved under a long deploy, the TAG lands on the remote while main is
# REJECTED — a published tag for a commit nobody can fetch. Both or neither.
#
# And if it is neither, the local tag comes straight back off. The version is
# then still untagged, so a re-run REUSES it — which is right, because the
# deploy above already shipped exactly these bytes under that number.
if ! git push --atomic --follow-tags origin main; then
  git tag -d "$NEW" >/dev/null
  echo "" >&2
  echo "THE DEPLOY SHIPPED, but the push was rejected — so nothing was tagged." >&2
  echo "  main has moved on the remote. Pull, then re-run: the lane reuses ${NEW}." >&2
  exit 1
fi
echo "==> dtp done: $NEW (build $NEWBUILD) is on the phone and pushed"
