# HoldKey

<p align="center">
  <img src="assets/holdkey-logo.jpeg" alt="HoldKey logo" width="360">
</p>

Bad ease-ease keyframes in Premiere Pro because your mouse moved one pixel down while you only wanted to slide the timing left or right?

Same. HoldKey is for that.

Hold a key, drag a keyframe or easing handle, and your mouse stays locked to a perfectly horizontal line. Scale curves, rotation curves, position curves — no tiny vertical drift ruining the shape.

## Why

Premiere Pro keyframe editing is weirdly easy to mess up:

- You grab an ease handle.
- You try to move it horizontally.
- Your mouse drifts slightly up or down.
- The curve changes.
- You fix it.
- It happens again.

HoldKey removes that little fight.

## What It Does

- Locks mouse movement horizontally while you hold your trigger key
- Keeps natural X-axis mouse sensitivity
- Prevents the curve from dropping when you release the key mid-drag
- Lets you choose your own trigger key
- Can run only inside Premiere Pro
- Lives quietly in the macOS menu bar
- Supports start at login

## Install

Build from source:

```bash
./build.sh
```

Install:

```bash
cp -R HoldKey.app /Applications/
open /Applications/HoldKey.app
```

Then allow it in:

```text
System Settings -> Privacy & Security -> Accessibility
```

HoldKey needs Accessibility permission because it uses macOS event taps to modify mouse movement before Premiere sees it.

## Usage

1. Open HoldKey.
2. Click the menu bar cursor icon.
3. Choose `Change Key...`.
4. Press the key you want to hold while locking movement.
5. In Premiere Pro, hold that key while dragging a keyframe or easing handle.

Icon colors:

- Green: ready
- Yellow: locking right now
- Gray: disabled
- Red: Accessibility permission missing

## Built For

- Adobe Premiere Pro keyframes
- Scale / rotation / position curves
- Ease handles
- Editors who do not want to fight tiny accidental vertical mouse movement

HoldKey is not an Adobe plugin. It is a small native macOS menu bar app.

## Requirements

- macOS 12+
- Swift toolchain / Xcode command line tools
- Accessibility permission

## License

MIT

If HoldKey saves you from fixing one more cursed scale curve, starring the repo helps other editors find it.
