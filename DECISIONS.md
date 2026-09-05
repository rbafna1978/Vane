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

## Phase 2 — context engine

- **`normal` is a band, not an hourly curve.** Contract changed from `list[NormalPoint]` to
  `NormalBand {tmax_c, tmin_c, years}`. We hold daily history, so an hourly normal would have to be
  invented from a diurnal shape — a fabricated curve behind a real trace is the quiet dishonesty this
  app exists against. Two dashed rules also read more like printed chart paper than a second wiggle.
- **Normals keyed on (month, day), not day-of-year.** Day-of-year shifts by one after February 29th,
  so day 247 is September 3rd in some years and September 4th in others. Keying on DOY would silently
  average two different dates together.
- **Rank today's forecast high, never the current reading.** Found by looking at real output, not by
  a test: comparing the 12:15 temperature against 30 years of daily maxima produced "Coolest September
  4th in 30 years" when today was in fact the fifth-coolest. It would have published a false
  superlative every morning before the day warmed up. `SnapshotData` now carries `today_tmax_c`.
- **Ties defeat superlatives.** If a past year matched today exactly, today is not uniquely warmest
  and must not say it is. Rank counts `>=`, not `>`.
- **Streaks break on gaps in the record.** Reanalysis has holes; counting across one would claim
  consecutive days we have no record of.
- **Streaks compare against each day's own normal, not a fixed threshold**, so the sentence means the
  same thing in Reykjavik and Phoenix.
- **Under 10 years of record, no superlative claims at all.** Short records still get dry-spell facts,
  which need no baseline. A superlative from four years is a lie with a number in it.
- **Returning no context is a feature.** London on an ordinary day gets no line. Filler restating the
  temperature as a fact is precisely what this app exists to avoid.
- **Insert chunked at 32,000/6 rows.** Postgres binds at most 32,767 parameters per statement; a
  30-year backfill is ~67,000. ADR-0004 called for year batches and I overrode it because the *fetch*
  is one request — the *insert* needs batching for an unrelated reason. One commit for the whole cell,
  so the engine never ranks against a half-written record.
- **Worker concurrency 1, measured not guessed.** Four parallel archive fetches trip Open-Meteo's
  minutely limit and burn arq retries on a rate limit we inflicted on ourselves. A backfill runs once
  per cell and nobody waits on it.
- **A failed backfill resets the cell to cold.** Otherwise arq exhausts its retries, the cell stays
  `warming` forever, and the differentiator is lost silently — the exact failure ADR-0004 exists to
  prevent.

## Phase 3 — design system in code

- **Archivo Narrow, not FF DIN Condensed.** Your call on cost. Both are OFL and vendored with their
  licences; JetBrains Mono carries the data. Registration is explicit at launch because SPM resource
  bundles are not scanned the way an app's Info.plist is — and a font that fails to register falls
  back to the system face silently, which would ship a different app than the one designed. Three
  tests assert the faces actually resolve.
- **VaneKit is NOT main-actor-by-default; VaneUI is.** `write-swift` is explicit that a library
  should ship `nonisolated` APIs and let the caller decide where work runs. Forcing MainActor down
  into VaneKit would drag the widget extension and the sun engine onto the main actor for nothing.
  Pure value types inside VaneUI (`RGB`, `Palette`, `SkyState`, `VaneFont`) are marked `nonisolated`
  for the same reason — the widget computes a palette without touching the main actor.
- **Sun position is the NOAA algorithm, validated against Open-Meteo's published sunrise and sunset.**
  Independent source, so agreement is evidence rather than self-consistency. Also pinned: polar night,
  midnight sun, zenith over the Tropic of Cancer at the solstice, azimuth in both hemispheres.
- **Bug found by dumping the curve, not by a test: azimuth ran backwards after noon.**
  `truncatingRemainder` keeps the dividend's sign, so a western longitude left the hour angle at
  -302 degrees instead of +58. Elevation survived it (cosine is periodic) but the azimuth branch
  tests the *sign* to tell morning from afternoon, so the sun set in the east. The wash is driven by
  azimuth, so the interface would have been lit from the wrong side of the sky.
- **Colour is mixed in linear light, not in sRGB.** A straight average of gamma-encoded values lands
  darker than the light physically would — the grey band halfway through every naive gradient.
