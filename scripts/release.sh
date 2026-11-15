#!/bin/bash
# Publishes a Glimpse release from this Mac. Signing, notarization, the Sparkle
# key and App Store Connect credentials stay local; GitHub stores no secrets.
#
#   scripts/release.sh --env <file> --version x.y.z [--rc N] [--no-app-store]
#
#   --env <file>     private env file with ASC_KEY_ID, ASC_ISSUER_ID,
#                    ASC_PRIVATE_KEY_PATH (and PROVISIONING_PROFILE for the
#                    App Store upload)
#   --version x.y.z  marketing version
#   --rc N           publish vX.Y.Z-rc.N as a GitHub pre-release only
#   --no-app-store   skip the App Store Connect upload
#
# A final release, run from a clean main that matches origin/main:
#   1. swift test
#   2. Developer ID DMG, notarized and stapled (scripts/make-dmg.sh)
#   3. tag vX.Y.Z, GitHub release with the DMG and its sha256, marked latest
#   4. App Store package uploaded (scripts/make-pkg.sh --upload); a failure
#      here is reported and the release continues
#   5. appcast.xml signed with the Sparkle key in the login keychain,
#      committed and pushed to main
#   6. Homebrew cask bumped in the tap
# A pre-release (--rc) does steps 1-3 only.
set -euo pipefail
cd "$(dirname "$0")/.."

tap="nairdaleo/homebrew-tastyjam"
repo="nairdaleo/Glimpse"
sparkle_account="com.tastyjam.glimpse"

# Prints the header comment above.
usage() { sed -n '2,/^set /s/^# \{0,1\}//p' "$0"; }
die() { echo "release: $*" >&2; exit 1; }
keys_env="" version="" rc="" app_store=1
while (( $# )); do
    case "$1" in
        --env) [[ $# -ge 2 ]] || { usage >&2; exit 2; }; keys_env="$2"; shift 2 ;;
        --env=*) keys_env="${1#*=}"; shift ;;
        --version) [[ $# -ge 2 ]] || { usage >&2; exit 2; }; version="$2"; shift 2 ;;
        --version=*) version="${1#*=}"; shift ;;
        --rc) [[ $# -ge 2 ]] || { usage >&2; exit 2; }; rc="$2"; shift 2 ;;
        --rc=*) rc="${1#*=}"; shift ;;
        --no-app-store) app_store=0; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
done
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { usage >&2; die "--version x.y.z is required."; }
[[ -z "$rc" || "$rc" =~ ^[0-9]+$ ]] || die "--rc takes a number."
[[ -f "$keys_env" ]] || die "--env <file> is required and must exist."
set -a; . "$keys_env"; set +a
: "${ASC_KEY_ID:?missing from the env file}" "${ASC_ISSUER_ID:?missing from the env file}" "${ASC_PRIVATE_KEY_PATH:?missing from the env file}"
if [[ -n "$rc" ]]; then tag="v$version-rc.$rc"; name="$version-rc.$rc"; else tag="v$version"; name="$version"; fi

# Everything is checked before anything is published.
git fetch -q origin
[[ "$(git branch --show-current)" == "main" ]] || die "run from main."
[[ -z "$(git status --porcelain)" ]] || die "commit or stash changes first."
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || die "main must match origin/main (pull or push first)."
git rev-parse -q --verify "refs/tags/$tag" >/dev/null && die "tag $tag already exists."
gh release view "$tag" -R "$repo" >/dev/null 2>&1 && die "release $tag already exists."
identity="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)"
[[ -n "$identity" ]] || die "no Developer ID Application identity in the keychain (issue #12)."
if [[ -z "$rc" ]]; then
    gh repo view "$tap" >/dev/null 2>&1 || die "Homebrew tap $tap does not exist."
fi

swift test

VERSION="$version" CODESIGN_IDENTITY="$identity" NOTARIZE=1 scripts/make-dmg.sh
dmg="build/Glimpse-$name.dmg"
[[ "build/Glimpse-$version.dmg" == "$dmg" ]] || mv "build/Glimpse-$version.dmg" "$dmg"
xcrun stapler validate "$dmg" || die "$dmg is not notarized; nothing was published."
(cd build && shasum -a 256 "Glimpse-$name.dmg" > "Glimpse-$name.dmg.sha256")
# make-dmg.sh writes Glimpse-$version.dmg.sha256; for a pre-release that is a stale name.
[[ "$name" == "$version" ]] || rm -f "build/Glimpse-$version.dmg.sha256"

git tag -a "$tag" -m "Glimpse $name"
git push origin "$tag"
if [[ -n "$rc" ]]; then
    gh release create "$tag" -R "$repo" --verify-tag --prerelease --generate-notes --title "Glimpse $name" "$dmg" "$dmg.sha256"
    echo "Published pre-release $tag."
    exit 0
fi
gh release create "$tag" -R "$repo" --verify-tag --latest --generate-notes --title "Glimpse $name" "$dmg" "$dmg.sha256"

app_store_result="skipped (--no-app-store)"
if (( app_store )); then
    if scripts/make-pkg.sh --env "$keys_env" --version "$version" --upload; then
        app_store_result="uploaded"
    else
        app_store_result="FAILED; retry with: git checkout $tag && scripts/make-pkg.sh --env <file> --version $version --upload"
    fi
fi

feed="$(mktemp -d)"
trap 'rm -rf "$feed"' EXIT
cp appcast.xml "$dmg" "$feed/"
.build/artifacts/sparkle/Sparkle/bin/generate_appcast --account "$sparkle_account" \
    --download-url-prefix "https://github.com/$repo/releases/download/$tag/" \
    --link "https://tastyjam.ca/glimpse/" "$feed"
cp "$feed/appcast.xml" appcast.xml
git add appcast.xml
git commit -m "release: appcast for Glimpse $version"
git push origin HEAD:main

git clone -q --depth 1 "https://github.com/$tap.git" "$feed/tap"
mkdir -p "$feed/tap/Casks"
sha="$(cut -d' ' -f1 "$dmg.sha256")"
sed -e "s/{{VERSION}}/$version/" -e "s/{{SHA256}}/$sha/" packaging/homebrew/glimpse.rb.template > "$feed/tap/Casks/glimpse.rb"
git -C "$feed/tap" add Casks/glimpse.rb
git -C "$feed/tap" commit -qm "glimpse $version"
git -C "$feed/tap" push -q origin HEAD

echo "Released $tag: GitHub release, appcast and Homebrew cask. App Store: $app_store_result"
