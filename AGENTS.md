# Working in MyCalMind

CalMind with the server taken out — a CLONE of CalMind's `apps/app` and
`packages/core`, not a rewrite. `README.md` is the map.

Until 2026-08-22 this lived inside the CalMind repo as `CalMind-Local`; it was
extracted — history preserved — into its own repo and renamed MyCalMind. The
upstream it clones is `~/GIT/CalMind` (github.com/chere005/CalMind).

## Standing rules

- **It is a clone, so keep it one.** A fix that belongs to the product belongs
  upstream in CalMind first and gets copied down — across repos now, which
  makes the copying a deliberate act rather than a shared working tree.
  Diverging by hand is how the two stop being the same app, which is the
  entire value of this being a copy.
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
- **`dtp` = deploy, tag, push; `tdtp` = test, deploy, tag, push.** Sean,
  2026-08-22 — two lanes, the `t` in front being the full test run, not the
  tag. `npm run dtp` / `npm run tdtp` (tools/dtp.sh, tools/tdtp.sh). There is
  no server and no web instance, so "deploy" is `tools/deploy-device.sh`: a
  Release build installed on the connected iPhone (the watch app installs
  separately; the script prints the command). Either lane bumps the MINOR
  version — x.y.0 → x.(y+1).0, as everywhere in the suite — in
  `package.json` + `app/app.json`, and RESTARTS `ios.buildNumber`/
  `android.versionCode` at 1: a dtp puts a build on the phone, and the build
  number is how two installs are told apart (AcctMind's lesson). A failed
  deploy stops the lane; a re-run reuses the still-untagged version and bumps
  only the build number. (The old rule "CalMind-Local is not tagged" was
  about sharing CalMind's tag namespace — in its own repo, its own bare `x.y.0`
  tags are the point.)
- **`main` is the branch.** Stage explicit paths — never `git add -A`.

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
