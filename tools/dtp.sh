#!/bin/sh
# dtp — deploy, tag, push. The release gesture for MyCalMind.
# tdtp — the same lane with the full test run in front: tools/tdtp.sh, which
# calls this with --full. (Sean's shorthand, 2026-08-22: dtp = deploy, tag,
# push; tdtp = test, deploy, tag, push.)
#
# THIS REPO SHIPS ITSELF (Sean, 2026-08-23: "all apps should have a deploy on
# their own mechanism inside their repo"). There is no server and no web
# instance — what a MyCalMind release ships is its platform builds, made by
# this repo's own tools/build-platforms.sh:
#   · macOS: a real Mac Catalyst app into /Applications — BEFORE the tag, so
#     a broken desktop build leaves the version untagged and a re-run reuses it
#   · Android: built, installed and launched on the local emulator — AFTER
#     the push, reported but never fatal
#   · iOS: BUILD-CHECKED only, never installed — AFTER the push, non-fatal.
#     The phone's free-team cap is 3 apps and Sean keeps MyCalMind off it
#     deliberately; tools/deploy-device.sh is the explicit install path and
#     is NOT part of this lane. (The watch companion builds inside the iOS
#     bundle; installing it is likewise explicit.)
# (The old rule "CalMind-Local is not tagged" was about sharing CalMind's tag
# namespace; in its own repo, its own tags are the point.)
#
# What a run does, in order:
#   0. refuse a wrong branch, then refuse CORE DRIFT (the gate below), then
#      refuse a tree with uncommitted TRACKED changes — the tag must name
#      exactly what shipped, and it must name a true clone
#   1. typecheck + core suite, EVERY run — see the gates below for why the
#      --full distinction no longer decides this
#   2. version: if the current version is tagged, bump the MINOR
#      (x.y.0 → x.(y+1).0) in package.json + app/app.json, RESTART
#      ios.buildNumber at 1 and INCREMENT android.versionCode — the two are
#      not the same kind of number: buildNumbers reset per marketing version,
#      versionCode is one monotonic integer per device, ever.
#      If the current version is still UNTAGGED (an earlier run failed before
#      tagging), reuse it and bump only the build number: a second build of
#      the same release is leaving the machine.
#   3. the Mac Catalyst bundle (tools/build-platforms.sh --mac) — BEFORE the
#      tag. A failed desktop build stops everything: never tag around one.
#   4. tag X.Y.0 (BARE — no v) (annotated); 5. git push --follow-tags
#   6. the device builds — Android on the emulator, then the iOS build check
#      — AFTER the push and reported rather than fatal: the release has
#      already happened, and an emulator that will not boot must not read as
#      a failed one. ONE AT A TIME, never in parallel — two heavy builds at
#      once has broken this machine twice.
#
# WHICH PLATFORMS: naming one selects only it, naming none means all of them —
# tools/build-platforms.sh's own convention.
set -e
cd "$(dirname "$0")/.."

FULL=0; PICKED=0; WANT_MAC=0; WANT_IOS=0; WANT_ANDROID=0
for a in "$@"; do
  case "$a" in
    --full)    FULL=1 ;;
    --mac)     WANT_MAC=1;     PICKED=1 ;;
    --ios)     WANT_IOS=1;     PICKED=1 ;;
    --android) WANT_ANDROID=1; PICKED=1 ;;
    # "the release and no platform builds" — what CoreMind's orchestrator
    # passes every self-shipping lane on a plain `dtp all`. This repo has no
    # web, so here it means: gates, bump, tag, push, build nothing.
    --web)     PICKED=1 ;;
    -*) echo "unknown flag: $a" >&2; exit 1 ;;
    # The positional used to be a device UDID for the phone install. That
    # install spends one of the phone's 3 free-team slots, so it is explicit
    # now, never a release side effect (see the header).
    *) echo "refusing: this lane no longer installs to the phone." >&2
       echo "  For the deliberate install: sh tools/deploy-device.sh $a" >&2
       exit 1 ;;
  esac
done
# --full is not a platform, so `tdtp` with no other flag still means all three.
[ "$PICKED" = 1 ] || { WANT_MAC=1; WANT_IOS=1; WANT_ANDROID=1; }

# ---------------------------------------------------------------- the branch
# The push below names main explicitly, so a lane run from any other branch
# would deploy and tag a tree it then does not push — while printing
# "pushed" and exiting 0.
BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$BRANCH" != "main" ]; then
  echo "refusing: this lane ships main, and HEAD is on '$BRANCH'" >&2
  exit 1
fi

# ------------------------------------------------------------- the core drift
# The clone must BE a clone when it ships. CoreMind's check proves every
# exact-row file here still carries the canon bytes; a release built on
# drifted core would tag a fork nobody decided on, under a version number that
# claims otherwise. Auto-rewriting source mid-release is not allowed — the
# gate makes the dependency LOUD instead, and the fix is CoreMind's own
# copy-down, run deliberately and committed before the lane runs again.
# No CoreMind checkout beside this repo is a warning, not a refusal — same
# stance as the status reporter below.
CHECKDRIFT="${MIND_DIR:-$(cd .. && pwd)}/CoreMind/bin/check-drift.sh"
if [ -f "$CHECKDRIFT" ]; then
  DRIFTOUT=$(sh "$CHECKDRIFT" MyCalMind 2>&1) || {
    printf '%s\n' "$DRIFTOUT" >&2
    echo "refusing: CoreMind's drift check failed for this repo — see above." >&2
    echo "  For DRIFT in exact rows, land the copy-down and re-run the lane:" >&2
    echo "    sh ../CoreMind/bin/deploy-core.sh --only MyCalMind" >&2
    exit 1
  }
else
  echo "   WARNING: no CoreMind checkout beside this repo — the core drift gate did not run" >&2
