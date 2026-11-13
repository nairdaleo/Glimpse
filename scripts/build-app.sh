#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
configuration="${CONFIGURATION:-release}"
architecture="${ARCH:-$(uname -m)}"
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
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
cp "$binary_dir/Glimpse" "$bundle/Contents/MacOS/Glimpse"
cat > "$bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Glimpse</string>
<key>CFBundleIdentifier</key><string>com.tastyjam.glimpse</string>
<key>CFBundleName</key><string>Glimpse</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
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
codesign --force --sign - "$bundle"
echo "Built $bundle ($architecture; development signature only)"
