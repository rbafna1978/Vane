# ADR-0005: Railway

**Status:** Proposed
**Date:** 2026-09-03

## Context
Four things to run: FastAPI web, arq worker, Postgres, Redis. One engineer. The database holds users'
personal weather history, which is irreplaceable — it cannot be re-derived, because the whole point
is that it accumulates from install date.

## Decision
Railway.

## Options Considered

### Option A: Fly.io
| Dimension | Assessment |
|---|---|
| Complexity | Higher — Dockerfile, fly.toml, per-service config |
| Cost | Lower at equivalent resources |
| Ops burden | Depends entirely on which Postgres |
| Global | Genuinely better if we ever need edge presence |

Fly's classic Postgres is not a managed service — it is an app running in your organization, and
backups, failover, and upgrades are yours. Fly Managed Postgres exists now and removes that
objection, but it is younger and pricier, which erodes the cost advantage that was the reason to
pick Fly.

### Option B: Railway
| Dimension | Assessment |
|---|---|
| Complexity | Low — services from the repo, managed PG and Redis as add-ons |
| Cost | Higher, on the order of tens of dollars a month at this scale |
| Ops burden | Backups are automatic and restorable |
| Global | Single region. Fine. |

## Trade-off Analysis
The deciding factor is not price and not latency, it is who is responsible for the backup that gets
restored at 3am. With one engineer and irreplaceable data, that should not be us. The cost delta is
small enough that trading it for a managed database with automatic backups is not a close call.

Single-region latency is acceptable: every expensive path is cached in Redis or precomputed, and the
client is offline-first, so a slow cold request degrades to stale-then-refresh rather than a spinner.

## Consequences
- Easier: deploys, backups, connection strings, and Postgres upgrades.
- Harder: multi-region later means a migration. Acceptable — that is a good problem.
- Locked in to: nothing serious. It is a Dockerfile, Postgres, and Redis.

## Action Items
1. [ ] Docker Compose locally mirrors Railway service topology (web, worker, postgres, redis)
2. [ ] Verify the automatic backup schedule and *perform one test restore* before launch. An
       untested backup is not a backup.
