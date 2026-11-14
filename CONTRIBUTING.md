# Contributing to Glimpse

Thanks for helping. Glimpse is a small, native, MIT-licensed macOS menu-bar monitor. This guide covers how to propose changes, and how to do every step of building, testing, CI and releasing by hand.

Start with [docs/architecture.md](docs/architecture.md) for how the code is organized, and [docs/design.md](docs/design.md) for why.

## Proposing a change

1. **Open an issue first** for new behaviour, describing the user need. Small fixes can go straight to a pull request.
2. **Branch from `main`**, keep the change focused, and match the existing style.
3. **Monitoring changes need evidence**: accuracy (how you compared readings) or overhead (see [docs/performance.md](docs/performance.md)).
4. **Keep the docs true**: update [docs/architecture.md](docs/architecture.md) when modules, data flow, threading, persistence, editions, scripts or the release pipeline change, and the user-facing docs when behaviour changes.
5. **Open a pull request.** CI must pass. Describe what you verified and what you couldn't (hardware, macOS 12, Intel, sleep/wake).

Ground rules:

- macOS 12 stays the deployment target; don't raise it for a convenience API.
- Native counters only: no shell commands or subprocess polling. Missing data is shown as unavailable, never zero.
- Independent implementation: don't copy code from GPL projects (such as iGlance) or Apple sample code with incompatible terms. SF Symbols may be used in the UI but never in the app icon or logos.
- Never commit secrets, certificates, signing keys, personal diagnostics, or paths and hostnames from your own machine.

## Requirements

- macOS with Xcode 27.2 (or its command-line tools) selected: `sudo xcode-select -s /Applications/Xcode.app`.
- Nothing else: SwiftPM fetches the pinned Sparkle framework. `make-dmg.sh` creates its own Python virtualenv for `dmgbuild`.

## Doing everything by hand

### Build and run

```bash
swift test                                      # all unit, reader and rendering tests
./scripts/build-app.sh                          # build/Glimpse.app for this Mac, ad-hoc signed
open build/Glimpse.app                          # runs in the menu bar (no Dock icon)
open build/Glimpse.app --args --settings        # open straight into Settings
ARCH=universal ./scripts/build-app.sh           # arm64 + x86_64
build/Glimpse.app/Contents/MacOS/Glimpse --diagnose           # print live native readings, no UI
build/Glimpse.app/Contents/MacOS/Glimpse --render-cards <dir> # PNGs of every panel size, light and dark
```

To quit, click **Quit** in the dropdown panel (⌘Q while it is open). Settings are stored in the `com.tastyjam.glimpse` defaults domain; `defaults delete com.tastyjam.glimpse` resets them.

### Mac App Store edition

```bash
APP_STORE=1 ./scripts/build-app.sh              # sandboxed, no Sparkle → build/AppStore/Glimpse.app
build/AppStore/Glimpse.app/Contents/MacOS/Glimpse --diagnose  # readers inside the sandbox
scripts/make-pkg.sh --version 0.3.0             # + installer package; unsigned without store certificates
```

Its settings live in the sandbox container (`~/Library/Containers/com.tastyjam.glimpse`).

### Run the CI checks

Locally, the same steps CI runs:

```bash
swift test
ARCH=universal ./scripts/build-app.sh && build/Glimpse.app/Contents/MacOS/Glimpse --diagnose
APP_STORE=1 ARCH=universal ./scripts/build-app.sh && build/AppStore/Glimpse.app/Contents/MacOS/Glimpse --diagnose
GLIMPSE_RENDER_ARTIFACTS="$TMPDIR/cards" swift test --filter MetricCardRenderingTests
gitleaks detect --source . --log-opts=--all    # optional: brew install gitleaks
```

On GitHub, CI runs on every push to `main` and every pull request. To run it on demand or watch it:

