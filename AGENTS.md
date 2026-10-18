# Working in MyCalMind

The baseline for all of Sean's repos lives in ~/GIT/AgentSuite/AGENTS.md
and is imported here; this file holds only what is true of THIS repo.
@../AgentSuite/AGENTS.md

CalMind minus the server: a CLONE of CalMind's `apps/app` + `packages/core` (upstream `~/GIT/CalMind`). Map: `ARCHITECTURE.md`.

## Rules

- **Keep it a clone.** Product fixes go upstream in CalMind first, then are copied down deliberately; never diverge by hand.
- **Drift gate:** `tools/dtp.sh` runs CoreMind `bin/check-drift.sh MyCalMind` first; failure stops the whole lane and the lane never rewrites source to pass. Fix = `sh ../CoreMind/bin/deploy-core.sh --only MyCalMind`, run and committed first. No CoreMind checkout beside this repo = WARNING, not refusal.
- **Rename is display-deep only.** Never rename: `com.seancheren.calmindlocal` (bundle ids), `group.com.seancheren.calmindlocal` (App Group, 4 Swift files), `_calmind-local._tcp` (Bonjour), persisted keys (`calmind.local.snapshot`, `calmind.local.peer.*`, `calmind.folded.*`, …) → orphans on-device data (the only copy) or breaks pairing.
- **Nothing references the server:** no URL, token or `serverUrl`; remove such a feature rather than stub it.
- **One `fetch` only:** the recipe importer, via `src/recipefetch.ts` + `core/fetchguard.ts` (refuses this device/network, `.local` included). A second `fetch` caller is a bug.
- **Gates:** `npm test` (core vitest, `TZ=America/Chicago`) and `npm run typecheck`; the lane runs both every run and a failure stops it. No lint script exists; don't invent one.
- **`npm run dtp` / `tdtp`** (`tools/dtp.sh`, `tools/tdtp.sh`) ship this repo's own `tools/build-platforms.sh` builds: Catalyst into `/Applications` BEFORE the tag, FATAL (re-run reuses the version); Android emulator + iOS build/install AFTER the push, reported not fatal.
- **Bump:** `ios.buildNumber` RESTARTS at 1 per marketing version; `android.versionCode` only INCREMENTS (a reset → INSTALL_FAILED_VERSION_DOWNGRADE). A re-run of a failed release bumps only the build number. Tags are bare `x.y.0`.
- **Lane reports status** itself (`tools/dtp.sh` → CoreMind `bin/report-status.sh`): opens a run, EXIT/INT/TERM trap closes it `failed`, `ok` severity 2 if live but a device build didn't run; every call `|| true`. DEFERS (reports nothing) when `MIND_RUN_ID` is set by `dtp all`.
- **Lane exits non-zero when a device build is owed** (release still shipped); CoreMind's batch continues with later repos.
- **Core vs screens:** rules are plain TS in `packages/core` (no React, no `react-native`, no `Platform.OS`); screens live in `app`.
- **`spec/*.json` vectors** (replayed by `test/spec.test.ts`) are the shared behaviour contract: change behaviour by amending a vector, never by editing a test to match new output.
- **Persist immediately:** `app/src/store.tsx` `mutate(fn)` writes with no debounce (snapshot = only copy). A snapshot that won't parse is moved aside and reported, never treated as empty.
- **Native modules are dumb pipes** (`peer-sync` carries opaque JSON; merge stays in core). JS loads them via `requireOptionalNativeModule` and no-ops when absent. Widget/complication read only the App Group container.
- **Expo:** read https://docs.expo.dev/versions/v57.0.0/ before writing Expo code (`app/AGENTS.md`).
- **`tools/heavy-lock.sh`** (CoreMind canon, exact row, never edited here) wraps each `build-platforms.sh` block and `deploy-device.sh` (waits, prints holder every 30 s, gives up after 30 min, `MIND_HEAVY_WAIT`). It sees only scripts sourcing it; WriteMind (`tools/build.sh`, `tools/test.sh`) and WriteMindCross builds take no lock, so serialize those by hand.

## Commands

```sh
npm install            # once, at the ROOT — the workspaces are packages/* and app
npm test               # = test:core, the whole vitest suite
npm run typecheck      # tsc --noEmit over the app workspace, which pulls core in
npm run dtp            # the release lane: gates, bump, platform builds, tag, push
npm run tdtp           # the same lane, --full      (tools/tdtp.sh -> dtp.sh --full)
npm run deploy:device  # NOT part of dtp/tdtp: one-off Release build + install onto the connected iPhone
npm run start          # Metro — but read the :8081 trap below before you look at it
```

