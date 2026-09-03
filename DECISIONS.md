# DECISIONS

Append-only. Every ADR and design choice, one line of rationale.

## 2026-09-03

- **Skills are repo-scoped, not global.** Copied the emilkowalski set + `frontend-design` into
  `.claude/skills/` rather than `~/.claude/skills/`. They were only present inside an unrelated
  project (`Interview_Helper/.agents/skills/`), so this session could not see them. Repo-local keeps
  them versioned with the project and mutates nothing global.
- **graphify runs as one repo-wide graph, not per-directory.** `tree-sitter-swift` and
  `tree_sitter_python` are both in the installed extractor, and `.metal` is a recognized extension —
  a single map covers the Xcode target and the FastAPI service. Revisit only if cross-language noise
  makes queries worse.

- **Visual direction: A, The Barograph.** Chosen over the Flight Strip (B) and the Cloud Atlas Plate (C).
  The differentiator is history; the barograph is the one instrument whose purpose is recording history
  continuously on a roll, so the visual language and the product mechanic are the same idea. Chart only —
  paper, grid, ink. Never the machine: no drum, no brass, no leather, no drop shadows.
- **Signature element: the unbroken trace.** Today is the right-hand end of one continuous roll that began
  at install. Dragging left is not navigation — the same paper keeps moving into the archive. The 11-year
  normal runs behind it dashed, so anomaly is a shape before it is a sentence.
- **Consequence: phase 5 redefined.** No shared-element transition between main screen and archive, because
  there is no jump between them. Phase 5 becomes scroll compression + the plate detail view.
- **Palette is a computed state, not a toggle.** paper/grid/ink/trace/wash/alert, with `wash` driven by real
  sun position from lat/lon and time. Grid moved off historical rust to green-grey `#AFBFA9` — rust on pale
  stock is the banned terracotta-on-cream pairing arrived at by an accurate route.
- **Type: FF DIN Condensed display / SF Pro Text body / Berkeley Mono data.** DIN 1451 is the lettering
  standard on European instrument faceplates, so the display face is the type that was on the machine.
  SF for body is deliberate: Dynamic Type and VoiceOver for free, and identity is carried elsewhere.
  Free fallbacks if licensing is declined: Archivo Narrow, JetBrains Mono.
