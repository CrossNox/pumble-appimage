#!/usr/bin/env bash
# Repackage Pumble's official Linux deb as an AppImage.
set -euo pipefail

feed=https://pumble.com/download/desktop/linux

usage() {
    cat >&2 <<EOF
usage: ${0##*/} --check
       ${0##*/} --fetch [--build] [-o file.AppImage]
       ${0##*/} --build [-o file.AppImage] <Pumble-linux-X.Y.Z.deb>

  --check   print the newest version in the upstream update feed
  --fetch   download the newest deb into the current directory and
            verify its sha512 against the feed
  --build   repackage the deb (the one just fetched, or the one given
            as an argument) as an AppImage
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
    curl -fL --retry 3 -o "$deb_name" "$feed/$deb_name"
    if [ "$(openssl dgst -sha512 -binary "$deb_name" | base64 -w0)" != "$sha512" ]; then
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

# Browser login hands the session back via a pumble:// URL, which only works
# if something on the host handles that scheme. Register a desktop entry
# (menu entry + scheme handler) pointing at this AppImage, unless another
# handler already exists or PUMBLE_NO_INTEGRATION is set. Rewritten whenever
# the AppImage path changes.
if [ -n "$APPIMAGE" ] && [ -z "$PUMBLE_NO_INTEGRATION" ]; then
    data=${XDG_DATA_HOME:-$HOME/.local/share}
    desktop=$data/applications/pumble-appimage.desktop
    handler=$(xdg-mime query default x-scheme-handler/pumble 2>/dev/null)
    if { [ -z "$handler" ] || [ "$handler" = pumble-appimage.desktop ]; } &&
        ! grep -qF "Exec=\"$APPIMAGE\" %U" "$desktop" 2>/dev/null; then
        mkdir -p "$data/applications" "$data/icons/hicolor/256x256/apps"
        cp -f "$here/pumble-desktop.png" "$data/icons/hicolor/256x256/apps/" 2>/dev/null
        cat >"$desktop" <<DESKTOP
[Desktop Entry]
Name=Pumble
Exec="$APPIMAGE" %U
Terminal=false
Type=Application
Icon=pumble-desktop
StartupWMClass=Pumble
MimeType=x-scheme-handler/pumble;
Categories=Network;Office;
DESKTOP
        update-desktop-database "$data/applications" 2>/dev/null
        xdg-mime default pumble-appimage.desktop x-scheme-handler/pumble 2>/dev/null
    fi
fi

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

check=no fetch=no build=no out='' deb=''

[ $# -gt 0 ] || usage
while [ $# -gt 0 ]; do
    case $1 in
        --check) check=yes ;;
        --fetch) fetch=yes ;;
        --build) build=yes ;;
        -o) [ $# -ge 2 ] || usage; out=$2; shift ;;
        -*) usage ;;
        *) [ -z "$deb" ] || usage; deb=$1 ;;
    esac
    shift
done

if [ $check = yes ]; then
    if [ $fetch = yes ] || [ $build = yes ] || [ -n "$deb" ]; then
        usage
    fi
    read_feed
    echo "$version"
    exit 0
fi

[ $fetch = yes ] || [ $build = yes ] || usage
[ $build = yes ] || [ -z "$out" ] || usage  # -o only makes sense with --build

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

if [ $fetch = yes ]; then
    [ -z "$deb" ] || usage  # --fetch picks its own deb
    read_feed
    fetch_deb
    deb=$deb_name
fi

if [ $build = yes ]; then
    [ -n "$deb" ] || usage
    build_appimage "$(readlink -f "$deb")" "$out"
fi