- **Contrast is guaranteed by construction, not by hoping.** Paper travels light-to-dark across dusk
  while ink travels dark-to-light; unguarded they pass each other and contrast collapses to 1.48:1 —
  the screen becomes unreadable at exactly the hour someone is outside looking at the sky. `ink` is
  now pushed away from `paper` until it clears WCAG AA (4.5:1). Measured floor is exactly 4.50:1 at
  every minute of the day; AAA holds for 92.2%.
- **The lightness ramp spans exactly civil twilight (+6 to -6 degrees).** First attempt used a narrow
  band to dodge the contrast problem, which made light/dark read as the toggle the brief forbids.
  Once contrast was guaranteed independently, the gentle ramp cost 2 points of AAA and nothing else.
- **The catalog shows the whole day as a strip, not one instant behind a slider.** A ramp has to be
  judged as a ramp; seeing dawn, noon, dusk and midnight at once is what caught the ramp being too
  steep in the first place.
- **Three motion primitives, chosen by `find-animation-opportunities`, which vetoed the obvious one.**
  See the phase 3 note in the README.

## review-animations findings (phase 3) — all fixed

- **`PaperScroll` release animation was dead code.** `settled` was assigned once outside
  `withAnimation` and again inside it, so the block saw no change and the spring never ran —
  every release teleported. Missed because the primitive has no call site until phase 5. Now one
  assignment, inside the block.
- **`PaperScroll` now carries real velocity.** `withAnimation(.spring)` starts from rest;
  `predictedEndTranslation` projects a destination, not momentum. A flick and a slow drag settled
  identically. Now `interpolatingSpring(initialVelocity:)` derived from the gap between predicted
  and actual translation, clamped to ±12.
- **`RollingNumber`'s reduced-motion path removed motion entirely.** `.contentTransition(.identity)`
  hard-swaps the digits. Reduced motion means gentler, never absent — now `.opacity`.
- **The catalog animated a gesture-driven value.** `.animation(VaneMotion.sky, value: palette)` at
  1.2s made the colour trail the scrubbing finger by over a second. Removed; `VaneMotion.sky` is
  documented as ambient-only. Same error I had correctly avoided on `PaperScroll`'s tracking path.
- **`entrance` cut from 340ms to 280ms**, inside the sub-300ms UI budget.
- **Two comments described curves the code did not use.** `.smooth` is a zero-bounce spring, not an
  ease-out. Wrong comments in a design system propagate to every call site.

## Phase 4 — main screen (IN PROGRESS, paused 2026-09-05)

Working end to end: real location via CoreLocation, real backend data, real context sentence,
trace with pen tip, sunrise/sunset, wind, streak dots.

- **Offline-first is real, not aspirational.** `SnapshotStore` loads synchronously in
  `WeatherModel.init`, so the first frame the screen ever draws already has content. There is no
  state in the model that means "waiting" while a cache exists, which is why there can be no
  launch spinner.
- **A failed refresh with content on screen is silent.** The user is looking at the last known
  reading, which is what they wanted. It is only an error when there is nothing to show.
- **The server now sends `utc_offset_seconds`.** Sunrise must render in the time of the place
  being looked at, not the phone's. Inferring the offset from a midnight boundary breaks on DST
  days, so the server sends what it already knows. Field is optional client-side so a cache
  written by an older build still decodes — a schema addition must never blank a working app.
- **Bug: sunset rendered as "07:33".** `.hour(.twoDigits(amPM: .omitted))` is a 12-hour clock
  with the disambiguating half removed. On an instrument that is a wrong number, not a
  formatting preference. Now explicit 24-hour in the location's zone.
- **Bug: Dynamic Type did nothing at all.** Every font used `fixedSize:` or `Font.system(size:)`,
  both of which opt out of scaling — while `VaneType.reading(for:)` sat fully unit-tested and
  never called by anything. Tests giving false confidence about code with no callers.
- **Fixing that exposed three layout failures at AX5**, all now handled: the station line
  truncated (METAR code is dropped at accessibility sizes so the place name keeps the width);
  the chart's hour labels collided into pulp (thinned to six-hourly, size capped — the axis is a
  fixed width so its labels cannot scale freely); the footer truncated to "↑… ↓ 1… 285…"
  (stacks vertically instead).
- **Content overflowed the safe area at AX5.** A `ZStack` centres content taller than itself,
  which pushed the station line under the status bar. Now a `ScrollView` with
  `.scrollBounceBehavior(.basedOnSize)` — scrolls only when it must, still a fixed sheet at
  normal sizes.