fi

# ------------------------------------------------------------- the status page
# A SINGLE-REPO RELEASE IS STILL A RELEASE. Sean, 2026-08-23: "i dont see the
# tdtp from ChefMind on status". CoreMind's bin/dtp.sh had reported to
# seancheren.com/status since the page existed; a repo shipping ITSELF did not,
# so the page went quiet for exactly the runs nobody else knew were coming — and
# the history graph recorded no purple for them at all.
#
# NEVER FATAL. report-status.sh exits 0 on every failure path by design, and the
# `|| true` here covers the case where CoreMind is not checked out beside this
# repo at all. A status page must never be the thing that stops a release.
REPORTER="${MIND_DIR:-$(cd .. && pwd)}/CoreMind/bin/report-status.sh"
RUN_ID=""
REPORT_DONE=0
if [ -f "$REPORTER" ]; then
  KIND=dtp; [ "$FULL" = 1 ] && KIND=tdtp
  RUN_ID=$(sh "$REPORTER" start "$KIND" MyCalMind 2>/dev/null || true)
  # A lane that dies anywhere — a failed deploy, a refused push, a Ctrl-C —
  # must not leave this repo purple on the page for ever.
  trap 'if [ -n "$RUN_ID" ] && [ "$REPORT_DONE" != 1 ]; then sh "$REPORTER" finish "$RUN_ID" failed 3 "stopped before finishing" >/dev/null 2>&1 || true; fi' EXIT INT TERM
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

# ------------------------------------------------------------------- the gates
# EVERY run, not just --full: tools/deploy-device.sh used to be this lane's
# deploy step and ran typecheck + core inside itself, so a plain dtp was never
# ungated — taking the phone install out of the lane must not take the gates
# out with it. --full stays the tdtp spelling; today the two lanes converge,
# and anything slower lands in the full lane the day it exists.
[ "$FULL" = 1 ] && echo "==> tdtp: the full run, before anything is touched"
npm run -s typecheck || { echo "typecheck failed — nothing shipped" >&2; exit 1; }
npm run -s test:core -- --reporter=dot || { echo "core suite failed — nothing shipped" >&2; exit 1; }

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
  # versionCode NEVER restarts. iOS buildNumbers reset per marketing version;
  # Android's versionCode is one device-wide monotonic integer, and resetting
  # it makes every install a DOWNGRADE the OS refuses. Paid for on 2026-08-23:
  # 1.1.0 shipped versionCode 1 against an emulator holding 4 —
  # INSTALL_FAILED_VERSION_DOWNGRADE, on the release's own lane.
  NEWCODE=$((VCODE + 1))
  echo "==> version: $CUR (tagged) -> $NEW, build 1, versionCode $VCODE -> $NEWCODE"
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

# ------------------------------------------------------------------ the desktop
# The Mac Catalyst bundle, BEFORE the tag — the suite's safety order: a broken
# desktop build leaves the version untagged, so a re-run reuses it, exactly as
# a failed deploy does in the repos that have one. This is the build a release
# must prove; it is also the closest thing MyCalMind has to a deploy, since
# the web has none and the phone is out of the lane on purpose.
if [ "$WANT_MAC" = 1 ]; then
  if ! sh tools/build-platforms.sh --mac; then
    echo "" >&2
    echo "THE MAC CATALYST BUILD FAILED — so nothing was tagged." >&2
    echo "  Fix it and re-run: the lane reuses ${NEW} (build ${NEWBUILD})." >&2
    exit 1
  fi
fi

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
  echo "THE MAC BUNDLE IS BUILT AND INSTALLED, but the push was rejected — so" >&2
  echo "  nothing was tagged. main has moved on the remote. Pull, then re-run:" >&2
  echo "  the lane reuses ${NEW}." >&2
  exit 1
fi
echo "==> pushed, tagged $NEW"

# ------------------------------------------------------------- the device builds
# After the push, and NOT fatal. The release is done by here — the tag is on
# the remote, the Mac bundle is in /Applications — so an emulator that will
# not boot, or an iOS toolchain hiccup, is a thing to be told about, not a
# failed release to unpick.
#
# One at a time, never in parallel: two heavy build/device processes at once
# has caused real failures on this machine twice (AGENTS.md).
DEVICE_FAILED=""
if [ "$WANT_ANDROID" = 1 ]; then
  sh tools/build-platforms.sh --android || DEVICE_FAILED="$DEVICE_FAILED --android"
fi
# The iOS run is a BUILD CHECK — it compiles Release (watch companion
# included) and stops; nothing touches the phone (see the header).
if [ "$WANT_IOS" = 1 ]; then
  sh tools/build-platforms.sh --ios || DEVICE_FAILED="$DEVICE_FAILED --ios"
fi
if [ -n "$DEVICE_FAILED" ]; then
  echo "" >&2
  echo "$NEW IS TAGGED AND PUSHED. These platform builds did not finish:$DEVICE_FAILED" >&2
  echo "  Re-run just those, once the machine is ready:" >&2
  echo "    sh tools/build-platforms.sh$DEVICE_FAILED" >&2
fi

# The page is told how it ended, and with what severity: a live, tagged release
# whose phone build did not run is not a failure, but it is not a clean 0 either.
REPORT_DONE=1
if [ -n "$RUN_ID" ]; then
  if [ -n "$DEVICE_FAILED" ]; then
    sh "$REPORTER" finish "$RUN_ID" ok 2 "$NEW live; device builds pending:$DEVICE_FAILED" >/dev/null 2>&1 || true
  else
    sh "$REPORTER" finish "$RUN_ID" ok 0 "$NEW live" >/dev/null 2>&1 || true
  fi
fi

echo "==> dtp done: $NEW (build $NEWBUILD) is tagged and pushed"
