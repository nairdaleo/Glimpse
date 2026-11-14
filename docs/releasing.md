# Releasing

Releases are built in GitHub Actions from tags. Nothing unsigned is ever published: the workflows stop with an error until the secrets below exist.

| Step | How | Result |
| --- | --- | --- |
| Release candidate | `git tag v0.3.0-rc.1 && git push origin v0.3.0-rc.1` | `release-candidate.yml` runs the tests, builds the universal DMG, signs it with Developer ID, notarizes and staples it, and attaches `Glimpse-0.3.0-rc.1.dmg` + `.sha256` to a **pre-release**. |
| Test it | Download the pre-release DMG on Apple silicon and Intel Macs | Gatekeeper should open it without warnings. |
| Promote | Actions → **Promote release candidate** → Run workflow with `rc_tag` | `promote-release.yml` re-attaches the identical notarized DMG as `Glimpse-0.3.0.dmg` under release `v0.3.0` at the rc's commit, marks it latest, and commits an updated `appcast.xml` to `main` so Sparkle offers the update. |

`VERSION` comes from the tag (`v0.3.0-rc.1` → `0.3.0`); the build number is the commit count, so it always increases. Every uploaded build is tagged at the commit it was built from by construction. Promotion also bumps the Homebrew cask in `nairdaleo/homebrew-tap` from `packaging/homebrew/glimpse.rb.template` when `HOMEBREW_TAP_TOKEN` is set (users then `brew install --cask nairdaleo/tap/glimpse`).

## One-time setup (owner)

Add these as repository secrets (Settings → Secrets and variables → Actions → New repository secret). They never leave GitHub's encrypted store; the workflows delete the temporary keychain and key file after each run.

| Secret | What to put in it |
| --- | --- |
| `DEVELOPER_ID_P12_BASE64` | Keychain Access → My Certificates → right-click **Developer ID Application: …** → Export… as `.p12` with a password, then `base64 -i DeveloperID.p12 \| pbcopy` and paste. Delete the `.p12` file afterwards. Requires the certificate from #12. |
| `DEVELOPER_ID_P12_PASSWORD` | The password chosen for that export. |
| `ASC_KEY_ID` | App Store Connect API key ID used for notarization (the Admin key). |
| `ASC_ISSUER_ID` | The App Store Connect issuer ID. |
| `ASC_PRIVATE_KEY` | Contents of the key's `AuthKey_<ID>.p8` file (`pbcopy < AuthKey_<ID>.p8`). |
| `HOMEBREW_TAP_TOKEN` | Optional, for the cask bump. Create the public repo `nairdaleo/homebrew-tap` (empty, default branch `main`), then a fine-grained personal access token limited to that repository with **Contents: Read and write**. |
| `SPARKLE_ED_PRIVATE_KEY` | Promotion only. `.build/artifacts/sparkle/Sparkle/bin/generate_keys --account com.tastyjam.glimpse -x sparkle.key`, paste the file's contents, then delete the file. Its public half is already in `Configuration/Updates.plist`. |

Locally, `scripts/make-dmg.sh` does the same build with the login keychain and the `ASC_*` variables from your own environment; see [updates.md](updates.md).

## Mac App Store

The store edition is a separate build of the same sources: sandboxed (`Configuration/AppStore.entitlements`), compiled with `GLIMPSE_APP_STORE=1` so Sparkle is neither linked nor embedded, and without the update feed. Updates come from the store.

| Step | How | Result |
| --- | --- | --- |
| Local check | `scripts/make-pkg.sh` | `build/AppStore/Glimpse.app` and `build/Glimpse-<version>-AppStore.pkg`. Without distribution certificates the app is ad-hoc signed, which is enough to run it in the sandbox. |
| Upload | `git checkout v0.3.0 && KEYS_ENV=<your env file> VERSION=0.3.0 UPLOAD=1 scripts/make-pkg.sh` | Signs with the distribution certificates and provisioning profile from the login keychain, uploads the package to App Store Connect and pushes the tag `v<version>-build<N>`. Run it right after promoting the GitHub release. |
| Release | App Store Connect | Test through TestFlight, attach the build to a version and submit for review by hand. |

The upload runs **locally only**. App Store Connect credentials for the store edition are not stored in GitHub, and there is no upload workflow. The script reads `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_PRIVATE_KEY_PATH` and `PROVISIONING_PROFILE` (path to the profile) from the environment, or from a private env file whose path is given in `KEYS_ENV`, and refuses to upload from a tree with uncommitted changes.

One-time setup (owner):

1. developer.apple.com → Identifiers: register the App ID `com.tastyjam.glimpse` (macOS).
2. Certificates: create **Apple Distribution** (or *Mac App Distribution*) and **Mac Installer Distribution** and install both in the login keychain.
3. Profiles: create a **Mac App Store Connect** provisioning profile for that App ID and certificate; download it and point `PROVISIONING_PROFILE` at it.
4. App Store Connect → Apps → + → New App (macOS, bundle ID `com.tastyjam.glimpse`).

The first upload also needs an app icon (#16); App Store Connect rejects packages without one. Remaining store work (tips, review prompts, hiding **Remove Glimpse…**, which cannot trash a sandboxed app) is tracked in #7.

## CI

`ci.yml` runs on every push and pull request: `swift test`, the universal app build, the sandboxed App Store edition build and the native-reader diagnostic in both on Apple silicon (`macos-15`) and Intel (`macos-15-intel`) runners, card renders uploaded as artifacts for visual review, and a full-history gitleaks secret scan. GitHub secret scanning with push protection, Dependabot alerts and security updates are enabled for the repository; `dependabot.yml` checks SwiftPM (Sparkle) and the pinned GitHub Actions weekly. Third-party actions are pinned to commit SHAs with the version in a comment, so Dependabot updates them explicitly. Hardware-specific behaviour (battery, Wi-Fi changes, sleep/wake, start at login) still needs a real Mac.