- **Streak is local (UserDefaults), not server-backed.** `/v1/archive/open` lands with the push
  loop in phase 7.

### Still owed before phase 4 can be called done
- `design:design-critique` and `design:accessibility-review` on the screen
- `engineering:code-review` on the phase 4 diff
- `engineering:tech-debt` — due at the end of phase 3 and skipped; covers phases 1-4
- Instruments numbers. `xctrace` was killed against the simulator, and simulator hitch numbers
  would be meaningless anyway: no ProMotion, no real GPU, no thermal behaviour. Launch-to-first-
  paint is now instrumented via `LaunchMetrics` (measured from `kinfo_proc` process start, so it
  includes dyld). Real 120fps hitch numbers need a physical device.

## Phase 4 reviews — findings and fixes

**design:design-critique.** The composition was unresolved: a third of the screen empty while the
signature element was the quietest thing on it.
- Chart takes the remaining height instead of a fixed 200pt. A chart fills its sheet.
- Streak became a tick rule. Seven evenly spaced dots at the bottom of a screen is a
  `UIPageControl` and people will try to swipe it; a rule is the instrument's own vocabulary.
- The normal band was imperceptible on dark paper. Its weight now scales against the paper.
- Stopped reserving 76pt for a context line that may not exist — an empty slot reads as a
  rendering bug. The sentence pushes into the sheet when it arrives, and the chart yields.

**design:accessibility-review.** Four findings, one critical.
- The chart's VoiceOver summary said "Within the usual range" for a day *below* the band — the
  exact case the on-screen sentence was describing. Sighted and non-sighted users were told
  opposite things. Now reports all three cases.
- Low-confidence context was distinguished only by 62% opacity; the label now says so.
- The normal band borrowed `grid`, held to a decorative 1.6:1. It is essential graphic content
  under WCAG 1.4.11, so it now has its own token held to 3:1, tested at every hour.
- Empty-state button was ~37pt tall against the 44pt minimum.

**engineering:code-review.** Six findings, two of which could hang the app.
- `LocationProvider.request()` never resumed its continuation if the permission dialog was
  ignored — no delegate callback fires, so `refresh()` and the caller's `.task` hung for the
  life of the process. Now a timeout resolves the waiting continuation.
- Location resolution awaited reverse geocoding, so a slow `CLGeocoder` held up the weather
  fetch. The comment claimed a failed name must never cost us the location; the code did exactly
  that. The coordinate now resolves first and the name arrives after — which required making
  `LocationProvider` `@Observable`, or the late name would have reached nowhere.
- `loadMostRecent()` decoded every cached file to find the newest, on the synchronous launch
  path. Now sorts by modification date and decodes one, falling through if it is corrupt.
- `contextVisible` was a one-shot flag set inside `.task`; a cell cold on first fetch and warm
  later would keep its sentence hidden forever. Now driven by the data.
- `URLSession`'s 60s default timeout is far longer than anyone waits. 10s, with cache behind it.
- `StreakStore` moved to VaneKit (it is calendar arithmetic with no view in it) and dropped its
  `Sendable` conformance rather than claiming `@unchecked` over `UserDefaults`.

**engineering:tech-debt** (owed since phase 3). Ledger in `docs/TECH-DEBT.md`. Top four done:
- Backend URL moved out of a source constant into build configuration. A Release build with no
  host configured now fails at launch rather than shipping a TestFlight build pointed at
  `localhost` — which is not a degraded app, it is a dead one.
- CI added. Three suites across two languages and the only thing running them was me.
- `WeatherModel` now has tests, through a `LocationProviding` seam and a `URLProtocol` stub. It
  is the most breakable code in the app and had none.
- `docs/api-contract.md` corrected: `normal` is a band, `utc_offset_seconds` documented, and
  `forecast_cache` moved to the debt ledger rather than left as a table that exists on paper.

**Profiling.** `xctrace` could not be made to complete against the simulator (three attempts,
including one that ran past ten minutes for a 25-second recording). Cold launch to first
meaningful paint is instrumented instead, measured from `kinfo_proc` process start so dyld is
included: **285 / 228 / 219 / 216 / 229 ms over five cold launches, median ~228ms against a
1200ms budget.** Animation hitch numbers still need a physical device — a simulator has no
ProMotion, no real GPU and no thermal behaviour, and reporting its figures would be theatre.

## Phase 4 follow-up — chart legibility and conditions

Feedback: the chart could not be read at a glance, and conditions were missing entirely.

