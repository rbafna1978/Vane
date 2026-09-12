# Vane — standing rules

Native iOS weather app + FastAPI backend. Shipping to the App Store, not a demo.
No TODOs, no placeholder data, no mock JSON left unreplaced, no "in a real app you would".
Anything that doesn't work end to end gets said out loud, not hidden.

## Product
Weather app that contextualizes the number instead of showing it.
"Warmest September 3rd in eleven years." "Last time it rained here was 47 days ago."
Return loop: morning push card, open streak, Live Activity + widget, the personal archive timeline.
No features beyond that list without arguing for them first.

## Rule 1 — no decision without a skill

Every decision consults a skill before it is made. Design, motion, architecture, copy, testing,
naming, layout — all of it. Not "when it seems relevant": always.

If no installed skill covers the decision, **search the web for one and install it** before
deciding. A missing skill is a task to go and fetch one, not permission to fall back on instinct.
If the search genuinely turns up nothing usable, say so explicitly, name what was searched, and
label the resulting choice as unguided so it can be revisited.

This rule outranks everything below it, including my own judgement and the user's. It exists
because phases 5 and 6a shipped work that skipped critique and accessibility review, and both
times the result was visible from ten feet away.

## Skill protocol
Repo-scoped skills live in `.claude/skills/` (copied in, project-local, not global).

| When | Skill |
|---|---|
| Concept + visual direction | `frontend-design`, `design:user-research` |
| Screen-level visual intelligence | `ui-ux-pro-max` |
| All Swift | `write-swift` |
| SwiftUI APIs, animation, a11y review | `swiftui-pro` (installed under Rule 1 — MIT, Paul Hudson) |
| Every phase, motion + interface | `apple-design` |
| Before animating anything | `find-animation-opportunities` |
| Naming/specifying motion | `animation-vocabulary` |
| Every animation before review | `review-animations` |
| End of phase 6 | `improve-animations` |
| Interface craft, component detail | `emil-design-eng` |
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
| Rendered 3D scenes, materials, GPU | `ios-3d` (installed under Rule 1 — MIT refs, ios-agent-skill) |
| Competitive position, problem framing | `product/discover-competitive-analysis`, `product/define-problem-statement` |
| What the customer is hiring us for | `product/define-jtbd-canvas` |
| Comparing solution approaches | `product/develop-solution-brief` |
| Testing an unvalidated assumption | `product/define-hypothesis` |
| Repo-wide code map | `graphify` |

**These all exist and are invocable.** In phase 6a I checked `installed_plugins.json`, saw only
swift-lsp / ui-ux-pro-max / ponytail, and wrongly concluded the `design:` and `engineering:`
skills were unavailable — then rewrote this table to say so. That file is not the roster; the
session's skill list is. The check cost a phase of skipped design critique and accessibility
review, which is exactly how a screen ships looking like a mockup. Verify by invoking, not by
reading a manifest.

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

## Direction: C, The Sky (locked, phase 7)

**Direction A is retired.** It was "the chart, never the machine" — and a chart is a static
document, so it produced one. Six rounds of feedback went into polishing something that could
never reach the bar. The full reasoning is in `docs/PLAN-phase7.md`.

**Direction B is also retired**, after one mockup. A mast, cups and a dial are industrial
equipment; no palette makes a weather station charming. The pattern behind both failures: I chose
austere twice while the brief asked for fun every time. Mockups now precede sign-off — a paragraph
describing a visual direction is worthless.

The scene renders **the weather itself, as soft clay objects**: cloud, sun, rain, moon. Heavy,
lumpy, characterful, with real material and cast shadow. Being adjacent to the reference is the
target, not the failure — the differentiation is the meaning layer, not the art style.

**What is ours: the ground is the real sky**, computed from the sun's true position. Competitors
are always white. Vane is never the same colour twice.

Composition, from the reference: one object scene, one enormous figure, one line of meaning, and a
technical annotation overlay on demand — callouts with leader lines pointing *into* the scene. Our
overlay annotates with **history**, which is the thing no competitor does.

Rendering is **Blender → USDZ → RealityKit**, SwiftUI composited on top — the reference app's own
architecture (they use Blender + SceneKit) on the current renderer, since SceneKit is
soft-deprecated. See ADR-0009. **The art is authored by the user in Blender; I cannot author 3D.**
A scene contract — entity names, variable ranges, units — is written before any art exists.

## Interaction model: one scene, one sheet

There are no pages. The scene is always present; everything else is a sheet pulled up over it to
whatever height the user wants, and dropped when they are done. Hour by hour, the week, thirty
years and the record are *sections of one continuous sheet*, never destinations. Detail annotates
the scene in place — the composition never moves. The scene recedes and dims rather than leaving,
so there is nothing to navigate back to.

1:1 tracking with nothing eased on the drag path. Momentum projected to choose the detent.
Interruptible mid-flight from the presentation value. Rubber-band at both ends. Springs, never
durations. **The sheet is an accessibility-adjustable control whose increments are the detents**,
so VoiceOver moves it the way a drag does; Reduce Motion crossfades rather than travels.

Type: **Big Shoulders** (display) — variable `wght` 100–900 and `opsz` 10–72. Chosen by setting
54° at 180pt against five alternatives and looking, not from a specimen sheet; Archivo Narrow, the
incumbent, has no mass at all beside it and would disappear against a rendered scene. The
optical-size axis is the rare property here: one family cut correctly for both 180pt and 12pt.
SF Pro Text (body, for Dynamic Type and VoiceOver) / JetBrains Mono (data).

## Design hard constraints
- **No line charts. Anywhere.** No traces, curves, sparklines or scatter. A line asks the reader
  to decode an axis, a scale and a slope before it says anything, and every one built in phases
  3–6 made its screen worse. This kills the barograph roll, the hourly curve and the pressure
  trace.

  **Bars are allowed**, and only because they are read by *length*, which needs no decoding — a
  taller bar is more, and that is the entire instruction manual. Use them where the point is a
  comparison between discrete things: this date across thirty years, one day against the next.
  Never for a continuous quantity over time; that is a line chart with the line hidden.

  What replaces the rest is the direction itself: **the instrument is the reading.** The aneroid
  dial *is* the pressure — you do not also need a pressure line. The column height *is* the
  temperature. The vane *is* the bearing. The cups' speed *is* the wind strength. Where an
  instrument cannot carry it, use a bar, a number with a plain label, or a sentence.
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
