#!/usr/bin/env bash
# Download the latest Pumble deb from the official update feed, check its
# sha512 and repackage it as an AppImage here. --check prints the latest
# version and exits.
set -euo pipefail

feed=https://pumble.com/download/desktop/linux

yml=$(curl -fsSL "$feed/latest-linux.yml")
version=$(awk '/^version:/{print $2}' <<<"$yml")
deb=$(awk '/^path:/{print $2}' <<<"$yml")
sha512=$(awk '/^sha512:/{print $2}' <<<"$yml")
released=$(awk '/^releaseDate:/{print $2}' <<<"$yml" | tr -d "'")
[ -n "$version" ] && [ -n "$deb" ] || { echo "can't parse $feed/latest-linux.yml" >&2; exit 1; }

if [ -n "${GITHUB_OUTPUT:-}" ]; then
    printf 'version=%s\ndate=%s\ndeb=%s\n' "$version" "$released" "$deb" >>"$GITHUB_OUTPUT"
fi

if [ "${1:-}" = --check ]; then
    echo "$version"
    exit 0
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

echo "fetching $deb (released $released)"
curl -fL --retry 3 -o "$tmp/$deb" "$feed/$deb"

if [ "$(openssl dgst -sha512 -binary "$tmp/$deb" | base64 -w0)" != "$sha512" ]; then
    echo "sha512 mismatch on $deb" >&2
    exit 1
fi

"$(dirname "$0")/build-appimage.sh" "$tmp/$deb" "Pumble-$version-x86_64.AppImage"
