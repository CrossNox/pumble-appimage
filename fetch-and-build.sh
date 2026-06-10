#!/usr/bin/env bash
# Fetch Pumble's Linux update feed, download the latest deb, verify its sha512
# and repackage it as an AppImage in the current directory.
#   --check   only print the latest upstream version, don't download or build
set -euo pipefail

FEED="https://pumble.com/download/desktop/linux"

YML="$(curl -fsSL "$FEED/latest-linux.yml")"
VERSION="$(awk '/^version:/{print $2}' <<<"$YML")"
DEB_NAME="$(awk '/^path:/{print $2}' <<<"$YML")"
SHA512_B64="$(awk '/^sha512:/{print $2}' <<<"$YML")"
DATE="$(awk '/^releaseDate:/{print $2}' <<<"$YML" | tr -d "'")"
[ -n "$VERSION" ] && [ -n "$DEB_NAME" ] || { echo "error: could not parse feed" >&2; exit 1; }

# Expose feed data to subsequent GitHub Actions steps
if [ -n "${GITHUB_OUTPUT:-}" ]; then
    printf 'version=%s\ndate=%s\ndeb=%s\n' "$VERSION" "$DATE" "$DEB_NAME" >> "$GITHUB_OUTPUT"
fi

if [ "${1:-}" = "--check" ]; then
    echo "$VERSION"
    exit 0
fi

echo "==> Upstream version: $VERSION (released $DATE)"
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

"$(dirname "$0")/build-appimage.sh" "$WORK/$DEB_NAME" "Pumble-$VERSION-x86_64.AppImage"
