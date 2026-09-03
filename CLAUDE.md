# Vane — standing rules

Native iOS weather app + FastAPI backend. Shipping to the App Store, not a demo.
No TODOs, no placeholder data, no mock JSON left unreplaced, no "in a real app you would".
Anything that doesn't work end to end gets said out loud, not hidden.

## Product
Weather app that contextualizes the number instead of showing it.
"Warmest September 3rd in eleven years." "Last time it rained here was 47 days ago."
Return loop: morning push card, open streak, Live Activity + widget, the personal archive timeline.
No features beyond that list without arguing for them first.

## Skill protocol
Repo-scoped skills live in `.claude/skills/` (copied in, project-local, not global).

| When | Skill |
|---|---|
| Concept + visual direction | `frontend-design`, `design:user-research` |
| All Swift | `write-swift` |
| Every phase, motion + interface | `apple-design` |
| Before animating anything | `find-animation-opportunities` |
| Naming/specifying motion | `animation-vocabulary` |
| Every animation before review | `review-animations` |
| End of phase 6 | `improve-animations` |
| Tokens, component library | `design:design-system` |
| Every screen before review | `design:design-critique` |
| All UI text | `design:ux-copy` |
| Before any screen is done | `design:accessibility-review` |
| Spec per screen before building | `design:design-handoff` |
| Architecture decisions | `engineering:architecture`, `engineering:system-design` |
| Before writing tests | `engineering:testing-strategy` |
| End of every phase, own diff | `engineering:code-review` |
| Bug taking >1 attempt | `engineering:debug` |
| README, runbook, API docs | `engineering:documentation` |
| Before first deploy | `engineering:deploy-checklist` |
| Every third phase | `engineering:tech-debt` |

Skill guidance outranks my instincts and the user's. Where it conflicts, follow the skill and say where we disagreed.
The emilkowalski set (`apple-design`, `animation-vocabulary`, `review-animations`,
`find-animation-opportunities`, `improve-animations`, `emil-design-eng`) outranks everyone on motion
and interface judgment. Take their reasoning, translate implementation to SwiftUI. Never install a
web package because a skill recommended one.
`find-animation-opportunities` gets special weight: take its "don't animate this" verdicts seriously.

## ponytail
Active plugin, SessionStart hook verified. Level `full`.
ON for phases 1, 2, 8 (backend, ingest, deploy). OFF for phases 3–6 (motion, shaders, design system,
archive) — those are the product. If the ladder says a Metal shader should be `.blur()`, the ladder is
wrong about this brief; say so rather than quietly taking the smaller path.

## graphify
Regenerate the code map at every phase boundary. One repo-wide graph covers Swift + Python
(tree-sitter-swift and tree_sitter_python both present). Consult the map before opening files.
Reading >3 files to answer a structural question means the map is stale or unused.

## Direction: A, The Barograph (locked)
The chart, never the machine. Pale eau-de-nil stock, printed hairline grid, one aniline-violet pen trace.
Signature: the trace never breaks — today is the right end of one roll that began at install; dragging
left is the archive on the same paper. The 11-year normal runs behind it dashed.

Palette (day / night): paper #DFE7DC / #12171A - grid #AFBFA9 / #263029 - ink #1B2021 / #DCE6DE
trace #3A2E6B / #8B7BD4 - alert #B8442E / #E06A4F - wash computed from sun position.
`trace` and `alert` are the entire saturated budget.

Type: FF DIN Condensed (display, fallback Archivo Narrow) / SF Pro Text (body) / Berkeley Mono
(data, fallback JetBrains Mono). Scale: Reading 148/132, Display L 40/44, Context 28/34, Body 17/24,
Caption 13/18, Data 12/16. Body + Caption scale with Dynamic Type; Reading + Context on a clamped curve.

## Design hard constraints
- No purple→blue gradients. No #F4F1EA cream + #D97757 terracotta. No glassmorphism-on-everything.
  No SaaS card kit (identical radii, same soft grey shadow).
- No SF Pro as the display face. Body may be SF. Display type is a deliberate licensed choice.
- Visual language derived from atmosphere and its instruments: barograph traces, isobars, wind roses,
  METAR notation, Beaufort scale, cloud atlas plates. Not Dribbble.
- Spend the boldness in one place. One screen carries the moment; everything else is quiet.
- Light/dark is not a toggle. Color state computed from real sun position + conditions.

## Motion rules
- Specify before building: curve, duration, properties, origin, trigger, interrupt behaviour.
- Everything interruptible. Springs, not eased durations, on anything touchable mid-flight.
- No non-user-triggered motion except one orchestrated moment per screen. Ambient weather is content.
- `accessibilityReduceMotion` honored everywhere; the reduced path is designed, not disabled.
- Budget: 120fps ProMotion / 8.3ms. Scale particles + shader complexity on `ProcessInfo.thermalState`.
  Cold launch to first meaningful paint < 1.2s. Instruments numbers, not vibes.

## Architecture
iOS: Swift 6 strict concurrency, iOS 18 min, `@Observable`, proper `@MainActor` isolation,
no `@unchecked Sendable`. Layers: VaneKit / VaneUI / app. Extensions share VaneKit.
Offline first — opens instantly with cached state, never a launch spinner.
No third-party dep without justification against a hand-rolled version.

Backend: FastAPI, Python 3.12, async throughout, Pydantic v2 as the shared contract. Postgres 16.
Redis forecast cache with source-matched TTLs. Open-Meteo primary behind a provider interface,
NWS for US alerts. Ingest worker backfills normals per 0.25° cell on first request for that cell —
never backfill the planet. Alembic, pytest + httpx, ruff, mypy strict, Docker Compose.
APNs token auth.

## Definition of done (per screen)
design-critique + review-animations + accessibility-review run and shown. Dynamic Type to a11y sizes
without breaking. VoiceOver order sensible, decorative motion hidden. Reduced-motion path designed.
Instruments shows no hitches, numbers reported. Copy through `design:ux-copy`. Tests for the logic.

## Working style
Blunt. Bad ideas get said before they get built. Non-obvious lines (Metal, spring configs, partition
strategy, concurrency annotations) get explained — what it does and why that value.
Small surgical diffs. Don't rebuild what works.
`DECISIONS.md` is append-only: every ADR and design choice, one line of rationale.
