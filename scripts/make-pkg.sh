#!/bin/bash
# Builds the Mac App Store edition (sandboxed, universal, no Sparkle) and wraps
# it in an installer package: build/Glimpse-<version>-AppStore.pkg
#
#   VERSION=0.3.0 PROVISIONING_PROFILE=Glimpse.provisionprofile scripts/make-pkg.sh
#
# Signing: MAS_APP_IDENTITY and MAS_INSTALLER_IDENTITY, else the first
# "Apple Distribution"/"3rd Party Mac Developer Application" and
# "3rd Party Mac Developer Installer" identities in the keychain. Without them
# the app is ad-hoc signed and the package unsigned: enough to test the sandbox
# locally, not uploadable.
# Upload: UPLOAD=1 with ASC_KEY_ID, ASC_ISSUER_ID and ASC_PRIVATE_KEY_PATH sends
# the package to App Store Connect.
set -euo pipefail
cd "$(dirname "$0")/.."

version="${VERSION:-0.3.0}"
build_number="${BUILD_NUMBER:-$(git rev-list --count HEAD)}"
identities="$(security find-identity -v)"
first_identity() { sed -n "s/.*\"\\($1: [^\"]*\\)\".*/\\1/p" <<<"$identities" | head -1; }
app_identity="${MAS_APP_IDENTITY:-$(first_identity "Apple Distribution")}"
app_identity="${app_identity:-$(first_identity "3rd Party Mac Developer Application")}"
installer_identity="${MAS_INSTALLER_IDENTITY:-$(first_identity "3rd Party Mac Developer Installer")}"

APP_STORE=1 ARCH=universal VERSION="$version" BUILD_NUMBER="$build_number" CODESIGN_IDENTITY="${app_identity:--}" ./scripts/build-app.sh

pkg="build/Glimpse-$version-AppStore.pkg"
rm -f "$pkg"
if [[ -n "$app_identity" && -n "$installer_identity" ]]; then
    productbuild --component build/AppStore/Glimpse.app /Applications --sign "$installer_identity" "$pkg"
else
    productbuild --component build/AppStore/Glimpse.app /Applications "$pkg"
    echo "WARNING: no App Store distribution identities; $pkg is for local testing only." >&2
fi

if [[ "${UPLOAD:-0}" == "1" ]]; then
    [[ -n "$app_identity" && -n "$installer_identity" && -n "${PROVISIONING_PROFILE:-}" ]] \
        || { echo "Upload needs distribution identities and PROVISIONING_PROFILE." >&2; exit 1; }
    : "${ASC_KEY_ID:?}" "${ASC_ISSUER_ID:?}" "${ASC_PRIVATE_KEY_PATH:?}"
    # altool finds the key by file name in API_PRIVATE_KEYS_DIR.
    keys="$(mktemp -d)"
    trap 'rm -rf "$keys"' EXIT
    cp "$ASC_PRIVATE_KEY_PATH" "$keys/AuthKey_$ASC_KEY_ID.p8"
    API_PRIVATE_KEYS_DIR="$keys" xcrun altool --upload-app --type macos --file "$pkg" \
        --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
fi
echo "$pkg"