- Lane platform flags (→ `tools/build-platforms.sh`): `--mac`, `--ios`, `--android` compose; none = all three; `--web` (passed by `dtp all`) = release, no platform builds. A POSITIONAL arg is refused; use `sh tools/deploy-device.sh <udid>`.
- One test file or name (`--run` is mandatory, else vitest watches); use this form, not bare `npx vitest`, which loses `TZ=America/Chicago` → off-by-a-day failures:

```sh
npm -w @calmind/core run test -- --run parse.test
npm -w @calmind/core run test -- --run -t 'clamped steps'
```

## Platforms

Local-only, Bonjour peer-to-peer; no server, no web instance (none, deliberately).

- **iOS:** built AND installed onto Sean's phone every release (paid team; no per-phone cap). `tools/deploy-device.sh` is the install without a release.
- **watchOS:** iOS build yields `Watch/CalMindWatch.app` (legacy name kept on purpose, like the bundle id). Install: `xcrun devicectl device install app --device <watch-udid> …/Watch/CalMindWatch.app` (ARCHITECTURE.md "Running it"); nothing installed now.
- **macOS:** Mac Catalyst app at `/Applications/MyCalMind.app`, via committed config plugin `app/plugins/withMacCatalyst.js` (survives `prebuild`; enables `SUPPORTS_MACCATALYST` on app + widget, NOT watchOS targets; `platformFilter = ios` on "Embed Watch Content").
  - arm64 only: `ExpoModulesCore.xcframework` has no x86_64 Catalyst slice.
  - Build Expo modules and RN core from source: `EXPO_USE_PRECOMPILED_MODULES=0 RCT_USE_PREBUILT_RNCORE=0` before `expo prebuild` (prebuilt XCFramework copy scripts lack a `maccatalyst` case).
  - `ReactNativeDependencies` maccatalyst slice is malformed (copies not symlinks; stray `ReactNativeDependencies_{boost,folly,glog}.bundle` → codesign fails). `tools/patch-rndeps-catalyst.js` (idempotent, verbatim from CoreMind `bin/`) fixes it; the catalyst path runs it between prebuild and `xcodebuild` and aborts if it fails.
  - It patches the `[CP-User] [RNDeps] Replace React Native Dependencies…` phase in generated `ios/Pods/Pods.xcodeproj` (alwaysOutOfDate, re-extracts the broken bundle every build), so repairing `ios/Pods` beforehand is wiped. The 3 bundles are DROPPED, not moved.
  - Clang compile cache for Catalyst only: `~/Library/Developer/Xcode/MindCAS/MyCalMind` (4G cap, outside `app/ios`, safe to delete → one cold build). The iOS build is NOT cached (no object-by-object proof); Swift is never cached (Traps).
- **Android:** `com.seancheren.calmindlocal`; builds, installs, launches on the emulator.

`tools/build-platforms.sh [--mac] [--ios] [--android]` is the build; CoreMind `bin/build-platforms.sh` is the table-driven fallback. MyCalMind rides CoreMind's `dtp all` cascade, which also installs to Sean's phone.

## Traps

- **Debug build renders CalMind's bundle (login screen) →** Metro :8081 is often CalMind's dev server; build Release to look at anything (`tools/deploy-device.sh` does).
- **Prebuild dies in `unicode_normalize` (ASCII-8BIT) →** CocoaPods needs `LANG=en_US.UTF-8`.
- **Watch bridge missing →** `rsync --exclude ios` also drops `modules/*/ios` (SOURCE); exclude only generated `app/ios`.
- **Widget/watch shows waiting state forever →** a Swift file missed the App Group id (bridge module, widget, complication, watch store).
- **`accessoryCorner is unavailable in iOS` →** never pass `-sdk iphonesimulator` to xcodebuild (overrides SDKROOT for all targets); use `-destination 'platform=iOS Simulator,id=…'` alone.
- **simctl text injection truncates a `keyboardType="url"` field at the first `.` →** type dots as their own one-character injections.
- **Taps/typing swallowed mid-test →** simulator shared with a CalMind session; boot a second device.
- **Swift compile cache misses macro-plugin changes** (`ExpoModulesMacros-tool` via `-load-plugin-executable` isn't in the key) → lane sets `SWIFT_ENABLE_COMPILE_CACHE=NO`; re-prove before enabling.
