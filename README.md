# MyCalMind

CalMind with the server removed. Everything stays on your devices.

## Disclaimer

Feel free to build and deploy the iOS and watch apps on your own devices, etc. There is no website to deploy — this edition has the server taken out.

**This is a personal project to have some fun with claude code, which generated essentially all of the code, and the rest of this readme:**

## Quick start / Install

Build from source and install onto your own devices, see Building. Nothing is packaged for download.

## Platforms

- iOS
- watchOS (app, complication, home-screen widget)
- macOS (Mac Catalyst)
- Android
- No web version, by design

## Usage

Same screens as [CalMind](https://github.com/chere005/CalMind): reminders, calendar, notes with recipes, habits. No accounts, nothing to sign into. An iPhone and a Mac on the same network mirror each other over Bonjour.

## Notes

- The only internet request is fetching a recipe URL you paste.
- Android keeps its own copy; mirroring is iPhone and Mac only.
- Built for one person: a release installs onto Sean's phone, Mac and the local Android emulator.

## Building

```sh
npm install
npm test
cd app && LANG=en_US.UTF-8 npx expo prebuild --platform ios --clean
```

`LANG` is required; CocoaPods needs a UTF-8 locale. Then `xcodebuild -allowProvisioningUpdates`, or `sh tools/build-platforms.sh` for Mac, iOS and Android. Release: `npm run dtp` (or `tdtp`, tests first).

## Documentation

- [ARCHITECTURE.md](ARCHITECTURE.md): what was removed from CalMind and why, the one internet request, how each platform ships.
- [AGENTS.md](AGENTS.md): rules for anyone, human or agent, changing the code.

## Contributing

Issues and pull requests are welcome. Read AGENTS.md first; `npm test` and `npm run typecheck` must pass. BSD 3-Clause, see [LICENSE](LICENSE).
