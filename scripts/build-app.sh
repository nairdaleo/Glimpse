#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
configuration="${CONFIGURATION:-release}"
architecture="${ARCH:-$(uname -m)}"
signing_identity="${CODESIGN_IDENTITY:--}"
if [[ "$architecture" != "arm64" && "$architecture" != "x86_64" && "$architecture" != "universal" ]]; then
    echo "ARCH must be arm64, x86_64, or universal" >&2
    exit 2
fi
mkdir -p build
if [[ "$architecture" == "universal" ]]; then
    swift build -c "$configuration" --arch arm64 --arch x86_64
    binary_dir="$(swift build -c "$configuration" --arch arm64 --arch x86_64 --show-bin-path)"
else
    swift build -c "$configuration" --arch "$architecture"
    binary_dir="$(swift build -c "$configuration" --arch "$architecture" --show-bin-path)"
fi
bundle="build/Glimpse.app"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources" "$bundle/Contents/Frameworks"
cp "$binary_dir/Glimpse" "$bundle/Contents/MacOS/Glimpse"
resource_bundle="Glimpse_GlimpseApp.bundle"
if [[ ! -d "$binary_dir/$resource_bundle" ]]; then
    echo "Missing SwiftPM resource bundle: $binary_dir/$resource_bundle" >&2
    exit 1
fi
ditto "$binary_dir/$resource_bundle" "$bundle/Contents/Resources/$resource_bundle"
cat > "$bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Glimpse</string>
<key>CFBundleIdentifier</key><string>com.tastyjam.glimpse</string>
<key>CFBundleName</key><string>Glimpse</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.2.0</string>
<key>CFBundleVersion</key><string>2</string>
<key>LSMinimumSystemVersion</key><string>12.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSHumanReadableCopyright</key><string>Copyright © 2026 Tasty Jam App Development. MIT licensed.</string>
</dict></plist>
PLIST
if [[ -f "$bundle/Contents/LICENSE" ]]; then
    mv "$bundle/Contents/LICENSE" "$bundle/Contents/Resources/LICENSE"
fi
cp LICENSE "$bundle/Contents/Resources/LICENSE"
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
codesign --force --deep --sign "$signing_identity" "$bundle/Contents/Frameworks/Sparkle.framework"

helper="$bundle/Contents/Library/LoginItems/GlimpseLoginHelper.app"
mkdir -p "$helper/Contents/MacOS"
cp "$binary_dir/GlimpseLoginHelper" "$helper/Contents/MacOS/GlimpseLoginHelper"
cat > "$helper/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>GlimpseLoginHelper</string>
<key>CFBundleIdentifier</key><string>com.tastyjam.glimpse.loginhelper</string>
<key>CFBundleName</key><string>Glimpse Login Helper</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.2.0</string>
<key>CFBundleVersion</key><string>2</string>
<key>LSMinimumSystemVersion</key><string>12.0</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
codesign --force --sign "$signing_identity" "$helper"
codesign --force --sign "$signing_identity" "$bundle"
codesign --verify --deep --strict "$bundle"
echo "Built $bundle ($architecture). Distribution still requires Developer ID signing and notarization."
