# MyCalMind

Feel free to build and deploy the iOS and watch apps on your own devices, etc. There is no website to deploy — this edition has the server taken out.

**This is a personal project to have some fun with claude code, which generated essentially all of the code, and the rest of this readme:**

CalMind with the server taken out: reminders, calendar, notes, habits and
recipes, kept entirely on your own devices. There are no accounts and nothing
to sign into, and your devices mirror each other over Bonjour on the local
network rather than through anyone's host. It is a clone of
[CalMind](https://github.com/chere005/CalMind)'s app and core, gutted of
everything that needed a server, so every screen and every rule is the one
upstream ships.

It is built for one person — Sean — and a release installs it onto his own
phone, his Mac and the local Android emulator; there is nothing packaged here
for anyone else.

**Runs on** iOS and watchOS (watch app, complication, home-screen widget),
macOS as a Mac Catalyst app, and Android. There is no web version, deliberately.

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

[`ARCHITECTURE.md`](ARCHITECTURE.md) is the long version: what was taken out of
CalMind and why, the one request this app makes to the internet and the guards
around it, the identity it must keep, how each platform ships, and what the
release lanes do. [`AGENTS.md`](AGENTS.md) is the rule book for changing the
code, traps included.

BSD 3-Clause licensed — see [`LICENSE`](LICENSE).