- **The chart had no value axis at all.** You could see that today rose; you could not see to
  what. Ruling now sits on labelled round temperatures (a 1/2/5/10 step chosen so the range fits
  in about five lines) rather than on arbitrary fractions of the height — a line you cannot name
  is decoration, a line at 20 degrees is a measurement.
- **Precipitation was in the payload since phase 1 and never drawn.** Now a row of marks under
  the trace, scaled against a 1mm floor so light drizzle looks light and real rain fills the row,
  and drawn only when something is actually falling — an always-present empty row teaches people
  to ignore the one place the chart says it will rain.
- **`current.code` was also unused since phase 1.** WMO 4677 codes now map to plain words
  ("Overcast", "Light rain") rather than the METAR abbreviations the chart furniture borrows:
  someone deciding on a jacket should not have to learn a code. An unrecognised code renders
  nothing rather than guessing.
- **Feels-like appears only when it differs from the reading by 2 degrees or more.** Printing
  "feels like 20" beside 20 is noise dressed as data.

## Phase 4 follow-up — the band, and conditions reaching the palette

- **The normal band read as a selection highlight.** A solid shaded rectangle is what text
  selection looks like; unlabelled, it was furniture rather than information. The fill dropped to
  a whisper (0.16 light / 0.22 dark), the dashed edges at 3:1 now carry it, and it says
  "30-YEAR NORMAL" on itself. An unlabelled shaded region cannot be the answer the whole app is
  built to give.
- **Conditions never reached the palette.** The brief requires colour state driven by sun
  position *and current conditions*; `cloudCover` was a `SkyState` parameter added in phase 3
  that nothing ever passed, so every day rendered as though it were clear. The server now sends
  measured `cloud_cover` — real cover rather than inferred from the weather code, because
  "partly cloudy" spans 25-75% and the palette needs the number, not the bucket.
- **Overcast flattens the paper toward neutral, not darker.** A grey day loses colour, not light.
  Only the paper: draining chroma from the trace would make the reading hardest to find on
  exactly the days it is greyest. Contrast is tested at every cloud level and hour.
- **Backend tests were asserting memorised fixture values** (`temp_c == 21.9`, a hardcoded
  sunrise). Re-recording the payload broke four tests for no reason. They now assert against the
  fixture's own values — the thing under test is the mapping, not the weather in Oakland on one
  afternoon.

## Phase 5 — detail and archive

- **The detail screen is contextualised, not a seven-day list.** `/v1/forecast` now attaches each
  day's own 30-year normal, and rows share one temperature axis so a warm day sits visibly right
  of a cool one. Oakland on the day this was built: 3 below normal today, swinging to 10 above by
  Wednesday — a heat wave visible as a shape.
- **Normals are attached after the cache, not inside it.** A provider payload and thirty years of
  history change on completely different clocks; baking normals into a one-hour cache entry would
  freeze them there.
- **One query for the whole forecast, matched on a packed `month * 100 + day` key.** Ten round
  trips to render one screen is an N+1 on the request path, and two parallel `unnest` calls make
  Postgres pick between overloads it cannot disambiguate from an untyped parameter.
- **GRDB, as ADR-0002 specified.** Compression is a `GROUP BY` that runs under a finger.
  Precipitation *sums* across a compressed span rather than averaging — averaging would report a
  wet week as a damp day.
- **`ArchiveStore` is `Sendable` without `@unchecked`.** GRDB's `DatabaseQueue` is itself
  `Sendable` and serialises its own access, so there is no promise the compiler cannot check.
- **Deviation from ADR-0002, stated.** That ADR made the server the source of truth and the local
  store a cache. Device identity and `/v1/archive` land with the push loop in phase 7, so until
  then the archive is *created* locally — we are the only party that knows the app was opened and
  what it was like. Phase 7 adds upload so it survives reinstall.
- **The archive is reached by dragging left on the chart**, not by a button. The signature is that
  the roll is continuous; a control that "opens the archive" would contradict the thing the design
  is about. A VoiceOver custom action provides the same route, since a drag is not operable.
- **`try?` hid a real failure.** Recording to the archive swallowed its error, so when the roll
  showed zero marks there was nothing to diagnose from. Both the store open and the write now log.
  The archive is the one thing in the app that cannot be re-fetched from anywhere.
- **The archive got its own legend and axis range.** It had inherited the forecast's, which said
  "FORECAST" over days that had already happened and stretched the scale to 10 degrees for values
  that were never drawn.
