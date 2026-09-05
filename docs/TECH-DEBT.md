# Tech debt ledger — after phase 4

Scored `(Impact + Risk) x (6 - Effort)`, each 1-5. This audit was due at the end of phase 3 and
was skipped; it covers phases 1-4.

| # | Item | I | R | E | Score | When |
|---|---|---|---|---|---|---|
| 1 | Backend URL is a hardcoded `localhost` constant | 3 | 4 | 1 | **35** | now |
| 2 | No CI — nothing runs the 99 tests but me | 4 | 4 | 2 | **32** | now |
| 3 | `WeatherModel` has no tests: cache-first, error fallback, screen states | 3 | 4 | 2 | **28** | now |
| 4 | `docs/api-contract.md` has drifted from the built API | 2 | 3 | 1 | **25** | now |
| 5 | No rate limiting on public endpoints | 1 | 5 | 2 | 24 | before public |
| 6 | No error monitoring or structured request logging in production | 2 | 4 | 2 | 24 | phase 7 |
| 7 | No device auth; every route is public | 2 | 4 | 3 | 18 | phase 7 |
| 8 | Migrations run on web boot | 1 | 3 | 2 | 16 | >1 instance |
| 9 | Streak is local `UserDefaults`, lost on reinstall | 2 | 3 | 3 | 15 | phase 7 |
| 10 | The design-system `Catalog` compiles into the shipped app | 1 | 2 | 1 | 15 | phase 8 |
| 11 | No single-flight lock on cache expiry (`ponytail:` marked) | 1 | 2 | 2 | 12 | if metrics move |

## The four worth doing now

**1. Hardcoded base URL** is the highest-scoring item and the cheapest. A TestFlight build pointing
at `localhost:8000` is not a degraded app, it is a dead one, and nothing in the current setup stops
that shipping.

**2. No CI** is the item that keeps every other item honest. Three suites across two languages,
99 tests, ruff and mypy — and the only thing running them is me remembering to.

**3. `WeatherModel` is untested** and it is the most breakable code in the app: cache-first init,
the decision to stay silent when a refresh fails, and the four screen states. Every bug found by
eye this phase lived within one file of it.

**4. Contract doc drift** — `docs/api-contract.md` still describes `normal` as a list of points and
has no `utc_offset_seconds`. A spec that lies is worse than no spec.

## Deliberately not debt

Deployment (phase 7), GRDB and the archive (phase 5), the widget (phase 6), and Instruments hitch
numbers (need a physical device) are all *sequenced*, not deferred maintenance. They are on the
plan and nothing is decaying while they wait.
