#!/bin/bash
# Builds a universal Glimpse.app and packages it as build/Glimpse-<version>.dmg
# with a drag-to-Applications window.
#
#   VERSION=0.3.0 BUILD_NUMBER=42 scripts/make-dmg.sh
#
# Signing: uses CODESIGN_IDENTITY, else the first "Developer ID Application"
# identity in the keychain, else ad-hoc (local testing only; Gatekeeper blocks
# ad-hoc apps downloaded from the internet).
# Notarization: runs when Developer ID signed and ASC_KEY_ID, ASC_ISSUER_ID and
# ASC_PRIVATE_KEY_PATH (an App Store Connect API key) are set. NOTARIZE=0 skips.
set -euo pipefail
cd "$(dirname "$0")/.."

version="${VERSION:-0.2.0}"
build_number="${BUILD_NUMBER:-$(git rev-list --count HEAD)}"
identity="${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)}"
identity="${identity:--}"

ARCH=universal VERSION="$version" BUILD_NUMBER="$build_number" CODESIGN_IDENTITY="$identity" ./scripts/build-app.sh

work="build/dmg"
rm -rf "$work"
mkdir -p "$work"
subtitle="Version $version"
swift scripts/dmg/background.swift "$work/background.png" 1 "$subtitle"
swift scripts/dmg/background.swift "$work/background@2x.png" 2 "$subtitle"
tiffutil -cathidpicheck "$work/background.png" "$work/background@2x.png" -out "$work/background.tiff" >/dev/null

# dmgbuild writes Finder layout directly, without scripting Finder, so it also
# works on headless CI runners. Pinned in a private virtualenv.
venv=".build/dmg-venv"
if [[ ! -x "$venv/bin/dmgbuild" ]]; then
    python3 -m venv "$venv"
    "$venv/bin/pip" install --quiet "dmgbuild==1.6.5"
fi

dmg="build/Glimpse-$version.dmg"
rm -f "$dmg"
"$venv/bin/dmgbuild" -s scripts/dmg/settings.py -D app=build/Glimpse.app -D background="$work/background.tiff" "Glimpse $version" "$dmg"

if [[ "$identity" == "-" ]]; then
    echo "WARNING: ad-hoc signed. Fine for local testing; downloads will be blocked by Gatekeeper." >&2
else
    codesign --force --sign "$identity" --timestamp "$dmg"
    if [[ "${NOTARIZE:-1}" == "1" && -n "${ASC_KEY_ID:-}" && -n "${ASC_ISSUER_ID:-}" && -n "${ASC_PRIVATE_KEY_PATH:-}" ]]; then
        xcrun notarytool submit "$dmg" --key "$ASC_PRIVATE_KEY_PATH" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID" --wait
        xcrun stapler staple "$dmg"
        spctl --assess --type open --context context:primary-signature --verbose "$dmg"
    else
        echo "WARNING: signed but not notarized (set ASC_* or NOTARIZE=1)." >&2
    fi
fi
shasum -a 256 "$dmg" | tee "$dmg.sha256"
