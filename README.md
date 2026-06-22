# HoldKey

HoldKey is a tiny macOS menu bar utility for video editors. Hold a trigger key while dragging a keyframe or easing handle, and your mouse movement stays horizontally aligned.

It was built for Adobe Premiere Pro keyframe work, where even a small vertical drift can change a curve while you are only trying to move timing left or right.

## Features

- Horizontal mouse lock while holding a configurable trigger key
- Precise modifier-key activation via `flagsChanged`
- Drag latch: the lock stays active until the mouse button is released, so curves do not fall when you release the trigger key mid-drag
- Natural X-axis sensitivity
- Optional “Only in Premiere Pro” mode
- Start at login
- Native macOS menu bar app

## Requirements

- macOS 12 or newer
- Accessibility permission for HoldKey
- Swift toolchain / Xcode command line tools to build from source

## Build

```bash
./build.sh
```

The build script creates `HoldKey.app` and signs it with a stable local self-signed identity stored in a dedicated keychain. This avoids ad-hoc signing changing the app identity on every rebuild.

Install it manually:

```bash
cp -R HoldKey.app /Applications/
open /Applications/HoldKey.app
```

Then enable HoldKey in:

System Settings -> Privacy & Security -> Accessibility

## Usage

1. Open HoldKey from `/Applications`.
2. Click the menu bar cursor icon.
3. Choose your trigger key with `Change Key...`.
4. In Premiere Pro, hold the trigger key while dragging a keyframe or easing handle.

Menu bar icon colors:

- Green: enabled and ready
- Yellow: horizontal lock active
- Gray: disabled
- Red: Accessibility permission missing

## Notes

HoldKey works at the macOS event level with `CGEventTap`. It is a standalone utility, not an Adobe plugin.

## License

MIT
