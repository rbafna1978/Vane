---
name: ios-3d
description: Rendering three-dimensional scenes and materials on iOS — RealityKit entities and materials, Metal shaders and the frame loop, and why SceneKit is not the answer any more. Use when building or reviewing any rendered scene, custom material, or GPU work in this app.
license: MIT (reference documents by Nagarjuna2997, ios-agent-skill)
---

# Rendering in three dimensions on iOS

Installed under Rule 1 for Vane's phase 7 rebuild, because no installed skill covered rendered
3D scenes and the decision — RealityKit versus SceneKit versus raw Metal versus pre-rendered
sprites — is architectural and expensive to get wrong.

**The headline finding, which contradicts most training data: `SceneKit` is soft-deprecated as of
iOS 26. New 3D work uses RealityKit.** Anything suggesting SceneKit for a new scene is out of
date; `references/scenekit.md` is kept only so that advice can be recognised and rejected.

- `references/realitykit.md` — entities, components, materials, lighting, `Model3D`, the
  `RealityView` SwiftUI bridge.
- `references/metal.md` — shaders, compute, and the frame loop, for anything RealityKit's
  material system cannot express.
- `references/scenekit.md` — what not to reach for, and why.
- `references/accessibility.md` — Dynamic Type, VoiceOver and Reduce Motion, which a rendered
  scene has to answer for exactly as much as a stack of labels does.

Only the reference documents were installed. The upstream project also ships MCP servers, a
scaffolding CLI and 24 subagents; that is infrastructure, and infrastructure gets installed with
the user's agreement, not as a side effect of wanting a reference document.
