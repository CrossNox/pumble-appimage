#!/usr/bin/env bash
# usage: build-appimage.sh <Pumble-linux-X.Y.Z.deb> [output.AppImage]
set -euo pipefail

deb=$(readlink -f "${1:?usage: $0 <Pumble-linux-X.Y.Z.deb> [output.AppImage]}")
version=$(basename "$deb" | sed -n 's/^Pumble-linux-\(.*\)\.deb$/\1/p')
[ -n "$version" ] || { echo "can't parse version from ${1##*/}" >&2; exit 1; }
out=$(readlink -f "${2:-Pumble-$version-x86_64.AppImage}")

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

if command -v dpkg-deb >/dev/null; then
    dpkg-deb -x "$deb" "$tmp/root"
else
    (cd "$tmp" && ar x "$deb")
    mkdir "$tmp/root"
    tar -xf "$tmp"/data.tar.* -C "$tmp/root"
fi

appdir=$tmp/AppDir
mkdir "$appdir"
cp -a "$tmp/root/opt/Pumble/." "$appdir/"
cp "$tmp/root/usr/share/icons/hicolor/256x256/apps/pumble-desktop.png" "$appdir/"
ln -s pumble-desktop.png "$appdir/.DirIcon"

# electron-builder marker; with it present the app tries deb-style autoupdates
rm -f "$appdir/resources/package-type"

# chrome-sandbox can't be setuid inside an AppImage, so use the userns
# sandbox where the kernel allows it and --no-sandbox elsewhere
cat >"$appdir/AppRun" <<'EOF'
#!/bin/bash
here=$(dirname "$(readlink -f "$0")")
if [ "$(cat /proc/sys/kernel/unprivileged_userns_clone 2>/dev/null || echo 1)" = 1 ]; then
    exec "$here/pumble-desktop" "$@"
else
    exec "$here/pumble-desktop" --no-sandbox "$@"
fi
EOF
chmod +x "$appdir/AppRun"

cat >"$appdir/pumble-desktop.desktop" <<EOF
[Desktop Entry]
Name=Pumble
Exec=pumble-desktop %U
Terminal=false
Type=Application
Icon=pumble-desktop
StartupWMClass=Pumble
MimeType=x-scheme-handler/pumble;
Categories=Network;Office;
X-AppImage-Version=$version
EOF

tool=${APPIMAGETOOL:-$(command -v appimagetool || true)}
if [ -z "$tool" ]; then
    tool=$tmp/appimagetool
    curl -fsSL -o "$tool" https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage
    chmod +x "$tool"
fi

# APPIMAGE_EXTRACT_AND_RUN so the tool works without FUSE (CI)
ARCH=x86_64 APPIMAGE_EXTRACT_AND_RUN=1 "$tool" "$appdir" "$out"
