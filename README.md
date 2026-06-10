# Pumble AppImage

Unofficial AppImage builds of [Pumble](https://pumble.com), the team chat app —
for Fedora and any other Linux distribution that doesn't use deb packages.
Not affiliated with Pumble/CAKE.com.

## Install

1. Download `Pumble-X.Y.Z-x86_64.AppImage` from the
   [latest release](../../releases/latest).
2. Make it executable and run it:

   ```bash
   chmod +x Pumble-*-x86_64.AppImage
   ./Pumble-*-x86_64.AppImage
   ```

To get a menu entry and icon, add it with
[Gear Lever](https://flathub.org/apps/it.mijorus.gearlever) (recommended) or
any other AppImage integration tool.

## Updates

The AppImage does not update itself. New upstream versions are picked up
automatically and published here as releases, usually within a day — click
**Watch → Custom → Releases** on this repo to get notified, or let Gear Lever
check for updates for you.

## Is this safe?

Every release is built unattended by a
[GitHub Actions workflow](.github/workflows/release.yml) in this repo: it
downloads the official deb from `pumble.com`, verifies its sha512 checksum
against Pumble's own update feed, and repackages the unmodified app as an
AppImage. No code is added or changed — you can audit the couple of shell
scripts that do it.

## Known issues

- The in-app **"Launch at startup"** setting doesn't work (it expects a
  system-wide installation). Add the AppImage to your desktop environment's
  autostart settings instead.

## Building it yourself

```bash
./fetch-and-build.sh                          # latest version, straight from pumble.com
./build-appimage.sh Pumble-linux-X.Y.Z.deb    # from a deb you already have
```

Requires `curl`, `tar`, `ar` (binutils) and `openssl`; appimagetool is
downloaded automatically.
