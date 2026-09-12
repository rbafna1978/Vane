# ADR-0008: The scene is authored in Spline and rendered by SplineRuntime

Date: 2026-09-11
Status: Accepted, with three open questions that must close before shipping
Supersedes: the Metal SDF raymarching decision recorded in ADR-0007

## Context

ADR-0007 chose Metal SDF raymarching for the scene. The reasoning held for Direction B — the
forms were sphere unions and I could write the shader. Two things changed it.

Direction B was rejected at mockup: a mast, cups and a dial are industrial equipment, and no
palette makes a weather station charming. Direction C renders the weather itself — soft clay
cloud, sun, rain, moon — and the user's instruction is to build those objects the way the
reference app does.

**Honesty note:** no source found confirms what Not Boring Weather actually uses. Their App Store
copy says "gaming industry tech"; nobody names a tool. Spline is chosen because the user asked
for it and because it verifies well below, not because it is documented as theirs.

## Decision

**`SplineRuntime`, via Swift Package Manager, with scenes authored in Spline and bundled locally.**

Verified against the package itself rather than the marketing page:

| Requirement | Finding |
| --- | --- |
| Driven by live weather | `setNumberVariable`, `setBoolVariable`, `setStringVariable`, `emitEvent`, `emitEventReverse`, and `findObject(name:)` exposing `position`, `rotation`, `scale`, `visible`, and light `intensity`. |
| Offline first | `init(sceneFileURL: URL?)` accepts any URL, so scenes ship in the bundle. The docs lead with cloud `build.spline.design` URLs; we will not use them. |
| Size | 8.6 MB, `ios-arm64` slice. The repository's 80 MB is six platform slices; the App Store thins the rest. |
| Swift 6 | The interface carries `@preconcurrency` and `@MainActor` annotations, so strict concurrency should hold without `@unchecked Sendable`. |
| Platform floor | iOS 16. We target 18. |

The live-data question was the make-or-break: a renderer that could only play its own canned
animation would be useless, because Vane's whole premise is that the scene is a function of real
observations. It passes.

## Rejected

**Metal SDF raymarching** (ADR-0007's choice). Still technically right and now beside the point:
the bottleneck was never the renderer, it was that I cannot author the art. A shader I write
produces shapes I designed, and two directions have now established that my visual judgement is
the weakest link in this project. Moving the art into a tool built for it, operated by someone
with taste, is the actual fix.

**RealityKit.** Rejected in ADR-0007 for needing authored USDZ assets. That objection dissolves
here — but Spline's editor, material system and particle support are aimed squarely at this look,
and RealityKit would mean building that pipeline ourselves.

## Consequences

**Someone has to author the scenes, and it cannot be me.** Spline is a visual editor. I can wire
the runtime, drive every variable from live weather, and build all thirteen surfaces around it —
but the clouds, the sun and the rain must be modelled by a person in a GUI. This is the single
largest change to how this project works and it is a real, ongoing commitment from the user.

**Three things must close before the App Store, none before a prototype:**

1. **There is no LICENSE file in the repository** and the framework ships as a closed binary.
   Absent a stated licence the default is all rights reserved. This must be resolved with Spline
   directly.
2. **It is a closed binary.** We cannot read it, patch it, or fix a bug in it. If it breaks on an
   iOS release we wait for them. `CLAUDE.md` requires a third-party dependency to be justified
   against a hand-rolled version; the justification is that hand-rolling to this quality bar is
   months of work and does not solve the art problem at all.
3. **A scene contract has to exist before the art does** — the exact variable names, ranges and
   object names the app will drive. If the app expects `cloudCover` as 0–1 and the scene ships a
   variable called `clouds` taking 0–100, nothing moves and nothing errors. That contract is mine
   to write and is the first thing built in 7.1.
