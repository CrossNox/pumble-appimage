#!/usr/bin/env bash
# Check Pumble's update feed for a new Linux version; if the GitHub release
# doesn't exist yet, download the deb, verify it, repackage as AppImage and
# publish a release. Requires the gh CLI (authenticated, or GH_TOKEN set).
set -euo pipefail

FEED="https://pumble.com/download/desktop/linux"

YML="$(curl -fsSL "$FEED/latest-linux.yml")"
VERSION="$(awk '/^version:/{print $2}' <<<"$YML")"
DEB_NAME="$(awk '/^path:/{print $2}' <<<"$YML")"
SHA512_B64="$(awk '/^sha512:/{print $2}' <<<"$YML")"
DATE="$(awk '/^releaseDate:/{print $2}' <<<"$YML" | tr -d "'")"
[ -n "$VERSION" ] && [ -n "$DEB_NAME" ] || { echo "error: could not parse feed" >&2; exit 1; }

TAG="v$VERSION"
echo "==> Upstream version: $VERSION (released $DATE)"

if gh release view "$TAG" >/dev/null 2>&1; then
    echo "==> Release $TAG already exists, nothing to do."
    exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> Downloading $FEED/$DEB_NAME"
curl -fL --retry 3 -o "$WORK/$DEB_NAME" "$FEED/$DEB_NAME"

echo "==> Verifying sha512"
ACTUAL="$(openssl dgst -sha512 -binary "$WORK/$DEB_NAME" | base64 -w0)"
if [ "$ACTUAL" != "$SHA512_B64" ]; then
    echo "error: sha512 mismatch (feed: $SHA512_B64, got: $ACTUAL)" >&2
    exit 1
fi

APPIMAGE="Pumble-$VERSION-x86_64.AppImage"
"$(dirname "$0")/build-appimage.sh" "$WORK/$DEB_NAME" "$WORK/$APPIMAGE"

echo "==> Creating release $TAG"
gh release create "$TAG" "$WORK/$APPIMAGE" \
    --title "Pumble $VERSION" \
    --notes "AppImage repackaged from the official deb published $DATE at $FEED/$DEB_NAME (sha512 verified against the upstream update feed)."
echo "==> Released $TAG"
