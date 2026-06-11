#!/usr/bin/env bash
# Repackage Pumble's official Linux deb as an AppImage.
set -euo pipefail

feed=https://pumble.com/download/desktop/linux

usage() {
    cat >&2 <<EOF
usage: ${0##*/} check
       ${0##*/} fetch [-o file.AppImage]
       ${0##*/} build [-o file.AppImage] <Pumble-linux-X.Y.Z.deb>

  check   print the newest version in the upstream update feed
  fetch   download the newest deb, verify its sha512 and build an AppImage
  build   build an AppImage from a deb you already have
EOF
    exit 64
}

die() { echo "${0##*/}: $*" >&2; exit 1; }

# parse latest-linux.yml into version/deb_name/sha512/released
read_feed() {
    local yml
    yml=$(curl -fsSL "$feed/latest-linux.yml")
    version=$(awk '/^version:/ {print $2}' <<<"$yml")
    deb_name=$(awk '/^path:/ {print $2}' <<<"$yml")
    sha512=$(awk '/^sha512:/ {print $2}' <<<"$yml")
    released=$(awk '/^releaseDate:/ {print $2}' <<<"$yml" | tr -d "'")
    if [ -z "$version" ] || [ -z "$deb_name" ]; then
        die "can't parse $feed/latest-linux.yml"
    fi
    # make the feed data available to later GitHub Actions steps
    if [ -n "${GITHUB_OUTPUT:-}" ]; then
        printf 'version=%s\ndate=%s\ndeb=%s\n' \
            "$version" "$released" "$deb_name" >>"$GITHUB_OUTPUT"
    fi
}

fetch_deb() {
    echo "fetching $deb_name (released $released)"
    curl -fL --retry 3 -o "$tmp/$deb_name" "$feed/$deb_name"
    if [ "$(openssl dgst -sha512 -binary "$tmp/$deb_name" | base64 -w0)" != "$sha512" ]; then
        die "sha512 mismatch on $deb_name"
    fi
}

build_appimage() {  # <deb> <output (may be empty)>
    local deb=$1 out=$2 version root appdir tool

    version=$(basename "$deb" | sed -n 's/^Pumble-linux-\(.*\)\.deb$/\1/p')
    [ -n "$version" ] || die "can't parse version from ${deb##*/}"
    out=$(readlink -f "${out:-Pumble-$version-x86_64.AppImage}")

    root=$tmp/root
    if command -v dpkg-deb >/dev/null; then
        dpkg-deb -x "$deb" "$root"
    else
        (cd "$tmp" && ar x "$deb")
        mkdir "$root"
        tar -xf "$tmp"/data.tar.* -C "$root"
    fi

    appdir=$tmp/AppDir
    mkdir "$appdir"
    cp -a "$root/opt/Pumble/." "$appdir/"
    cp "$root/usr/share/icons/hicolor/256x256/apps/pumble-desktop.png" "$appdir/"
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
        curl -fsSL -o "$tool" \
            https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage
        chmod +x "$tool"
    fi

    # APPIMAGE_EXTRACT_AND_RUN so the tool works without FUSE (CI)
    ARCH=x86_64 APPIMAGE_EXTRACT_AND_RUN=1 "$tool" "$appdir" "$out"
}

cmd=${1:-}
[ $# -eq 0 ] || shift

out=
while getopts o: opt; do
    case $opt in
        o) out=$OPTARG ;;
        *) usage ;;
    esac
done
shift $((OPTIND - 1))

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

case $cmd in
    check)
        [ $# -eq 0 ] || usage
        read_feed
        echo "$version"
        ;;
    fetch)
        [ $# -eq 0 ] || usage
        read_feed
        fetch_deb
        build_appimage "$tmp/$deb_name" "$out"
        ;;
    build)
        [ $# -eq 1 ] || usage
        build_appimage "$(readlink -f "$1")" "$out"
        ;;
    *)
        usage
        ;;
esac
