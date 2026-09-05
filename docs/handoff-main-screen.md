# Handoff — main screen

The only screen most people will ever see. It answers one question ("what is it like out?") and
then earns its place by answering a second nobody asked ("is that unusual here?").

## Layout

Single column, 24pt horizontal padding, safe-area top and bottom. Top-aligned, no centring:
this is a chart, and a chart starts at the top of the paper.

```
┌─────────────────────────────────────┐
│ OAKLAND, CA        KOAK 051756Z  ⌄  │  station line, Data 12, tracking 1.4
│                                     │  ── 32
│ 18°                                 │  Reading 148, clamped Dynamic Type
│                                     │  ── 8
│ 8 straight days cooler than         │  Context 28. The reason the app exists.
│ normal.                             │
│                                     │  ── 28
│ ┌─────────────────────────────────┐ │
│ │  ·  ·  ·  ·  ·  ·  ·  ·  ·  ·   │ │  BarographTrace, height 200
│ │ ╌╌╌╌╌╌╌╌ normal band ╌╌╌╌╌╌╌╌╌  │ │  solid to now, dashed ahead, pen tip
│ │ ────────────●╌ ╌ ╌ ╌ ╌ ╌ ╌ ╌    │ │
│ │ 00   03   06   09   12   15  21 │ │
│ └─────────────────────────────────┘ │
│                                     │  ── 24
│ ↑ 06:42   ↓ 19:33      280° 12KT    │  Data 12
│                                     │  ── 20
│ ○ ○ ● ○ ○ ○ ○                       │  streak, 5pt dots, 8pt gap
└─────────────────────────────────────┘
```

Vertical rhythm is 4pt-based: 8 / 20 / 24 / 28 / 32. No value outside that set.

## Tokens

| Token | Usage |
|---|---|
| `palette.paper` | screen background, pen-tip halo |
| `palette.ink` | reading, context, station line, footer |
| `palette.grid` | chart ruling, normal band fill and dashes, unfilled streak dots |
| `palette.trace` | the trace, the pen tip, filled streak dot |
| `palette.alert` | alerts only. Absent on an ordinary day. |
| `.vaneReading` / `.vaneContext` / `.vaneData` | 148 / 28 / 12 |

All resolved from `SkyState.now(latitude:longitude:date:cloudCover:)`. Nothing hardcodes a colour.

## States

| State | What renders | Why |
|---|---|---|
| **Cached** (default) | Everything, from disk, instantly | Offline-first. There is never a launch spinner. |
| **Refreshing** | Cached content unchanged; no spinner, no skeleton | A refresh is not an event the user needs told about. |
| **Cold / warming cell** | Everything except the context line | The line is absent, not replaced by a placeholder. `context_state` is `cold` or `warming`. |
| **Warm, nothing interesting** | Everything except the context line | Identical to above by design. An ordinary day says nothing rather than filler. |
| **No cache, no network** | Station line + designed empty state | Copy through `design:ux-copy`. Says what happened and what to do. |
| **Location denied** | Designed state with a single action | Never a dead end. |
| **Low-confidence context** | Context line at 62% opacity | Short record still shows, but does not claim thirty years of authority. |

The three "no context line" cases render identically on purpose. The user should never learn to
read the *absence* of a sentence as an error.

## Motion

One orchestrated moment, and it is the arrival of the context line.

| Element | Trigger | Motion | Duration | Curve |
|---|---|---|---|---|
| Context line | The sentence *changes or first arrives* | rise 6pt + fade | 280ms | `VaneMotion.entrance` (zero-bounce spring) |
| Reading | Value changes | `.numericText` roll | 280ms | `VaneMotion.figure` |
| Palette | Real time passing | crossfade | 1200ms | `VaneMotion.sky` |

**It does not replay on every open.** Rendering unchanged cached content animates nothing — an
intro that fires several times a day stops being a moment and becomes a delay.

The trace does **not** draw itself. `find-animation-opportunities` rejects animated line drawing
on data the user is reading, at this frequency. That verdict stands.

Reduced motion: rise becomes a fade, roll becomes a crossfade, palette crossfade shortens. All
designed paths, none disabled.

## Accessibility

VoiceOver order, which is also the reading order:

1. Location — "Oakland, California"
2. Reading — "18 degrees"
3. Context — the sentence, verbatim
4. Chart — one summary sentence: now / high / low / inside or outside the usual range
5. Footer — "Sunrise 6:42 AM. Sunset 7:33 PM. Wind 12 knots from 280 degrees."
6. Streak — "Opened 3 days in a row"

The station code, the grid, the normal-band fill and the pen halo are `accessibilityHidden` —
they are paper, not content.

Dynamic Type: body and caption scale to AX5 unrestricted. Reading and context scale on
`VaneType`'s clamped curve (ceilings 1.30 and 1.55). At AX5 the reading may wrap its degree
symbol; that is accepted. Nothing may clip or truncate.

Contrast is guaranteed at ≥4.5:1 at every minute by `Palette.guaranteeingContrast`.

## Edge cases

- **Temperature ≥ 3 digits or ≤ -10**: the reading is `minimumScaleFactor(0.7)`, single line.
- **Long context sentence**: wraps to a maximum of three lines, never truncates. The sentence is
  the product; an ellipsis in it is a bug.
- **Missing normal band** (cold cell): the chart draws grid + trace only. No empty band outline.
- **Arc shorter than 24h** (near local midnight): the trace draws what exists; the axis stays 0–24.
- **Location changes while open**: refetch, and animate the context line as an arrival.
