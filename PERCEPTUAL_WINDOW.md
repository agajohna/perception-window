# Curiosity — Perceptual Window

## The issue

When the phone is held between the user's eyes and an object, the object shown on-screen is not the same apparent size as the real object around the phone's edges. That breaks the illusion of transparency.

We do not want an expensive live calibration system yet. For now, treat this like a fixed perceptual handicap: a **device-specific baseline zoom** that corrects the ordinary viewing case.

## Goal

Make the phone feel less like a camera and more like a piece of transparent glass.

## Prototype approach

Assume a normal inspection posture:

- Phone roughly 12–16 inches from the user's eyes
- Subject roughly 2–5 feet beyond the phone
- Portrait orientation
- User looking near the center of the screen

Test fixed zoom values: `1.00`, `1.10`, `1.18`, `1.25`, `1.30`

Choose the value that makes the preview feel most geometrically faithful during normal use.

**No user-facing calibration screen. No slider. No front-camera eye tracking. No continuous distance estimation.**

## Implementation

Hidden configuration in `PerceptionConfiguration`:

- `perceptualBaselineZoom` — physical camera zoom (default `1.18`)
- Physical camera 1.18× = Curiosity perceptual 1.00× (neutral window state)

## Two visual states

### Window state

Default camera preview. Uses `perceptualBaselineZoom`. No global magnification animation. Camera should feel stable and transparent.

### Lens state

When the user holds the eye button and the system has selected a subject:

- Keep the overall scene at the perceptual baseline
- Gently magnify only the selected subject region (`lensMagnification`, ~1.15×–1.35× relative to window state)
- Animate smoothly; release returns to normal scale

**At rest, it is a window. Under curiosity, it becomes a lens.**

## Avoid

- Zooming the entire camera feed when the eye activates
- Sudden digital zoom jumps
- Visible calibration UI
- Running front and rear cameras simultaneously
- Continuous eye-distance calculations
- LiDAR dependency for this stage

## Testing method

Use an object that crosses the phone's edge (e.g. Zebra printer). Hold in normal inspection position. Compare the portion visible outside the phone with the same object inside the screen. Choose the fixed zoom where apparent sizes align most naturally. Test on the actual target device.

## Product principle

Correct the ordinary case first. Calculate the exceptional case later.

This is not yet a full optical model. It is a practical perceptual correction that should make the app disappear more convincingly today.
