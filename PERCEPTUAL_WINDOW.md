# Curiosity — Glass View (Sensor Fusion)

## Goal

Make the display behave like a **physically transparent pane** between the user's eye and the world.

**Key principle:** The camera moves with the phone. The viewpoint stays with the person.

Baseline device: **iPhone 12 mini** (no LiDAR, TrueDepth front, wide + ultra-wide rear).

## Architecture

All sensors fuse into a single `PerceptionState` consumed by the Metal renderer:

```
Front TrueDepth     → viewer/eye pose (on-device only, Glass View active)
Rear wide camera    → primary texture (ARKit)
Rear ultra-wide     → overscan margin (Stage 1+: wide only; dual-texture next)
ARKit               → 6DOF device pose, feature points, planes, intrinsics
IMU                 → high-frequency orientation prediction between frames
Feature points / parallax / planes → dynamic dominant scene depth

PerceptionState → Metal viewpoint-correct reprojection → full-screen Glass View
```

## Rendering rules

1. **Warp-only after init** — never blend unwarped ARSCNView with warped mesh
2. **Graceful fallback** — confidence drops → simplified reprojection → passthrough
3. **Privacy** — front camera runs only during Glass View; no storage, no upload, no identification

## Stages

### Stage 1 — Viewer-aware flat plane (current)

- TrueDepth coarse eye pose (~12 Hz)
- ARKit device pose + IMU prediction
- Dynamic dominant plane depth (features + parallax + planes)
- Wide rear texture via ARKit
- Metal reprojection

### Stage 2 — Motion-refined depth

- Continuous parallax depth from natural phone motion (enabled via `planeDepthSelfTuningEnabled`)

### Stage 3 — Multi-region depth

- Foreground/background planes from feature clusters or monocular depth

### Stage 4 — Dense depth

- LiDAR or Core ML monocular depth where practical

### Stage 5 — Actual viewer position

- Refined gaze from front sensing (beyond coarse TrueDepth landmarks)

## Fallback modes

| Mode | When |
|------|------|
| `fullReprojection` | Viewer pose + tracking + depth confidence high |
| `simplifiedReprojection` | Tracking OK, viewer pose weak — fixed eye distance, dynamic depth |
| `passthrough` | Tracking lost, thermal critical, or repeated warp failures |

## Tuning (legacy A1 fallback when `glassViewSensorFusionEnabled = false`)

| Parameter | When to tune |
|-----------|--------------|
| `virtualEyeDistanceMeters` | Phone still — seam scale |
| `scenePlaneDepthMeters` | Phone slides sideways — parallax |

Double-tap re-locks fusion state.

## Debug

Set `glassViewDebugMetricsEnabled = true` to overlay:

- viewer pose confidence, eye distance, scene depth source
- active rear sources, reprojection error estimate
- fallback mode, thermal state, render latency

## Acceptance test

Rigid object (printer, door frame, monitor edge). Hold phone between one eye and object. Move phone slowly; then move head slightly with phone steady.

Success: object continuity across the physical screen edge; scene feels less like a moving camera feed; head movement updates viewpoint; drift reduced vs fixed-offset version.

## Product principle

Prove the experience on current hardware. If sensor fusion cannot make the screen feel meaningfully less like a camera, fall back to normal preview without blocking continuity or core app features.
