# Pumble AppImage

Unofficial AppImage builds of [Pumble](https://pumble.com), repackaged from the
official Linux `.deb` releases. Not affiliated with Pumble/CAKE.com.

## Download

Grab the latest `Pumble-*-x86_64.AppImage` from the
[releases page](../../releases/latest), make it executable and run it:

```bash
chmod +x Pumble-*-x86_64.AppImage
./Pumble-*-x86_64.AppImage
```

For menu integration use [Gear Lever](https://flathub.org/apps/it.mijorus.gearlever)
or `appimaged`.

## How it works

- Pumble publishes an electron-updater feed at
  `https://pumble.com/download/desktop/linux/latest-linux.yml`.
- A scheduled GitHub Actions workflow ([release.yml](.github/workflows/release.yml))
  checks it daily. When a version appears that has no `vX.Y.Z` tag here yet,
  [`fetch-and-build.sh`](fetch-and-build.sh) downloads the deb, verifies its
  sha512 against the feed and repackages it as an AppImage, which the workflow
  publishes as a release.
- [`build-appimage.sh`](build-appimage.sh) does the actual repackaging:
  - extracts `/opt/Pumble` from the deb into an AppDir with the desktop entry
    and icon;
  - removes electron-builder's `package-type` marker so the app's auto-updater
    doesn't attempt deb-style updates;
  - adds an `AppRun` that uses the normal Chromium sandbox via unprivileged
    user namespaces (the setuid `chrome-sandbox` can't work inside an
    AppImage), falling back to `--no-sandbox` only where namespaces are
    disabled.

To fetch the latest version and build locally: `./fetch-and-build.sh`
(or `./build-appimage.sh Pumble-linux-X.Y.Z.deb` if you already have a deb).

> **Note:** GitHub pauses scheduled workflows after ~60 days without repo
> activity. If that happens, re-enable it from the Actions tab or trigger the
> workflow manually.

## Known caveats

- The in-app "launch at startup" option expects a system-wide desktop file at
  `/usr/share/applications/pumble-desktop.desktop` and logs an error; add the
  AppImage to your desktop's autostart settings instead.
