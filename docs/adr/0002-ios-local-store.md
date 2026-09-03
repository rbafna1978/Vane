# ADR-0002: GRDB for the local archive, server as source of truth

**Status:** Proposed
**Date:** 2026-09-03

## Context
The archive is one entry per day since install, and it is the return loop — "the thing they show
friends." Its defining interaction is scroll compression: dragging left moves through days, then
weeks, then months, with values aggregating as the scale changes. That is a GROUP BY over a date
range, run continuously during a gesture at 120fps.

Second force: the app is Swift 6 with strict concurrency and no `@unchecked Sendable` escape hatches.

## Decision
GRDB for the local store. The server (`/v1/archive`) is the source of truth; the local database is a
durable cache, not the master copy.

## Options Considered

### Option A: SwiftData
| Dimension | Assessment |
|---|---|
| Complexity | Low to start, high at the edges |
| Cost | Free, first-party |
| Scalability | Aggregates are the weak spot |
| Team familiarity | Medium |

**Pros:** first-party, `@Query` integrates directly with SwiftUI, CloudKit sync is close to free.
**Cons:** `PersistentModel` is not `Sendable`, so crossing actor boundaries means `ModelActor` and
passing `PersistentIdentifier`s — friction on every background write, exactly where strict
concurrency bites. Aggregate queries have no real expression; compression would mean fetching rows
and reducing in Swift, during a gesture. Migration story is still immature for a store we must never
corrupt.

### Option B: GRDB
| Dimension | Assessment |
|---|---|
| Complexity | Low — it is SQLite with good manners |
| Cost | Free, MIT, one dependency |
| Scalability | Excellent for this shape |
| Team familiarity | Medium |

**Pros:** `DatabaseQueue`/`DatabasePool` are `Sendable` and records are value types, so Swift 6
isolation is a non-event. Compression is one SQL statement. `ValueObservation` gives reactive
SwiftUI reads without ceding query control. Migrations are explicit and testable.
**Cons:** third-party. No free CloudKit sync.

## Trade-off Analysis
The CloudKit argument is the only real point for SwiftData, and it dissolves once the server holds
the archive: cross-device continuity comes from `/v1/archive` keyed on the device identity, not from
CloudKit. That removes SwiftData's advantage and leaves its two disadvantages — aggregate queries and
Swift 6 friction — landing precisely on this app's hottest path and hardest constraint.

The dependency is justified against a hand-rolled version: hand-rolling means raw SQLite C interop,
our own migration runner, and our own observation mechanism. That is more code than the dependency.

## Consequences
- Easier: scroll compression is SQL. Background writes need no ceremony. Archive survives reinstall,
  because the server has it.
- Harder: one third-party dependency to keep current. No offline-created archive entries without a
  reconciliation path (entries originate server-side, so this is by design).
- Revisit if: Apple ships `Sendable` models and real aggregate support in SwiftData.

## Action Items
1. [ ] GRDB via SPM, pinned to a major version
2. [ ] Schema mirrors `/v1/archive` payload; a `synced_at` column drives reconciliation
3. [ ] Compression query written and benchmarked before the archive screen is built
