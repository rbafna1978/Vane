# Handoff — detail and archive

## 1. Detail — the extended forecast

A 7-day list is what every weather app has. What makes this one is the same thing that makes the
main screen: **every day is shown against its own 30-year normal for that calendar date.** The
forecast number alone is table stakes; the deviation is the product.

```
┌─────────────────────────────────────┐
│ ← OAKLAND, CA                       │  Data 12
│                                     │
│ NEXT 10 DAYS                        │  Data 12, tracking 1.4
│                                     │
│ FRI 6   ░░░░▓▓▓▓▓▓░░░░   14°  22°   │  each row: a range bar
│ SAT 7   ░░▓▓▓▓▓▓░░░░░░   12°  20°   │  positioned against the
│ SUN 8   ░░░░░▓▓▓▓▓▓▓░░   15°  25°   │  same shared temperature
│ MON 9  ·░░░░░░▓▓▓▓▓▓░░   16°  26°   │  axis, so a warm day sits
│ TUE 10 ··░░░▓▓▓░░░░░░░   11°  18°   │  visibly right of a cool one
│                                     │
│         ↑ normal range for the date │
└─────────────────────────────────────┘
```

**The row is the comparison.** A light track shows that date's 30-year normal range; the solid
bar shows the forecast high–low. All rows share one temperature axis, so "warmer than usual"
is the bar sitting right of its track — legible without reading a number, the same way the main
screen's trace leaving the band is.

- Precipitation probability renders as leading dots (`·` per 25%), not a percentage, so the
  column scans. Amount is in the VoiceOver label only.
- Day the sun crosses: `TODAY` for row 0, weekday + date after.
- Rows are 44pt minimum, tappable target even before they are tappable.

**Reached by tapping the chart on the main screen** — the chart is the day, so the day's detail
belongs behind it. No new navigation chrome.

## 2. Archive — the roll

The signature of the whole design: **the trace never breaks.** Today is the right-hand end of one
continuous roll that began at install. Dragging left moves along the same paper.

There is **no shared-element transition** because there is no jump — the archive is the main
screen's chart continuing leftward, on the same sheet. (This was recorded at GATE 2 and it holds:
`matchedGeometryEffect` here would be animating a seam that does not exist.)

```
        ← drag                            today ●
 ░░░░▓▓░░▓▓▓▓░░░░░░▓▓░░░░▓▓▓▓▓▓░░░░░░░░░░░░░░░│
 └── weeks ──┘└──── days ────┘└─── hours ─────┘
      compressed        one mark per day    today's trace
```

**Compression by span, not by zoom.** Under ~14 days the roll draws one point per day. Beyond
that it aggregates to weekly means, then monthly — computed in SQL, not in Swift, because it runs
during a gesture (ADR-0002 exists for exactly this).

- The normal band travels with the roll: each day compared to *its* date's normal, so a warm
  January and a warm July both read as above the band.
- Empty at install: the roll starts today. Copy states the record begins now rather than
  apologising for being empty.

## Data

`archive_entries` is written locally, one row per day, whenever a snapshot for that day is seen.

**Deviation from ADR-0002, stated:** that ADR called the server the source of truth and the local
store a cache. Device identity and `/v1/archive` land with the push loop in phase 7, so until
then the archive is *created* locally — we are the only party that knows the app was opened and
what it was like. Phase 7 adds upload so it survives reinstall. This is a sequencing refinement,
not a reversal: the local store is still the thing rendered, and the server still becomes
authoritative for continuity across devices.

## Motion

| Element | Trigger | Motion | Curve |
|---|---|---|---|
| Roll | Drag | 1:1 tracking, no animation on the tracking path | — |
| Roll | Release | Momentum with velocity handoff, rubber-band at the ends | `interpolatingSpring` |
| Detail | Tap chart | Push, standard navigation | system |
| Rows | Appear | **None.** Data being read; `find-animation-opportunities` rejects staggered entry here | — |

Reduced motion: release settles with `easeOut`, no overshoot.

## Accessibility

- Detail rows: one element each — "Friday the 6th. High 22, low 14. Four degrees above the usual
  high for this date. 40 percent chance of rain, 2 millimetres."
- The archive roll is one element with a summary and an adjustable action (swipe up/down moves by
  a day), because a drag gesture is not operable by VoiceOver.
- Range bars are `accessibilityHidden`; the numbers and the comparison carry it.
