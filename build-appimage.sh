#!/usr/bin/env bash
# Repackage a Pumble .deb as an AppImage.
# Usage: ./build-appimage.sh <Pumble-linux-X.Y.Z.deb> [output.AppImage]
set -euo pipefail

DEB="$(readlink -f "$1")"
[ -r "$DEB" ] || { echo "error: cannot read $DEB" >&2; exit 1; }

# Version from the filename, e.g. Pumble-linux-1.4.6.deb -> 1.4.6
VERSION="$(basename "$DEB" | sed -n 's/^Pumble-linux-\(.*\)\.deb$/\1/p')"
[ -n "$VERSION" ] || { echo "error: cannot parse version from filename" >&2; exit 1; }

OUT="$(readlink -f "${2:-Pumble-$VERSION-x86_64.AppImage}")"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> Extracting $DEB"
if command -v dpkg-deb >/dev/null 2>&1; then
    dpkg-deb -x "$DEB" "$WORK/data"
else
    (cd "$WORK" && ar x "$DEB")
    mkdir "$WORK/data"
    tar -xf "$WORK"/data.tar.* -C "$WORK/data"
fi

APPDIR="$WORK/Pumble.AppDir"
echo "==> Building AppDir"
mkdir "$APPDIR"
cp -a "$WORK/data/opt/Pumble/." "$APPDIR/"
cp "$WORK/data/usr/share/icons/hicolor/256x256/apps/pumble-desktop.png" "$APPDIR/"
ln -sf pumble-desktop.png "$APPDIR/.DirIcon"

# electron-builder marker that makes the auto-updater attempt deb-style updates
rm -f "$APPDIR/resources/package-type"

cat > "$APPDIR/AppRun" <<'EOF'
#!/bin/bash
HERE="$(dirname "$(readlink -f "${0}")")"
# chrome-sandbox cannot be setuid inside an AppImage; rely on unprivileged
# user namespaces (default on Fedora). Fall back to --no-sandbox if disabled.
if [ "$(cat /proc/sys/kernel/unprivileged_userns_clone 2>/dev/null || echo 1)" = "1" ]; then
    exec "${HERE}/pumble-desktop" "$@"
else
    exec "${HERE}/pumble-desktop" --no-sandbox "$@"
fi
EOF
chmod +x "$APPDIR/AppRun"

cat > "$APPDIR/pumble-desktop.desktop" <<EOF
[Desktop Entry]
Name=Pumble
Exec=pumble-desktop %U
Terminal=false
Type=Application
Icon=pumble-desktop
StartupWMClass=Pumble
MimeType=x-scheme-handler/pumble;
Categories=Network;Office;
X-AppImage-Version=$VERSION
EOF

# Locate or fetch appimagetool
TOOL="${APPIMAGETOOL:-}"
if [ -z "$TOOL" ]; then
    if command -v appimagetool >/dev/null 2>&1; then
        TOOL=appimagetool
    else
        TOOL="$WORK/appimagetool"
        echo "==> Downloading appimagetool"
        curl -fsSL -o "$TOOL" \
            "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage"
        chmod +x "$TOOL"
    fi
fi

echo "==> Packing $OUT"
# APPIMAGE_EXTRACT_AND_RUN: lets the appimagetool AppImage run without FUSE (e.g. on CI)
ARCH=x86_64 APPIMAGE_EXTRACT_AND_RUN=1 "$TOOL" "$APPDIR" "$OUT"
echo "==> Done: $OUT"
