# ADR-0004: Cold cells return without context; backfill runs on arq

**Status:** Proposed
**Date:** 2026-09-03

## Context
Normals are backfilled 30 years per 0.25° cell on first request for that cell, then cached forever.
The brief settles the *what*. This ADR settles what happens during the ~5-15s that backfill takes,
because a user is holding a phone waiting.

Failure mode that matters: user opens app, backfill starts, the web process restarts mid-fetch, the
job is lost, and that cell stays contextless forever with no signal that anything is wrong.

## Decision
A request for a cold cell returns `200` immediately with `context: null` and a `context_state` of
`"warming"`. The client renders the temperature and the arc, and simply has no context line. Backfill
is enqueued on arq. Next open — or a push, once it lands — has the line.

## Options Considered

### Option A: Block the request until backfill completes
5-15s first request. Directly contradicts "never a spinner on launch." Rejected.

### Option B: FastAPI `BackgroundTasks`
Zero new dependencies, which is the attractive part. Rejected: the task dies with the process, has
no retry, and shares the event loop with request handling. Making it durable means a `cell_status`
table plus a sweeper that re-enqueues stale rows — which is a worse queue, hand-written.

### Option C: arq
Redis-backed, and Redis is already a dependency for the forecast cache, so this adds a library and
one worker process rather than new infrastructure. Durable, retries with backoff, survives deploys.

### Option D: Precompute popular cells ahead of demand
Rejected outright. This is backfilling the planet with extra steps, and the brief is right that the
on-demand trick is the whole point.

## Trade-off Analysis
B is the lazier-looking answer and it is a trap: the thing being deferred is not optional work, it is
the product's differentiator, and losing it silently is the worst outcome. Reaching for arq is the
decision ladder working correctly — a dependency that reuses existing infrastructure beats
hand-rolling durable retry.

## Consequences
- Easier: cold path is fast and honest. Backfill failures are visible and retried.
- Harder: a second process to run and deploy. Docker Compose gains a `worker` service.
- The client must have a designed state for "no context yet" — not an error, not a spinner, just a
  screen without the line. `design:ux-copy` decides whether it says anything at all. My instinct is
  it says nothing and the line simply appears later; a message about warming up is the app talking
  about itself.

## Action Items
1. [ ] `cells` table with `status` (cold / warming / warm) and `warmed_at`
2. [ ] Enqueue is idempotent on cell_id — concurrent first-requests must not queue duplicates
3. [ ] Backfill job is resumable: write observations in year batches, not one transaction
4. [ ] `/metrics` exposes cold-cell count and backfill failure count
