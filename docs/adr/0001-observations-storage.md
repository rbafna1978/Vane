# ADR-0001: Observations storage — no partitioning, no TimescaleDB

**Status:** Proposed
**Date:** 2026-09-03
**Deciders:** Rishit

## Context
`observations` holds daily historical values per 0.25° grid cell, backfilled 30 years on first
request for that cell. The brief asks us to pick between TimescaleDB and native Postgres 16
partitioning. Both answers assume a row count we do not have.

Volume: 30 years x 365 days = ~11,000 rows per cell. A cell is ~25km square. Realistic first-year
usage for a solo-shipped app is low thousands of distinct cells. 3,000 cells = 33M rows.
10,000 cells = 110M rows. Rows are narrow (cell_id, date, tmax, tmin, precip, and a few more).

Access patterns, all of them:
- percentile rank of today's value for this cell + day-of-year across all years
- streak state: consecutive days above/below a threshold, recent window
- "last time it rained here": most recent date where precip > 0
- almanac: all years for one cell + one date

Every one is `WHERE cell_id = ? AND ...`. cell_id is the natural leading key, not time.

## Decision
One unpartitioned table. `PRIMARY KEY (cell_id, date)` and a partial index for the precip lookup.
No TimescaleDB, no declarative partitioning.

## Options Considered

### Option A: TimescaleDB hypertable
| Dimension | Assessment |
|---|---|
| Complexity | Medium — extension, chunk tuning, its own upgrade path |
| Cost | Constrains hosting: managed Postgres on Railway and Fly MPG do not ship the extension |
| Scalability | Excellent, at volumes we are ~100x away from |
| Team familiarity | Low, and there is one engineer |

**Pros:** compression is genuinely good; continuous aggregates would suit normals.
**Cons:** forces self-managed Postgres, which puts backup of irreplaceable user history on a solo
dev. Buys throughput we do not need. Time-ordered chunking is the wrong axis — our queries are
cell-ordered, so most chunks are scanned or excluded by the index anyway, not by chunk pruning.

### Option B: Native declarative partitioning by date range
| Dimension | Assessment |
|---|---|
| Complexity | Medium — partition maintenance job, Alembic gets meaningfully worse |
| Cost | Free |
| Scalability | Good |
| Team familiarity | Medium |

**Pros:** no extension, portable.
**Cons:** partitions by date, but no query filters primarily by date — every cell-scoped query hits
every partition. It is the cost of partitioning with none of the pruning benefit. Alembic
autogenerate does not understand partitioned tables and will need hand-written migrations forever.

### Option C: One table, right indexes
| Dimension | Assessment |
|---|---|
| Complexity | Low |
| Cost | Free |
| Scalability | Fine to ~200M rows on modest hardware |
| Team familiarity | High |

**Pros:** Alembic autogenerate works. Any managed Postgres hosts it. Zero maintenance job.
**Cons:** we will have to revisit if the app succeeds beyond a certain point.

## Trade-off Analysis
A and B both pay real, permanent operational cost for a scaling problem that starts at roughly 100x
current projected volume, and both partition on an axis our queries do not use. The interesting
constraint is not row count, it is that TimescaleDB removes managed Postgres from the table — and a
solo engineer holding users' personal history should not be running their own database.

## Consequences
- Easier: migrations, hosting choice, local Docker Compose parity, backup story.
- Harder: a future migration to partitioning if volume arrives. That migration is well-trodden
  (`CREATE TABLE ... PARTITION BY`, copy, swap) and is cheaper than carrying the complexity now.
- Revisit when: `observations` exceeds 200M rows, OR p95 on `/v1/context` exceeds 200ms, OR
  `pg_stat_statements` shows sequential scans on the cell-scoped queries. Whichever comes first.

## Action Items
1. [ ] `observations` with `PRIMARY KEY (cell_id, date)`
2. [ ] Partial index `(cell_id, date DESC) WHERE precip_mm > 0` for the "last rain" query
3. [ ] Add the row-count tripwire to `/metrics` so we notice rather than discover
