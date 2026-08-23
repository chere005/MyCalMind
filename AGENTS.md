# Working in MyCalMind

CalMind with the server taken out — a CLONE of CalMind's `apps/app` and
`packages/core`, not a rewrite. `README.md` is the map.

The baseline for all of Sean's repos lives in ~/GIT/AgentSuite/AGENTS.md
and is imported here; this file holds only what is true of THIS repo.
@../AgentSuite/AGENTS.md

Until 2026-08-22 this lived inside the CalMind repo as `CalMind-Local`; it was
extracted — history preserved — into its own repo and renamed MyCalMind. The
upstream it clones is `~/GIT/CalMind` (github.com/chere005/CalMind).

## Standing rules

- **It is a clone, so keep it one.** A fix that belongs to the product belongs
  upstream in CalMind first and gets copied down — across repos now, which
  makes the copying a deliberate act rather than a shared working tree.
  Diverging by hand is how the two stop being the same app, which is the
  entire value of this being a copy.
- **The lane REFUSES to ship drifted core — that rule made enforceable.**
  Before it touches anything, `tools/dtp.sh` runs CoreMind's
  `bin/check-drift.sh MyCalMind`, which proves every exact-row file here still
  carries the canon bytes; a failure stops the WHOLE lane, because a release
  built on drifted core tags a fork nobody decided on, under a version number
  claiming it is still the clone. The lane will not rewrite source to make
  itself pass — the fix is the copy-down, run deliberately and committed
  first: `sh ../CoreMind/bin/deploy-core.sh --only MyCalMind`. No CoreMind
  checkout beside this repo is a WARNING, not a refusal: the gate could not
  run, and that is a different thing from having failed.
- **The rename was display-deep, and stays that way.** MyCalMind is the NAME:
  app.json's `name`/`slug`, the three targets' `displayName`s, the strings on
  screen, the docs. The IDENTITY did not move and must not:
  `com.seancheren.calmindlocal` (bundle ids), `group.com.seancheren.calmindlocal`
  (the App Group four Swift files read), `_calmind-local._tcp` (Bonjour — how
  paired devices find each other), and every persisted key
  (`calmind.local.snapshot`, `calmind.local.peer.*`, `calmind.folded.*`, …).
  Renaming any of those orphans the on-device store or breaks pairing — the
  data IS the device's only copy, so that is the one unrecoverable mistake
  this repo offers.
- **Nothing may reference the server.** No URL of his, no token, no
  `serverUrl`. If a feature needs one it does not belong here — take it out
  rather than stubbing it, so nobody later mistakes a stub for a gap.
- **One `fetch` exists, and it is the recipe importer.** Sean, 2026-08-21:
  reading a recipe URL he pasted is fine, everything else stays on the device
  or on a paired one. It goes through `src/recipefetch.ts` and
  `core/fetchguard.ts` and nowhere else — a second caller of `fetch` in this
  app is a bug until he says otherwise. The guard refuses this device and this
  network, `.local` included, because that is where the Bonjour peers are.
- **`npm test` and `npm run typecheck` are the gates.** `npm test` runs
  `packages/core`'s vitest suite (`TZ=America/Chicago` — the spec fixtures are
  timezone-sensitive); `npm run typecheck` runs `tsc --noEmit` against the app
  workspace. The lane runs BOTH on every run — they used to live inside
  `deploy-device.sh`, which stopped fronting the lane on 2026-08-23, and
  taking the phone install out must not have taken the gates with it. A
  failing gate stops the lane rather than shipping around it. There is no
  lint script in this repo; don't invent one.
- **`npm run dtp` / `npm run tdtp`** (tools/dtp.sh, tools/tdtp.sh). There is
  no server and no web instance, so what a release ships is its platform
  builds, made by this repo's OWN `tools/build-platforms.sh` (2026-08-23:
  "all apps should have a deploy on their own mechanism inside their repo"):
  the Catalyst bundle into `/Applications` BEFORE the tag and FATAL — a broken
  desktop build leaves the version untagged, so a re-run reuses it rather than
  burning a number — then Android on the emulator and the iOS build check
  AFTER the push, reported rather than fatal, because by then the release has
  already happened and an emulator that will not boot is not a failed one. iOS
  is build-checked but NEVER installed: the phone install stays the explicit
  `tools/deploy-device.sh`, because it spends one of the phone's 3
  free-team slots. The bump RESTARTS `ios.buildNumber` at 1 and INCREMENTS
  `android.versionCode` — they are different kinds of number: buildNumbers
  reset per marketing version, versionCode is one monotonic integer per
  device, ever (proven 2026-08-23: a reset shipped versionCode 1 against an
  emulator holding 4 — INSTALL_FAILED_VERSION_DOWNGRADE). A re-run of a
  failed release bumps only the build number. (The old rule "CalMind-Local
  is not tagged" was about sharing CalMind's tag namespace — in its own repo,
  its own bare `x.y.0` tags are the point.)
