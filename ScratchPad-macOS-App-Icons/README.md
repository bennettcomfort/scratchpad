# Scratch Pad macOS Icons

This package contains two complete Xcode-ready macOS app-icon asset catalogs:

- `ScratchPad-Light/Assets.xcassets/AppIcon.appiconset`
- `ScratchPad-Dark/Assets.xcassets/AppIcon.appiconset`

Each set includes all required macOS icon sizes from 16×16 through 1024×1024 and a valid `Contents.json`.

## Install in Xcode

1. Open your project.
2. Open `Assets.xcassets`.
3. Delete or rename the existing `AppIcon` set.
4. Drag the chosen `AppIcon.appiconset` folder into `Assets.xcassets`.
5. In the target's **General** settings, confirm **App Icons Source** is `AppIcon`.
6. Clean the build folder and rebuild.

The 1024×1024 master image is also included beside each asset catalog.
