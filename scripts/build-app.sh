#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
configuration="${CONFIGURATION:-release}"
architecture="${ARCH:-$(uname -m)}"
signing_identity="${CODESIGN_IDENTITY:--}"
version="${VERSION:-0.3.0}"
build_number="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
# APP_STORE=1 builds the Mac App Store edition: sandboxed, without Sparkle or
# the update feed, into build/AppStore/Glimpse.app. PROVISIONING_PROFILE (a Mac
# App Store profile) is embedded when set; scripts/make-pkg.sh drives this.
app_store="${APP_STORE:-}"
[[ "$app_store" == "1" ]] || app_store=""
if [[ -n "$app_store" ]]; then
    export GLIMPSE_APP_STORE=1
    # Separate scratch directory so switching editions does not rebuild everything.
    swift_build=(swift build --scratch-path .build/appstore)
    bundle="build/AppStore/Glimpse.app"
    rm -rf "$bundle"
    extra_info="<key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
<key>ITSAppUsesNonExemptEncryption</key><false/>"
else
    swift_build=(swift build)
    bundle="build/Glimpse.app"
    extra_info=""
fi
# Distribution identities need the hardened runtime and a secure timestamp
# for notarization; ad-hoc development builds keep plain signatures.
sign_flags=(--force --sign "$signing_identity")
if [[ "$signing_identity" != "-" ]]; then
    sign_flags+=(--options runtime --timestamp)
fi
if [[ "$architecture" != "arm64" && "$architecture" != "x86_64" && "$architecture" != "universal" ]]; then
    echo "ARCH must be arm64, x86_64, or universal" >&2
    exit 2
fi
mkdir -p build
if [[ "$architecture" == "universal" ]]; then
    "${swift_build[@]}" -c "$configuration" --arch arm64 --arch x86_64
    binary_dir="$("${swift_build[@]}" -c "$configuration" --arch arm64 --arch x86_64 --show-bin-path)"
else
    "${swift_build[@]}" -c "$configuration" --arch "$architecture"
    binary_dir="$("${swift_build[@]}" -c "$configuration" --arch "$architecture" --show-bin-path)"
fi
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources" "$bundle/Contents/Frameworks"
cp "$binary_dir/Glimpse" "$bundle/Contents/MacOS/Glimpse"
resource_bundle="Glimpse_GlimpseApp.bundle"
if [[ ! -d "$binary_dir/$resource_bundle" ]]; then
    echo "Missing SwiftPM resource bundle: $binary_dir/$resource_bundle" >&2
    exit 1
fi
ditto "$binary_dir/$resource_bundle" "$bundle/Contents/Resources/$resource_bundle"
cat > "$bundle/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Glimpse</string>
<key>CFBundleIdentifier</key><string>com.tastyjam.glimpse</string>
<key>CFBundleName</key><string>Glimpse</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$version</string>
<key>CFBundleVersion</key><string>$build_number</string>
<key>LSMinimumSystemVersion</key><string>12.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
$extra_info
<key>GlimpseCommit</key><string>$(git rev-parse --short HEAD 2>/dev/null || echo unknown)$(git diff --quiet HEAD 2>/dev/null || echo -dirty)</string>
<key>NSHumanReadableCopyright</key><string>Copyright © 2026 Tasty Jam App Development. MIT licensed.</string>
</dict></plist>
PLIST
if [[ -f "$bundle/Contents/LICENSE" ]]; then
    mv "$bundle/Contents/LICENSE" "$bundle/Contents/Resources/LICENSE"
fi
cp LICENSE "$bundle/Contents/Resources/LICENSE"
app_sign_flags=("${sign_flags[@]}")
helper_sign_flags=("${sign_flags[@]}")
if [[ -z "$app_store" ]]; then
python3 - <<'PY'
from pathlib import Path
import plistlib
info = Path('build/Glimpse.app/Contents/Info.plist')
with info.open('rb') as file:
    values = plistlib.load(file)
with Path('Configuration/Updates.plist').open('rb') as file:
    values.update(plistlib.load(file))
with info.open('wb') as file:
    plistlib.dump(values, file)
PY

# Preserve Sparkle's executable permissions and framework symlinks.
sparkle_source=".build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
ditto "$sparkle_source" "$bundle/Contents/Frameworks/Sparkle.framework"
cp .build/artifacts/sparkle/Sparkle/LICENSE "$bundle/Contents/Resources/Sparkle-LICENSE"
# Sign Sparkle inside-out, as its documentation describes; the Downloader
# service keeps its sandbox entitlements.
sparkle="$bundle/Contents/Frameworks/Sparkle.framework"
codesign "${sign_flags[@]}" "$sparkle/Versions/B/XPCServices/Installer.xpc"
codesign "${sign_flags[@]}" --preserve-metadata=entitlements "$sparkle/Versions/B/XPCServices/Downloader.xpc"
codesign "${sign_flags[@]}" "$sparkle/Versions/B/Autoupdate"
codesign "${sign_flags[@]}" "$sparkle/Versions/B/Updater.app"
codesign "${sign_flags[@]}" "$sparkle"
else
    # The app's entitlements are the sandbox plus the identifiers from the
    # provisioning profile, which App Store Connect requires to match.
    rmdir "$bundle/Contents/Frameworks"
    entitlements="build/AppStore/Glimpse.entitlements"
    cp Configuration/AppStore.entitlements "$entitlements"
    if [[ -n "${PROVISIONING_PROFILE:-}" ]]; then
        cp "$PROVISIONING_PROFILE" "$bundle/Contents/embedded.provisionprofile"
        security cms -D -i "$PROVISIONING_PROFILE" -o build/AppStore/profile.plist
        python3 - "$entitlements" <<'PY'
import plistlib, sys
with open('build/AppStore/profile.plist', 'rb') as file:
    profile = plistlib.load(file)['Entitlements']
with open(sys.argv[1], 'rb') as file:
    values = plistlib.load(file)
for key in ('com.apple.application-identifier', 'com.apple.developer.team-identifier'):
    values[key] = profile[key]
if values['com.apple.application-identifier'].split('.', 1)[1] != 'com.tastyjam.glimpse':
    sys.exit('The provisioning profile is not for com.tastyjam.glimpse.')
with open(sys.argv[1], 'wb') as file:
    plistlib.dump(values, file)
PY
        rm build/AppStore/profile.plist
    fi
    app_sign_flags+=(--entitlements "$entitlements")
    helper_sign_flags+=(--entitlements Configuration/AppStore.entitlements)
fi

helper="$bundle/Contents/Library/LoginItems/GlimpseLoginHelper.app"
mkdir -p "$helper/Contents/MacOS"
cp "$binary_dir/GlimpseLoginHelper" "$helper/Contents/MacOS/GlimpseLoginHelper"
cat > "$helper/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>GlimpseLoginHelper</string>
<key>CFBundleIdentifier</key><string>com.tastyjam.glimpse.loginhelper</string>
<key>CFBundleName</key><string>Glimpse Login Helper</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$version</string>
<key>CFBundleVersion</key><string>$build_number</string>
<key>LSMinimumSystemVersion</key><string>12.0</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
codesign "${helper_sign_flags[@]}" "$helper"
codesign "${app_sign_flags[@]}" "$bundle"
codesign --verify --deep --strict "$bundle"
if [[ "$signing_identity" == "-" ]]; then
    echo "Built $bundle $version ($build_number, $architecture), ad-hoc signed for local use."
else
    echo "Built $bundle $version ($build_number, $architecture), signed by $signing_identity."
fi
