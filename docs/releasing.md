# Releasing

Releases are published from the owner's Mac with `scripts/release.sh`. Signing, notarization, the Sparkle update key and App Store Connect credentials stay local; GitHub stores no release secrets, and CI only tests and builds.

```bash
scripts/release.sh --env <private env file> --version 0.3.0 --rc 1   # pre-release
scripts/release.sh --env <private env file> --version 0.3.0          # final release
```

| Step | Pre-release (`--rc N`) | Final release |
| --- | --- | --- |
| Checks before anything is published | on `main`, clean, equal to `origin/main`, tag unused, Developer ID identity present, `ASC_*` set | same, plus the Homebrew tap exists |
| `swift test` | ✓ | ✓ |
| Universal DMG signed with Developer ID, notarized, stapled (`scripts/make-dmg.sh`); stops if it is not notarized | ✓ | ✓ |
| Annotated tag, GitHub release with DMG + `.sha256`, generated notes | `vX.Y.Z-rc.N`, pre-release | `vX.Y.Z`, latest |
| App Store package uploaded (`scripts/make-pkg.sh --upload`, see below); a failure is reported and the release continues; `--no-app-store` skips it | — | ✓ |
| `appcast.xml` regenerated with Sparkle's `generate_appcast` using the key in the login keychain (account `com.tastyjam.glimpse`), committed and pushed to `main` | — | ✓ |
| Cask `Casks/glimpse.rb` in the tap `nairdaleo/homebrew-tastyjam` rendered from `packaging/homebrew/glimpse.rb.template` and pushed with your own git credentials | — | ✓ |

The env file provides `ASC_KEY_ID`, `ASC_ISSUER_ID` and `ASC_PRIVATE_KEY_PATH` (notarization and upload) and `PROVISIONING_PROFILE` (App Store). The build number is the commit count, so it always increases, and every uploaded build is tagged at the commit it was built from. Users install with `brew install --cask nairdaleo/tastyjam/glimpse`.

One-time setup (owner): the Developer ID Application certificate in the login keychain (#12), and the public tap repository `nairdaleo/homebrew-tastyjam` (#15).

## Mac App Store

The store edition is a separate build of the same sources: sandboxed (`Configuration/AppStore.entitlements`), compiled with `GLIMPSE_APP_STORE=1` so Sparkle is neither linked nor embedded, and without the update feed. Updates come from the store.

| Step | How | Result |
| --- | --- | --- |
| Local check | `scripts/make-pkg.sh` | `build/AppStore/Glimpse.app` and `build/Glimpse-<version>-AppStore.pkg`. Without distribution certificates the app is ad-hoc signed, which is enough to run it in the sandbox. |
| Upload | Part of `scripts/release.sh`; alone: `git checkout v0.3.0 && scripts/make-pkg.sh --env <your env file> --version 0.3.0 --upload` | Signs with the distribution certificates and provisioning profile from the login keychain, uploads the package to App Store Connect and pushes the tag `v<version>-build<N>`. |
| Release | App Store Connect | Test through TestFlight, attach the build to a version and submit for review by hand. |

The upload runs **locally only**, like the rest of the release. The script reads `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_PRIVATE_KEY_PATH` and `PROVISIONING_PROFILE` (path to the profile) from the environment or from the private env file given with `--env`, and refuses to upload from a tree with uncommitted changes. The older `KEYS_ENV=`, `VERSION=` and `UPLOAD=1` variables still work; a flag wins over its variable.

One-time setup (owner):

1. developer.apple.com → Identifiers: register the App ID `com.tastyjam.glimpse` (macOS).
2. Certificates: create **Apple Distribution** (or *Mac App Distribution*) and **Mac Installer Distribution** and install both in the login keychain.
3. Profiles: create a **Mac App Store Connect** provisioning profile for that App ID and certificate; download it and point `PROVISIONING_PROFILE` at it.
4. App Store Connect → Apps → + → New App (macOS, bundle ID `com.tastyjam.glimpse`).

The store edition includes optional tips: three consumable in-app purchases, `com.tastyjam.glimpse.tip.small`, `.medium` and `.large`, created in App Store Connect and submitted together with the first version. It also asks for a review at most once per version, after two weeks of use, when Settings is opened. Both are in `Sources/GlimpseApp/TipJar.swift`. Tips are tested through TestFlight, where purchases are free.

## CI

`ci.yml` runs on every push and pull request: `swift test`, the universal app build, the sandboxed App Store edition build and the native-reader diagnostic in both on Apple silicon (`macos-15`) and Intel (`macos-15-intel`) runners, card renders uploaded as artifacts for visual review, and a full-history gitleaks secret scan. GitHub secret scanning with push protection, Dependabot alerts and security updates are enabled for the repository; `dependabot.yml` checks SwiftPM (Sparkle) and the pinned GitHub Actions weekly. Third-party actions are pinned to commit SHAs with the version in a comment, so Dependabot updates them explicitly. Hardware-specific behaviour (battery, Wi-Fi changes, sleep/wake, start at login) still needs a real Mac.
