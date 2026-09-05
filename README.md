# Vane

A weather app that tells you what the number *means* for where you live.

Every weather app shows you 21°. Vane tells you it is the warmest September 5th in thirty
years, or that it has been forty-seven days since it last rained here, or that this is the
eighth straight day cooler than normal. That requires real history per location — normals,
ranks, streaks — which is why there is a real backend behind a native iOS app.

Sentences the engine produced today, from thirty years of record, verified against the raw data:

```
Sydney     Warmest September 5th in 30 years.        (31.8°C vs a previous high of 26.5°C)
Oakland    8 straight days cooler than normal.
Phoenix    5 straight days cooler than normal.
London     —                                          (an ordinary day gets no line)
```

That last row is deliberate. When nothing true is interesting, Vane says nothing. Filler
restating the temperature as a fact is what this app exists to avoid.

## Design direction — The Barograph

A barograph is a clock-driven drum that pulls chart paper past an ink pen, tracing pressure as
one unbroken line. It is the only common instrument whose *output is a history*, which is
exactly what this app is.

The interface is that chart: pale eau-de-nil stock, a printed hairline grid, one aniline-violet
pen trace. Today is the right-hand end of a roll that started the day you installed it. Drag
left and you are in your own archive, because it is the same paper. Behind the trace runs the
thirty-year normal, dashed, so *unusual* is a shape before it is a sentence.

The chart, never the machine — no drum, no brass, no leather, no drop shadows.

| | Day | Night |
|---|---|---|
| paper | `#DFE7DC` | `#12171A` |
| grid | `#AFBFA9` | `#263029` |
| ink | `#1B2021` | `#DCE6DE` |
| trace | `#3A2E6B` | `#8B7BD4` |
| alert | `#B8442E` | `#E06A4F` |

`trace` and `alert` are the entire saturated budget. Light and dark are not a toggle — the
palette is computed from real sun position and conditions.

Type: Archivo Narrow (display) / SF Pro Text (body) / JetBrains Mono (data). Both custom faces
are OFL and vendored with their licences.

Contrast is guaranteed rather than hoped for: ink is pushed away from paper until it clears WCAG
AA, so no time of day can produce an unreadable screen. Measured floor is 4.50:1 at every minute;
AAA holds for 92% of the day.

## Status

| Phase | | |
|---|---|---|
| 1 | Backend skeleton — `/v1/snapshot`, `/v1/forecast`, Docker, migrations | done |
| 2 | Context engine — normals backfill, ranks, streaks, `/v1/context` | done |
| 3 | Design system in code — tokens, type scale, sun engine, motion primitives | done |
| 4 | Main screen | done |
| 5 | Detail + archive | next |
| 6 | Widget + Live Activity | |
| 7 | Push loop + deploy | |
| 8 | Polish + App Store submission | |

Deployment is deliberately deferred to phase 7 — nothing before the push loop needs a hosted
backend, and the simulator reaches localhost.

## Layout

```
Vane/            iOS app target (Swift 6, iOS 18 minimum)
Packages/VaneKit models, sun-position engine. nonisolated — the caller decides where work runs.
Packages/VaneUI  tokens, type scale, motion primitives, the design-system catalog.
backend/         FastAPI + Postgres 16 + Redis + arq worker
docs/adr/        architecture decision records
DECISIONS.md     append-only log of every decision and its one-line reason
CLAUDE.md        standing rules for the project
```

## Run the backend

```bash
cd backend && docker compose up --build
curl "localhost:8000/v1/snapshot?lat=37.8044&lon=-122.2712"
```

The first request for a location returns in under a second with no context line and queues a
thirty-year backfill. The next one has a sentence. See [backend/README.md](backend/README.md).

## Run the app

```bash
open Vane.xcodeproj
```

Requires Xcode 26 and an iOS 18 simulator.

## How this is built

Decisions are written down before they are implemented, in [docs/adr](docs/adr), and logged in
[DECISIONS.md](DECISIONS.md) as they are made. Where a decision departs from the plan — and
several do — the reason is in the log rather than in someone's memory.