- **A single-repo release is still a release, so the lane reports itself.**
  The baseline's rule — a release reports to seancheren.com/status through
  CoreMind's `bin/report-status.sh`, and a status failure never fails a
  release — is wired into `tools/dtp.sh` itself, after CoreMind's `bin/dtp.sh`
  stopped being what ran here (Sean, 2026-08-23: "i dont see the tdtp from
  ChefMind on status"). It opens a run at the top and arms an EXIT/INT/TERM
  trap that closes it `failed`, so a lane that dies anywhere — a refused push,
  a Ctrl-C — cannot leave MyCalMind purple on the page for ever; it finishes
  `ok` with severity 2 when the release is live but a device build did not
  run. Every call is `|| true` and the reporter exits 0 on all of its own
  failure paths, by design. And it DEFERS when `MIND_RUN_ID` is set: CoreMind's
  orchestrator has already opened one card for the whole batch and passes the
  id down (Sean, 2026-08-23: "there should be one card per tdtp if multiple
  jobs are triggered in one batch"), so a lane run inside `dtp all` reports
  nothing of its own. Run alone, it opens and closes its own card.

## Commands

```sh
npm install            # once, at the ROOT — the workspaces are packages/* and app
npm test               # = test:core, the whole vitest suite (634 tests)
npm run typecheck      # tsc --noEmit over the app workspace, which pulls core in
npm run dtp            # the release lane: gates, bump, platform builds, tag,
                       #   push — what it ships is in Standing rules (tools/dtp.sh)
npm run tdtp           # the same lane, --full      (tools/tdtp.sh -> dtp.sh --full)
npm run deploy:device  # NOT part of dtp/tdtp: the deliberate Release build and
                       #   install onto the connected iPhone, which spends one of
                       #   its 3 free-team slots. Run it only when MyCalMind
                       #   should actually take one.
npm run start          # Metro — but read the :8081 trap below before you look at it
```

The lane takes the platform flags through to `tools/build-platforms.sh` and
uses its convention: `--mac`, `--ios`, `--android` select, naming NONE means
all three, and they compose. `--web` — what CoreMind's orchestrator passes
every self-shipping lane on a plain `dtp all` — means the release and no
platform builds, since this repo has no web to build. A POSITIONAL argument is
refused: it used to be a phone UDID, and the message points at
`sh tools/deploy-device.sh <udid>` so that a release can never spend a device
slot as a side effect.

One file, or one test by name, out of core's 48 suites — the flags go after
`--`, and `--run` is not optional, since vitest without it sits in watch mode:

```sh
npm -w @calmind/core run test -- --run parse.test
npm -w @calmind/core run test -- --run -t 'clamped steps'
```

Run them THAT way rather than `npx vitest` from inside `packages/core`:
`TZ=America/Chicago` lives in core's own `test` script, and a bare vitest is
the one way to lose it — the fixtures are timezone-sensitive, so what you get
is a handful of off-by-a-day failures that look like real breakage.

`app/AGENTS.md` is a single line and means it: Expo has changed, so read the
versioned docs at https://docs.expo.dev/versions/v57.0.0/ before writing Expo
code rather than recalling an older SDK's API.

## The shape of it

Two layers and a thin native edge, and the split is the whole design: what is
a RULE lives in `packages/core` as plain TypeScript — no React, no
`react-native`, no platform — so the vitest suite can hold all of it; what is a
SCREEN lives in `app`. A rule that grows a `Platform.OS` in it has moved to the
wrong side.

- **`packages/core`** — the brain. A record is `{ id, type, updated, deleted?,
  payload }` (`types.ts`), and folders, sections and calendars are records too,
  referenced BY ID and never by name, so a rename touches one record. Position
  in a list is a fractional string key (`order.ts`), so a drag rewrites one
  row rather than renumbering the list. `SyncEngine` (`sync.ts`) is the store
  itself: a map of records merged per-record last-write-wins on `updated`, a
  tie keeping the incumbent — which is what makes a peer's echo of our own
  record a no-op instead of a game of catch. `normalize.ts` is the repair pass
  run on every refresh. Around those sit the domain files: `parse` (the
  slash-only date parser), `repeats`/`rrule`, `day`/`layout` (the calendar
  grid), `recipe` (the largest, and the one with an importer behind it),
  `watch` (the feed the wrist reads), `ical`, `search`, `backup`, `undo`,
  `habit`.
- **`spec/*.json`** — four vector files replayed by `test/spec.test.ts`. They
  are the behaviour contract this core shares with the suite's other
  implementations, so a behaviour change starts by amending a vector; a test
  edited to match new output has silently forked the contract.
- **`app/src/store.tsx`** — the one stateful seam, and the file to read first.
  Every screen reads through `useStore()` and writes through `mutate(fn)`,
  which stamps the edit, re-renders, persists IMMEDIATELY (no debounce — the
  snapshot is the only copy) and sends just the changed records to the peers.
  Its header explains the three things this build had to do differently from
  upstream: fixed starter ids, the wait before seeding, and what happens to a
  snapshot that will not parse.
- **No router.** `App.tsx` is a five-way switch on a `tab` string with its own
  back stack; `nav.tsx` is the bottom bar, `chrome.tsx` the top bar that every
  screen mounts (and that hands every screen Settings for free). One file per
  tab in `app/src/screens`, plus Search, Settings and RecipeEditor.
- **Theming without prop-drilling.** `theme.ts` exports a MUTABLE palette `T`
  and a `themed()` sheet wrapper; `applyTheme` swaps the values in place and
  bumps a generation, `App.tsx` remounts the tree, and no component knows
  themes exist. The semantic colours (overdue, danger, the event blue) are
  literal across all four themes on purpose.
- **The native edge.** Three Expo modules in `app/modules` — `peer-sync` (the
  Bonjour transport and its TLS-by-passphrase handshake), `watch-bridge`
  (WatchConnectivity plus the widget's queued ticks), `native-ocr` (Vision, on
  device) — and three `@bacons/apple-targets` in `app/targets`: `watch`,
  `watchwidget` (the complication) and `appwidget` (the home screen). Every JS
  side loads through `requireOptionalNativeModule` and no-ops when the module
  is absent, so Android, Expo Go and web never branch on any of it. The
  modules are deliberately DUMB PIPES: `peer-sync` carries opaque JSON and the
  merge stays in core, because a second last-write-wins written in Swift is
  exactly the thing that drifts from the first and is only noticed when two
  devices disagree. The widget and complication cannot reach the store at all
  — they read the App Group container, which is why that one id appears in
  four Swift files.

## Platforms

No server, no web instance — local-only, Bonjour peer-to-peer, and the
device is the only copy of its data. As of 2026-08-23:

- **iOS — build-checked every release, never installed.** The lane compiles
  Release (watch companion included) and stops; nothing occupies a slot on
  the phone, on purpose. Apple's free developer team caps one physical device
  at 3 installed apps, and the phone's three are CalMind, ChefMind and
  AcctMind; MyCalMind was freed from it on 2026-08-22 to make room for
  ChefMind's reinstall. `tools/deploy-device.sh` (`npm run deploy:device`) is
  the deliberate install and is NOT part of `dtp`/`tdtp` — run it only when
  MyCalMind should actually take one of those slots.
- **watchOS — builds, a real companion app.** The iOS build produces a
  working watch companion, `Watch/CalMindWatch.app` inside the bundle (the
  legacy `CalMindWatch` product name is kept on purpose — same
  on-device-data reasoning as the bundle id). It installs with
  `xcrun devicectl device install app --device <watch-udid>
  …/Watch/CalMindWatch.app` (see "Running it" in `README.md`), proven
  building 2026-08-22, but nothing is installed to a paired watch right now.
- **macOS — a real Mac Catalyst app, installed at `/Applications/MyCalMind.app`.**
  Proven working 2026-08-22, after a long chase: `app/plugins/withMacCatalyst.js`
  (an Expo config plugin, committed, survives every `prebuild`) flips the
  Podfile's `mac_catalyst_enabled`, enables `SUPPORTS_MACCATALYST` on the main
  app AND the widget target (NOT the watchOS-SDK targets, which can't run
  under Catalyst — `platformFilter = ios` on the "Embed Watch Content" build
  file excludes `CalMindWatch.app` from the Catalyst product, matching
  Xcode's own suggested fix for "built for macOS but contains embedded
  content built for watchOS"). Build arm64-only —
  `ExpoModulesCore.xcframework` ships no x86_64 Catalyst slice at all
  (Info.plist has only `ios-arm64` and `ios-arm64_x86_64-simulator`), so
  x86_64 is a real, permanent gap in this Expo SDK version, not a bug here.
  Expo modules and React Native's own core must build **from source**, not
  from their prebuilt XCFrameworks — `EXPO_USE_PRECOMPILED_MODULES=0
  RCT_USE_PREBUILT_RNCORE=0` before `expo prebuild` — because those
  XCFrameworks' generated CocoaPods copy scripts have no `maccatalyst` case
  at all when the framework wasn't packaged with one.
  **The `ReactNativeDependencies` repair — automated, and no longer yours to
  redo.** That XCFramework (React Native's third-party C++ deps —
  folly/glog/boost) has NO source-build option and IS packaged with a
  maccatalyst slice, but that slice's bundle is malformed: the top-level
  binary and `Resources/` are real duplicate copies where a macOS-style
  versioned framework needs symlinks through `Versions/Current -> A`, and
  three privacy-manifest-only
  `ReactNativeDependencies_{boost,folly,glog}.bundle` sit at the bundle root,
  tripping "unsealed contents present in the root directory of an embedded
  framework". Codesign refuses it as shipped. The repair is
  `tools/patch-rndeps-catalyst.js` (idempotent — copied VERBATIM from
  CoreMind's `bin/`, where it was written, so its own "bin/" self-references
  mean that origin: CoreMind `d26b647`, 2026-08-22), and
  `tools/build-platforms.sh`'s catalyst path runs it between the prebuild and
  `xcodebuild`, aborting the build if it cannot — so a fresh
  `pod install`/`prebuild` no longer loses it. Two things about it are worth
  knowing before touching it. It patches the fix INTO the "`[CP-User] [RNDeps]
  Replace React Native Dependencies…`" script phase of the GENERATED
  `ios/Pods/Pods.xcodeproj` rather than repairing `ios/Pods` beforehand,
  because that phase is `alwaysOutOfDate` and re-extracts the pristine broken
  bundle on every single build — a fix applied before `xcodebuild` is wiped
  moments later, proven twice while chasing this. And the three resource
  bundles are DROPPED, not moved: under `Versions/A` codesign then wants them
  independently signed as subcomponents, which they neither are nor need to
  be. The costs were accepted rather than overlooked — the app's Expo modules
  and React Native core always build from source (slower), and a
  CocoaPods-generated file is shell-patched on every run.
- **Android — builds, installs, and launches.** `com.seancheren.calmindlocal`,
  confirmed on the local emulator 2026-08-23 (1.2.0, versionCode 6).
- **Web — none, deliberately.** No server means nothing to build a web
  instance against.

The platform builds run through this repo's own
`tools/build-platforms.sh [--mac] [--ios] [--android]` (since 2026-08-23;
CoreMind's `bin/build-platforms.sh` remains the table-driven fallback for a
checkout that predates it). MyCalMind rides CoreMind's `dtp all`
cascade like every app now — safely, because the lane never installs to a
phone: iOS is build-checked only, and the install stayed a deliberate,
explicit act.

## Traps that have cost real time here

- **A Debug build silently loads the OTHER app.** Metro serves on :8081, and
  the CalMind repo's dev server is often on it — a Debug build of this app then
  renders CalMind's bundle, login screen and all, and looks like the gutting
  failed. Build Release for anything you intend to look at.
  (`tools/deploy-device.sh` builds Release for this reason.)
- **CocoaPods needs a UTF-8 locale.** Without `LANG=en_US.UTF-8` prebuild dies
  in `unicode_normalize` with an ASCII-8BIT error that names nothing useful.
- **`rsync --exclude ios` also excludes `modules/*/ios`.** The generated
  `app/ios` should be skipped; the native modules' own `ios/` directories are
  SOURCE and must not be. The watch bridge went missing this way.
- **The App Group id is in Swift as well as in the configs.** Four files carry
  it — the bridge module, the widget, the complication, the watch store — and a
  missed one reads an empty container and shows a waiting state forever.
- **Never pass `-sdk iphonesimulator` to xcodebuild.** It overrides SDKROOT for
  every target in the scheme, so the watch complication compiles against the
  iOS SDK and dies on `accessoryCorner is unavailable in iOS` — which reads as
  broken watch code rather than a wrong flag. `-destination 'platform=iOS
  Simulator,id=…'` alone builds each target for its own platform.
- **`simctl` text injection stops at the first `.` in a `keyboardType="url"`
  field.** The URL keyboard's `.` is a long-press key. Type the dots as their
  own one-character injections. A real keyboard is unaffected; this only
  costs test time, and it looks exactly like the field truncating input.
- **The simulator may be shared with a CalMind session.** Its app can take the
  foreground mid-test and swallow your taps and typing. Boot a second device
  rather than fighting for the first.
- **The shell's working directory persists between Bash calls.** Use absolute
  paths; a `cd app` earlier in the session breaks the next relative command.
- **Ask what happens when a write fails.** The snapshot here is the ONLY copy —
  upstream it is a cache of what the server holds. A snapshot that will not
  parse is moved aside and reported, never treated as an empty store: empty and
  lost look identical, and the next write would go over the top of it.
