# MyCalMind

CalMind with the server taken out. Its own repo since 2026-08-22 — extracted
from [chere005/CalMind](https://github.com/chere005/CalMind) with its history,
where it lived as `CalMind-Local`, and renamed. The rename is display-deep
only: the bundle ids, App Group, Bonjour service and every persisted key keep
their `calmindlocal` spellings, because those ARE the installed app's identity
and its data (`AGENTS.md` has the full list).

**Platforms:** iOS and watchOS (SwiftUI watch app, watch-face complication,
home-screen widget); macOS as a real Mac Catalyst app, installed at
`/Applications/MyCalMind.app`; and Android, which builds, installs and
launches on the local emulator. All of them entirely local — no server, no
accounts; devices mirror each other over Bonjour on the local network. There
is no web instance, deliberately.

It is not a rewrite and not a lookalike — it is the app from CalMind's
`apps/app` and `packages/core`, copied whole and then gutted of everything
that needed a server. Every screen, every gesture, every rule is the one
upstream ships, because it is literally the same code.

```
app/            The Expo app, cloned from CalMind's apps/app — screens,
                gestures, styling, the native watch/complication/widget
                targets.
packages/core/  The brain, cloned verbatim minus the two modules that only
                existed to talk to a server.
spec/           The behaviour contract, copied so core's suite runs here.
tools/          dtp.sh / tdtp.sh, the release lanes; build-platforms.sh, the
                Mac Catalyst / iOS / Android builds a release ships, with
                patch-rndeps-catalyst.js beside it (the Catalyst codesign
                repair it cannot build without); and deploy-device.sh, the
                deliberate iPhone install, which is NOT part of a release.
```

## What was taken out, and why

| Gone | Because |
|---|---|
| `src/api.ts`, `src/config.ts` | the HTTP edge and the URL it pointed at |
| `Login`, `signIn`/`signOut`, `src/passkey.ts` | there is no account to sign into |
| `Requests`, `Request`, `core/meetreq.ts` | the public request page is a server endpoint |
| `ShareModal`, the shared-partner reads | sharing needs two accounts and a server to arbitrate |
| `QuickTick` | the widget's `?tick=` link is a URL on a server |
| `src/subs.ts`, `core/calsub.ts` | an ICS by link is fetched through the server's proxy — a browser cannot (no CORS) and a phone should not (the SSRF guard lived there) |
| ~~the recipe URL import~~ | **back, on-device** — see below. Photo import never left; that OCR is on-device |
| `src/update.ts` | it existed to reload a web build that is served |

The **store** kept its shape and lost its server half: the engine, the merge
rules, normalization and one snapshot on disk are all still there; the session,
the cursor, the dirty set and the push/pull are gone.

The context still exposes `session`, `syncState` and `sharedRecs` because twenty
screens read them. They tell the truth about an app with no server rather than
being rewritten out of twenty call sites: the name is a constant, the state is
always idle, sharing is always empty.

Two visible consequences, both deliberate:

- The top-right control is a **menu button**, not the account pill. Upstream its
  border carries the sync state and its letter is your initial; neither means
  anything here. It still turns red when this device cannot save its own copy,
  which is the one failure this build can actually have.
- The status line reads **"Saved on this device"**. It used to say
  "Online — synced", which would be a lie about a connection that does not exist.

## The one thing that leaves the device

Sean, 2026-08-21: *"can you still add the url parsing of recipes? reading from
that url is fine, the rest of the app remains local to its data or paired
devices."* So the Recipe page's 🔗 is back, and it is the whole of this app's
contact with the internet: a GET of a link he pasted, its HTML parsed by core's
`recipeFromHtml`, nothing sent but the URL.

Upstream the **server** did the fetching, behind `server/lib/fetchurl.php`,
because a browser cannot (recipe sites send no CORS headers) and because a
request made from inside the host reaches addresses the user cannot. There is
no server here, so the phone fetches and the guards move with it:

- `core/fetchguard.ts` decides **which addresses** — http(s) only, never this
  device and never this network. Its own tests cover the spellings a guard
  written from memory misses: `0177.0.0.1`, `2130706433`, `::ffff:192.168.1.10`,
  and `https://www.seriouseats.com@192.168.1.10/`. `.local` is refused by name,
  because that is Bonjour's suffix and this app advertises on it.
- `src/recipefetch.ts` owns the request — a 15s abort, a 4MB cap, an HTML sniff,
  and a **re-check of `res.url`** after the fact, since React Native follows
  redirects itself and offers no hook per hop. A response from a private address
  is dropped unread.

What it does not do is resolve the name, because JS cannot: a public hostname
pointing at `192.168.1.10` gets through. On a device that trade differs from the
server's — the reach is the network Sean is already on, not a host holding
everyone's data.

Some sites answer **402/403 to anything that is not a browser** (allrecipes and
seriouseats both refuse a datacentre address). The message says so rather than
quoting the number at him.

## Identity

Its own bundle ids (`com.seancheren.calmindlocal…`), its own App Group
(`group.com.seancheren.calmindlocal`), its own storage key — so it sits beside
the real CalMind on the same phone and wrist and shares nothing with it. The
watch app and the widgets say **MyCalMind**, because two identical icons is
a trap. The icon is CalMind's own.

## Running it

```sh
npm install
npm run test:core                          # 634 tests
npm run typecheck
cd app && LANG=en_US.UTF-8 npx expo prebuild --platform ios --clean
```

`LANG` is not optional — CocoaPods dies with a Unicode normalization error
without a UTF-8 locale.

Build and install with `xcodebuild -allowProvisioningUpdates` against the
device; `expo run:ios` cannot mint provisioning, and these bundle ids are new.
The watch app installs **directly**:

```bash
xcrun devicectl device install app --device <watch-udid> <MyCalMind.app>/Watch/CalMindWatch.app
```

**A Debug build is not self-contained.** It loads its bundle from Metro on
:8081 — and if the CalMind repo's Metro is running there, your Debug build
silently gets *that* app, login screen and all. Build Release to look at this
one.

For the Mac and Android builds by hand, use the same script the release lane
does — `sh tools/build-platforms.sh --mac` (Catalyst into `/Applications`),
`--android` (emulator), `--ios` (build check only) — naming none of them means
all three — and `--dry-run` to see the plan before anything runs.

## Releasing it

```sh
npm run dtp      # gates, bump, the Mac Catalyst app into /Applications, tag,
                 # push, then Android on the emulator and the iOS build check
npm run tdtp     # the same lane with the full test run in front
```

The Catalyst build comes BEFORE the tag and is fatal — a broken desktop build
leaves the version untagged, so a re-run reuses it. Android and the iOS build
check come after the push and are reported rather than fatal; the release has
already happened by then.

**A release never touches the phone.** iOS is build-checked only: Apple's free
developer team caps one physical device at 3 installed apps, and MyCalMind is
deliberately not one of the three. `tools/deploy-device.sh`
(`npm run deploy:device`) is the explicit install for the day it should take a
slot — it refuses to guess when no single connected iPhone is found.

Either lane bumps the minor version, but the two build numbers are different
kinds of number. `ios.buildNumber` RESTARTS at 1, because a build number is
per marketing version. `android.versionCode` only ever INCREMENTS: it is one
monotonic integer per device, for ever. Paid for on 2026-08-23, when a reset
shipped versionCode 1 to an emulator already holding 4 and the install came
back `INSTALL_FAILED_VERSION_DOWNGRADE`.
