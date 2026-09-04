# DECISIONS

Append-only. Every ADR and design choice, one line of rationale.

## 2026-09-03

- **Skills are repo-scoped, not global.** Copied the emilkowalski set + `frontend-design` into
  `.claude/skills/` rather than `~/.claude/skills/`. They were only present inside an unrelated
  project (`Interview_Helper/.agents/skills/`), so this session could not see them. Repo-local keeps
  them versioned with the project and mutates nothing global.
- **graphify runs as one repo-wide graph, not per-directory.** `tree-sitter-swift` and
  `tree_sitter_python` are both in the installed extractor, and `.metal` is a recognized extension —
  a single map covers the Xcode target and the FastAPI service. Revisit only if cross-language noise
  makes queries worse.

- **Visual direction: A, The Barograph.** Chosen over the Flight Strip (B) and the Cloud Atlas Plate (C).
  The differentiator is history; the barograph is the one instrument whose purpose is recording history
  continuously on a roll, so the visual language and the product mechanic are the same idea. Chart only —
  paper, grid, ink. Never the machine: no drum, no brass, no leather, no drop shadows.
- **Signature element: the unbroken trace.** Today is the right-hand end of one continuous roll that began
  at install. Dragging left is not navigation — the same paper keeps moving into the archive. The 11-year
  normal runs behind it dashed, so anomaly is a shape before it is a sentence.
- **Consequence: phase 5 redefined.** No shared-element transition between main screen and archive, because
  there is no jump between them. Phase 5 becomes scroll compression + the plate detail view.
- **Palette is a computed state, not a toggle.** paper/grid/ink/trace/wash/alert, with `wash` driven by real
  sun position from lat/lon and time. Grid moved off historical rust to green-grey `#AFBFA9` — rust on pale
  stock is the banned terracotta-on-cream pairing arrived at by an accurate route.
- **Type: FF DIN Condensed display / SF Pro Text body / Berkeley Mono data.** DIN 1451 is the lettering
  standard on European instrument faceplates, so the display face is the type that was on the machine.
  SF for body is deliberate: Dynamic Type and VoiceOver for free, and identity is carried elsewhere.
  Free fallbacks if licensing is declined: Archivo Narrow, JetBrains Mono.
- **Renamed WeatherMan -> Vane.** Project, target, scheme, `VaneApp`, and bundle id
  `com.rishitbafna.vane`. Done before the SPM packages exist, when it was still a `git mv` and a sed.
- **iOS deployment target 18.0, not the Xcode 26.5 template default.** The brief specifies iOS 18 as
  the floor; shipping at 26.5 would cut off most of the installed base for features we have not
  chosen yet.
- **Swift 6 language mode on from commit one.** `SWIFT_VERSION = 6.0` with
  `SWIFT_APPROACHABLE_CONCURRENCY` and `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. Turning strict
  concurrency on after code exists means fixing it everywhere at once; on from empty means never
  writing the violation.

## Phase 1 — backend skeleton

- **`/v1/snapshot` replaces `/conditions` + `/forecast` + `/context` on the main screen.** Three
  round trips on a cold cellular launch for one screen is the difference between feeling instant
  and feeling like a website.
- **One error envelope, including validation errors.** FastAPI's default 422 `{"detail": [...]}`
  is a second shape the client would need a second code path for; a handler maps it to
  `{"error": {code, message, retry_after}}` with a 400.
- **Redis fails open.** Cache read/write errors log and fall through to the provider. Redis is an
  optimisation, not a source of truth — an outage should cost speed, not uptime. Socket timeouts
  set to 2s so a hung Redis cannot hold requests open.
- **`cells` is the only table in phase 1.** Tables arrive with the code that uses them;
  `observations` and `daily_normals` land in phase 2 with the backfill that fills them. The row
  is real work, not scaffolding: it records which cells real users stand in, which is exactly
  the demand queue phase 2 consumes.
- **`context_state: "cold"` added to the contract.** ADR-0004 defined warm/warming only. Phase 1
  has neither — no normals and no worker — and reporting "warming" when nothing is warming would
  be a lie the client renders as a promise.
- **Provider protocol carries only `snapshot` and `forecast`.** ADR-0003 sketched a third method,
  `archive`; it lands in phase 2 with its caller rather than sitting unimplemented.
- **Migrations run on web boot.** With one engineer and one instance, a forgotten migration step
  is a likelier outage than two instances racing alembic. Revisit at more than one instance.
- **`DATABASE_URL` scheme is normalised in config, not in deploy settings.** Railway, Heroku and
  most managed Postgres inject `postgresql://`, which SQLAlchemy resolves to the sync psycopg
  driver and fails at startup with an error that never mentions the scheme. Rewriting it on load
  means the deploy cannot fail on a prefix nobody remembers.

## Deferrals (agreed 2026-09-03)

- **Deployment deferred to phase 7.** Phase 1's definition said "deployed and reachable"; it is not,
  deliberately. Nothing between here and the push loop needs a hosted backend — the simulator reaches
  `localhost:8000`, and a physical device reaches the Mac's LAN IP. APNs and TestFlight are the first
  things that genuinely cannot, and those are phase 7. Deploying now would bill for a database holding
  four test cells. The prep is committed and idle: `railway.json`, Dockerfile, and the `DATABASE_URL`
  scheme normalisation.
- **ADR-0005's backup restore test deferred with it.** It cannot be done before infrastructure exists.
  It remains a hard gate before real users, not a nice-to-have: the archive is the product and cannot
  be re-derived from anywhere.
