# Pumble AppImage

Unofficial AppImage builds of [Pumble](https://pumble.com), the team chat app — runs on any Linux distribution. Not affiliated with Pumble/CAKE.com.

## Install

1. Download `Pumble-X.Y.Z-x86_64.AppImage` from the [latest release](../../releases/latest).
2. Make it executable and run it:

```bash
chmod +x Pumble-*-x86_64.AppImage
./Pumble-*-x86_64.AppImage
```

On first run the app installs a desktop entry (`~/.local/share/applications/pumble-appimage.desktop`) and icon, which gives you a menu entry and registers the `pumble://` handler that browser-based login needs to hand the session back to the app. It won't touch an existing `pumble://` handler, and you can skip the whole thing with `PUMBLE_NO_INTEGRATION=1` (then register a handler yourself, or login won't complete). If you move or rename the AppImage, run it once to re-point the entry.

## Updates

The AppImage does not update itself. New upstream versions are picked up automatically and published here as releases, usually within a day — click **Watch → Custom → Releases** on this repo to get notified.

## Is this safe?

Every release is built unattended by a [GitHub Actions workflow](.github/workflows/release.yml) in this repo: it downloads the official deb from `pumble.com`, verifies its sha512 checksum against Pumble's own update feed, and repackages the unmodified app as an AppImage. No code is added or changed — you can audit the single short shell script that does it.

## Known issues

- The in-app **"Launch at startup"** setting doesn't work (it expects a system-wide installation). Add the AppImage to your desktop environment's autostart settings instead.

## Building it yourself

```bash
./pumble-appimage.sh --fetch --build
./pumble-appimage.sh --build Pumble-linux-X.Y.Z.deb
```

Requires `curl`, `tar`, `ar` (binutils) and `openssl`; appimagetool is downloaded automatically.
