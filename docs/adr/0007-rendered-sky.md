# ADR-0007: The sky is rendered, and it is rendered with SwiftUI's Metal shaders

Date: 2026-09-08
Status: Accepted

## Context

Phase 5c collapsed three pushed screens into one continuous roll. It fixed navigation and, in
doing so, removed the app's only depth. The result was one screen with one screen of content:
a number, a sentence, a hairline trace. Reviewed against the brief, three things were wrong.

1. There is no vertical axis. The roll owns horizontal (time); nothing owns depth.
2. The weather is named in a label rather than rendered. `CLAUDE.md` says "ambient weather is
   content" and Direction A says the wash is computed from sun position *and conditions*. Only
   the first half was ever built: conditions do exactly one thing today, which is drain chroma
   from the paper when it is overcast.
3. Most of the payload never reaches a pixel: `windKt`, `windDeg`, `humidity`, `pressureHpa`,
   the entire `hourly` array, `precipProbability`, and per-day `code`. Direction A is called
   The Barograph. A barograph measures pressure. We download pressure and never display it.

## Decision

**The sky is a real rendered scene, and the barograph is drawn in ink on top of it.**

Direction A survives. The instrument is not replaced by the scene — the two compose, and that
composition is the point: Not Boring Weather has a scene and no instrument, Apple Weather has an
instrument and no scene. Vane has both, and the instrument reads the scene.

**Vertical becomes depth, without navigation.** The roll sits at the top of a scroll; panels
below it carry the hourly curve, precipitation and pressure, wind, the normals, and this date in
every recorded year. Every panel is keyed to the scrub position, so scrubbing horizontally to
September 3rd makes every panel below read September 3rd. Two composed axes, zero pushed screens.

**Rendering uses SwiftUI's `Shader` API (`ShaderLibrary.bundle(.module)` with `.colorEffect`),
not an `MTKView`.**

Rejected: `MTKView`/`CAMetalLayer`. It would mean owning a render loop, a drawable lifecycle, and
a separate compositing path alongside SwiftUI, for capability we do not need — the sky is
per-pixel fragment work with no compute passes, no geometry, and no render-to-texture. The
SwiftUI path composites natively with the views drawn over it, is driven by `TimelineView` rather
than a `CADisplayLink` we maintain, and inherits the view's own lifecycle. Its cost is that it
cannot do compute or multi-pass; if the cloud model ever needs a real fBm accumulation buffer,
this is the decision to revisit.

Rejected: SpriteKit particles for rain. It brings a second scene graph and its own coordinate
system for something a hashed fragment function does in fifteen lines.

## Consequences

**Contrast is now the hard part.** Ink over a flat computed paper was solved by
`guaranteeingContrast(4.5)`. Ink over a rendered scene is not, because the scene varies per pixel.
The rule: the shader is constrained to a luminance band, the CPU computes the scene's worst-case
luminance from the same parameters that drive the shader, and `meetingContrast` pushes ink against
*that* rather than against the paper token. Text regions additionally sit on an opaque paper
gradient — a sheet of chart stock over the view, not a glass panel; glassmorphism stays banned.

**Launch budget wins over the sky.** Cold launch to first meaningful paint stays under 1.2s
(currently ~228ms median). The sky renders after first paint, over cached state, and never gates
it. If that turns out to be impossible the sky loses, not the launch.

**Thermal and refresh scaling is mandatory, not a nicety.** A full-screen fragment shader at
120Hz will warm the device. Baseline is a 30Hz `TimelineView` interval — cloud drift at 30Hz is
imperceptible and costs a quarter of 120 — raised only while precipitation is being drawn, and
paused entirely on `ProcessInfo.thermalState >= .serious` and under `accessibilityReduceMotion`.
The reduced-motion path is a still frame of the same shader at t=0, not a disabled view: the sky
is content, and removing content is not an accessibility accommodation.

**`find-animation-opportunities` does not gate this.** Its four-question gate governs UI
transitions, and correctly protects the scrub interaction, which does not change. Ambient weather
is content under our own rules. The finding taken from it: the delight budget belongs at the
rare/first-time tier, which for a weather app is the first open of the day — that is where the
one orchestrated moment goes, not on every launch.