```bash
gh workflow run ci.yml --ref <branch>           # or Actions → CI → Run workflow
gh run list --workflow ci.yml --limit 5
gh run watch                                    # follow the latest run
gh run view <run-id> --log-failed               # logs of failed steps
gh run download <run-id>                        # card renders uploaded by CI
```

Dependabot opens weekly pull requests for Sparkle and the pinned GitHub Actions.

### Release (maintainer only)

Releases run on the maintainer's Mac only; GitHub holds no release secrets. Normally one command does everything; see [docs/releasing.md](docs/releasing.md):

```bash
scripts/release.sh --env <private env file> --version X.Y.Z --rc N   # pre-release
scripts/release.sh --env <private env file> --version X.Y.Z          # final release
```

The private env file defines `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_PRIVATE_KEY_PATH` (an App Store Connect API key, used for notarization and uploads) and `PROVISIONING_PROFILE` (the Mac App Store profile). The login keychain holds the Developer ID Application, Apple Distribution and Mac Installer Distribution certificates and the Sparkle update key (account `com.tastyjam.glimpse`).

If the script fails partway, every step can be done by hand from a clean `main` that matches `origin/main`:

```bash
set -a; . <private env file>; set +a
V=X.Y.Z                                          # version; tag vX.Y.Z (or vX.Y.Z-rc.N)

# 1. Test
swift test

# 2. Notarized DMG (build, Developer ID signing, notarytool, stapler, spctl)
VERSION=$V scripts/make-dmg.sh
xcrun stapler validate build/Glimpse-$V.dmg      # must succeed before publishing
#    notarization alone, if needed:
#    xcrun notarytool submit build/Glimpse-$V.dmg --key "$ASC_PRIVATE_KEY_PATH" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID" --wait
#    xcrun notarytool log <submission-id> --key "$ASC_PRIVATE_KEY_PATH" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID"
#    xcrun stapler staple build/Glimpse-$V.dmg

# 3. Tag and GitHub release (add --prerelease instead of --latest for an rc)
git tag -a v$V -m "Glimpse $V" && git push origin v$V
gh release create v$V --verify-tag --latest --generate-notes --title "Glimpse $V" \
  build/Glimpse-$V.dmg build/Glimpse-$V.dmg.sha256

# 4. App Store upload (also tags vX.Y.Z-build<N>); then TestFlight and submit in App Store Connect
scripts/make-pkg.sh --version $V --upload

# 5. Sparkle appcast (final releases only)
mkdir -p /tmp/glimpse-feed && cp appcast.xml build/Glimpse-$V.dmg /tmp/glimpse-feed/
.build/artifacts/sparkle/Sparkle/bin/generate_appcast --account com.tastyjam.glimpse \
  --download-url-prefix "https://github.com/nairdaleo/Glimpse/releases/download/v$V/" \
  --link "https://tastyjam.ca/glimpse/" /tmp/glimpse-feed
cp /tmp/glimpse-feed/appcast.xml appcast.xml
git commit -m "release: appcast for Glimpse $V" appcast.xml && git push origin main

# 6. Homebrew cask (final releases only)
git clone https://github.com/nairdaleo/homebrew-tastyjam.git /tmp/tap
sed -e "s/{{VERSION}}/$V/" -e "s/{{SHA256}}/$(cut -d' ' -f1 build/Glimpse-$V.dmg.sha256)/" \
  packaging/homebrew/glimpse.rb.template > /tmp/tap/Casks/glimpse.rb
git -C /tmp/tap add Casks/glimpse.rb && git -C /tmp/tap commit -m "glimpse $V" && git -C /tmp/tap push
brew audit --cask --online nairdaleo/tastyjam/glimpse
```

Check a release from a user's point of view: download the DMG on another Mac (Apple silicon and Intel) and open it; `brew install --cask nairdaleo/tastyjam/glimpse`; and in an older installed version, **Check for Updates** offers the new one.

To pull a bad release: `gh release delete vX.Y.Z --cleanup-tag`, revert the appcast commit, and revert the cask commit in the tap. Never re-use a version number for different bytes.
