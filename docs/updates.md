# Updates and start at login

Glimpse uses Sparkle 2 for update checking, signed downloads, installation and relaunch. Automatic checks and automatic downloading/installing are separate opt-in settings. Sparkle persists these preferences and owns its update schedule; Glimpse does not poll a release endpoint itself. **Check for Updates** uses Sparkle's standard interface. System-profile submission is disabled.

A development build without release configuration shows that updates are unavailable and disables update controls. No feed URL or signing key is invented. The updater starts only when the app's Info.plist contains an HTTPS `SUFeedURL` with a host and a `SUPublicEDKey` that decodes to 32 bytes, and Sparkle accepts its configuration. This metadata check does not prove that a feed is reachable or that a release is published.

## Packaging a DMG

```bash
VERSION=0.3.0 scripts/make-dmg.sh   # → build/Glimpse-0.3.0.dmg and .sha256
```

The script builds a universal app (`BUILD_NUMBER` defaults to the commit count, so it always increases), renders the gradient drag-to-Applications background (`scripts/dmg/background.swift`) and lays out the window with a pinned `dmgbuild` in `.build/dmg-venv`, which writes Finder metadata directly and works headless on CI. Signing uses `CODESIGN_IDENTITY`, else the first *Developer ID Application* identity in the keychain, else ad-hoc with a warning — ad-hoc DMGs are for local testing only; Gatekeeper blocks them when downloaded. With a Developer ID identity the app is signed with the hardened runtime and secure timestamps (Sparkle inside-out), the DMG is signed, and when `ASC_KEY_ID`, `ASC_ISSUER_ID` and `ASC_PRIVATE_KEY_PATH` point at an App Store Connect API key it is notarized with `notarytool`, stapled and checked with `spctl`. `NOTARIZE=0` skips notarization.

The About tab reports version, build and the embedded commit (`GlimpseCommit`, suffixed `-dirty` for uncommitted builds).


`Configuration/Updates.plist` contains the public updater configuration. The matching private Ed25519 key is stored in the release owner's login Keychain under Sparkle account `com.tastyjam.glimpse`; only the public key is committed. The initial checked-in appcast has no downloadable release. A configured updater with an empty feed does not mean that a signed public binary has been released.

The distribution owner must supply a stable HTTPS appcast URL and the public EdDSA key from Sparkle's `generate_keys` tool. Keep the private key in the release owner's Keychain or secret store, outside the repository. Include these keys in the final app's Info.plist before signing:

| Key | Value |
| --- | --- |
| `SUFeedURL` | HTTPS URL of the published appcast XML |
| `SUPublicEDKey` | Base64 public EdDSA key |
| `SUEnableAutomaticChecks` | Boolean `false`, so checking starts only after opting in |
| `SUAutomaticallyUpdate` | Boolean `false`, so automatic downloading/installing starts only after opting in |
| `SUEnableSystemProfiling` | Boolean `false` |

Package the complete Sparkle framework, preserving its symlinks, helper applications and XPC services. Sign nested code and the login helper with the distribution identity, then sign the containing app, notarize and staple it. Ad-hoc builds are for local development. Sparkle archive signatures supplement Developer ID signing and notarization; neither replaces the other.

For each release, increment `CFBundleVersion` and set `CFBundleShortVersionString`. Archive the completed app with a tool that preserves framework symlinks, for example:

```bash
ditto -c -k --sequesterRsrc --keepParent build/Glimpse.app Glimpse.zip
```

Use Sparkle's `generate_appcast` with Glimpse's named Keychain account on a directory containing the release archive:

```bash
.build/artifacts/sparkle/Sparkle/bin/generate_appcast --account com.tastyjam.glimpse /path/to/release-archives
```

The default account `ed25519` is not Glimpse's key. The command generates the appcast and archive signatures. Upload the archive and resulting feed to their HTTPS locations. Keep the archive bytes unchanged after signing. Use the actual build number for `sparkle:version`, the display version for `sparkle:shortVersionString`, and `12.0.0` for `sparkle:minimumSystemVersion` while Monterey remains supported. Test an update from a previously signed build using the release feed before distribution, including a rejected modified archive, manual checks, opt-in persistence, installation and relaunch.

See Sparkle's [programmatic setup](https://sparkle-project.org/documentation/programmatic-setup/), [configuration reference](https://sparkle-project.org/documentation/customization/), and [publishing instructions](https://sparkle-project.org/documentation/publishing/) for the supported release tools and signature workflow.

## Start at login

On macOS 13 and later, Glimpse registers the main app with `SMAppService`. The toggle reflects the service's current enabled status. A registration awaiting approval is shown explicitly, with instructions to enable Glimpse in **System Settings > General > Login Items**. Glimpse refreshes the status when settings are revisited; it does not enable login automatically.

On macOS 12, Glimpse uses `SMLoginItemSetEnabled` with the bundled `com.tastyjam.glimpse.loginhelper` application in `Contents/Library/LoginItems/GlimpseLoginHelper.app`. The helper opens its containing Glimpse app only if it is not already running, and exits after the launch callback or a 15-second timeout. Monterey's legacy API cannot reliably report whether a login item is currently enabled. The toggle therefore shows the last successfully requested value, and its status explains that limitation. Verify it by logging out and back in.

To uninstall, use **Remove Glimpse…** in General settings: after confirmation it turns off start at login, optionally deletes saved settings (the `com.tastyjam.glimpse` defaults domain), moves the app bundle to the Trash (restorable) and quits. Manually: turn off start at login, quit Glimpse and move it to the Trash. Remove any manually added login item separately in macOS Login Items. Moving the installed app, replacing development signatures, and macOS approval decisions can affect login-item registration. Runtime checks on macOS 12, Intel hardware, and signed/notarized distribution builds remain required; compilation alone does not validate login or update installation.

## Mac App Store roadmap

The owner wants a free Mac App Store edition with optional support and reviews. That requires a separate sandboxed distribution build that excludes Sparkle and receives updates through the store. Native metric access, login behavior, entitlements and app review still require validation in that build; the direct-download package is not a submission-ready store archive.

Optional support should use StoreKit in-app purchases for developer tips, without locking monitoring features. Apple permits in-app purchase currencies for tipping developers in its [review guidelines](https://developer.apple.com/app-store/review/guidelines/). Review requests should use Apple's [native StoreKit review API](https://developer.apple.com/documentation/StoreKit/requesting-app-store-reviews); the system decides whether a prompt appears. Neither tip products nor review prompts are implemented in the current direct-download build.
