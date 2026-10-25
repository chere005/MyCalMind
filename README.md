# MyCalMind

Feel free to build and deploy the iOS and watch apps on your own devices, etc. There is no website to deploy — this edition has the server taken out.

**This is a personal project to have some fun with claude code, which generated essentially all of the code, and the rest of this readme:**

[CalMind](https://github.com/chere005/CalMind) with the server removed. Everything stays on your devices.

- No accounts. iPhone and Mac mirror over Bonjour on the local network.
- Runs on iOS, watchOS, macOS (Catalyst) and Android. No web version.
- The only internet request is fetching a recipe URL you paste.
- Built for one person. Nothing is packaged for anyone else.

## Run

```sh
npm install
npm test
cd app && LANG=en_US.UTF-8 npx expo prebuild --platform ios --clean
```

Then `xcodebuild`, or `sh tools/build-platforms.sh` for Mac, iOS and Android. Release: `npm run dtp` (or `tdtp`, tests first).

Docs: [ARCHITECTURE](ARCHITECTURE.md) · [AGENTS](AGENTS.md). BSD 3-Clause.
