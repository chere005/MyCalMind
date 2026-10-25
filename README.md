# MyCalMind

Feel free to build and deploy the iOS and watch apps on your own devices, etc. There is no website to deploy — this edition has the server taken out.

**This is a personal project to have some fun with claude code, which generated essentially all of the code, and the rest of this readme:**

[CalMind](https://github.com/chere005/CalMind) with the server taken out:
reminders, calendar, notes (recipes included) and habits, kept entirely on
your own devices. There are no accounts and nothing to sign into. An iPhone
and a Mac mirror each other over Bonjour on the local network rather than
through anyone's host, and the only request the app ever makes to the
internet is fetching a recipe URL you paste. It is a clone of CalMind's app
and core, gutted of everything that needed a server, so every screen and every
rule is the one upstream ships.

It runs on iOS, on watchOS (watch app, complication and home-screen widget),
on macOS as a Mac Catalyst app, and on Android, which keeps its own copy
without mirroring. There is no web version, deliberately. It is built for one
person: a release installs it onto Sean's phone, his Mac and the local Android
emulator, and nothing is packaged for anyone else.

## Running it

```sh
npm install
npm test                                   # the core suite
npm run typecheck
cd app && LANG=en_US.UTF-8 npx expo prebuild --platform ios --clean
```

`LANG` is not optional; CocoaPods dies without a UTF-8 locale. Then build with
`xcodebuild -allowProvisioningUpdates`, or let `sh tools/build-platforms.sh`
make the Mac, iOS and Android builds the way a release does. Releasing is
`npm run dtp` (deploy, tag, push) or `npm run tdtp` (the same, tests first).

## More

[ARCHITECTURE.md](ARCHITECTURE.md) is the long version: what was taken out of
CalMind and why, the one internet request and the guards around it, the
identity it must keep, how each platform ships, and what the release lanes do.
[AGENTS.md](AGENTS.md) is the rule book for changing the code, traps included.
BSD 3-Clause; see [LICENSE](LICENSE).
