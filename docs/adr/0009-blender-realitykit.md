# ADR-0009: Assets in Blender, rendering in RealityKit, SwiftUI on top

Date: 2026-09-11
Status: Accepted
Supersedes: ADR-0007 (Metal SDF raymarching) and ADR-0008 (Spline), neither of which reached code

## Context

ADR-0008 adopted Spline while openly recording that no source confirmed the reference app used
it. That is a hunch with a disclaimer attached, and it was correctly challenged.

Researched properly. **(Not Boring) Weather is built by Andy Allen and Mark Dawson at Andy Works,
with 3D assets authored in Blender and rendered in SceneKit**, in their own words: SceneKit was
chosen because it is "a bit more primitive than Unity, [but] it had everything we need, and it
plays nicely with the rest of Apple's frameworks", blending "a SceneKit 3D scene in the background
with SwiftUI or UIKit elements on top." Blender because it is "free, super capable."

## Decision

**Blender → USDZ → RealityKit, with SwiftUI composited on top.**

The architecture to copy is theirs: *a real 3D scene behind, native UI in front, assets authored
in a real 3D tool.* The renderer is not, and the reason is specific rather than fashionable:
**SceneKit is soft-deprecated** — Apple's investment has moved to RealityKit. Not Boring chose
SceneKit years before that happened. Starting new, long-lived work on it today buys a migration we
would rather not schedule.

`RealityView` composites natively with SwiftUI from iOS 18, which is our floor, and its `update:`
closure re-runs whenever bound state changes — that is the hook live weather drives the scene
through. USDZ is Apple's own interchange format and Blender exports it directly.

## Rejected

- **Blender → SceneKit.** Exactly what the reference ships, and it demonstrably works. Rejected
  only for the deprecation; if RealityKit proves awkward for this look, this is the fallback and
  it is a proven one.
- **Spline + `SplineRuntime`** (ADR-0008). Capable, and its live-data API verifies. But it is a
  closed 8.6 MB binary with **no LICENSE file in the repository**, and it is not what the
  reference uses. Taking on a proprietary dependency in order to imitate a stack that does not use
  it is the worst of both worlds.
- **Metal SDF raymarching** (ADR-0007). Technically sound and beside the point: the bottleneck was
  never the renderer, it was that the art must be authored by a person with taste either way.
- **Rive and Lottie.** Both are excellent, genuinely data-drivable runtimes. Both are 2D, and the
  look is lit 3D with real shadow.

## Consequences

**The art is authored by a person in Blender, and that person is not me.** This is unchanged from
ADR-0008 and is the real commitment in this direction. It is better here than there: Blender is
free, open source, and the exact tool the reference uses.

**A scene contract comes before any art.** The exact entity names, the variable ranges, and the
units the app will drive. If the app sends cloud cover as 0–1 and the model expects 0–100, nothing
moves and nothing errors. That document is mine and it is the first thing built in 7.1.

**Nothing proprietary, nothing to licence, nothing closed.** Blender is GPL, USDZ is Apple's,
RealityKit is first-party. There is no third-party framework in the shipping binary and no
unresolved licence blocking the App Store.
