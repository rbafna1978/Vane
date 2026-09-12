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

## Phase 5c — one surface, after feedback

Feedback: the detail screens felt plasticky and boxed-in, and the flow should be one screen with
things moving rather than screens being pushed.

**This was a self-inflicted contradiction.** GATE 2 recorded "dragging left is not navigation —
the same paper keeps moving", and the phase 5 handoff said "there is no shared-element transition
because there is no jump". Then I built two pushed screens with back buttons. The premise of the
design is a continuous roll; pushing a new screen to show yesterday denies it.

- **`NavigationStack`, `DetailScreen` and `ArchiveScreen` deleted.** One surface, `RollScreen`.
  The horizontal axis is time: past left, future right, pen at today.
- **Content is a function of position, not of a threshold.** Scrubbing to a past day does not
  "open" that day; the same three lines take different values. The reading rolls rather than
  swapping, because it is the same number changing, not a new one arriving.
- **The pen is fixed and the paper moves under it.** The instrument is the constant thing on
  screen; the data is what travels.
- **`apple-design` principles applied directly:** 1:1 tracking with no animation on the tracking
  path; the drag starts from the presentation value so a moving roll can be grabbed and
  redirected; Apple's momentum projection picks the landing day from where the flick was going
  rather than from where the finger left; release hands velocity to an `interpolatingSpring`;
  rubber-banding at both ends of the record.
- **The comparison is present at every position.** Today keeps its context sentence; every other
  day gets the same argument in the same form — how far it sat from its own date's normal — so
  the product's claim is not only true at the anchor.

**Lost, and worth naming:** the ten-day list view is gone. It was scannable in a way scrubbing is
not. If scanning turns out to matter it belongs *below* the roll on the same surface, not behind
a push.

**A `try?` hid the forecast failure**, for the third time in this project. The rule now: an error
may be swallowed, but it must still be logged. Both the archive write and the forecast fetch log.

## Phase 6 (re-plan) — the sky, and depth without navigation

The single-surface roll from 5c was the right fix to the wrong axis. Collapsing the pushed
screens was correct; deleting the information along with them was not. Depth and navigation are
not the same thing — Not Boring Weather has enormous depth and no navigation.

- **Direction A survives.** The scene renders the weather; the instrument is drawn in ink over
  it. See ADR-0007.
- **Vertical is depth.** Roll at the top of a scroll, panels below, every panel keyed to the
  scrub position. No pushes, no back buttons.
- **Rendering: SwiftUI `Shader` + `ShaderLibrary`, not `MTKView`.** Rationale and the conditions
  for revisiting are in ADR-0007.
- **Contrast strategy changes.** Ink is held against the *scene's* computed worst-case luminance,
  not against the paper token, because the ground is no longer flat.
- **Correction to the record:** `CLAUDE.md`'s skill table names `design:design-critique`,
  `design:accessibility-review`, `engineering:code-review` and others. Those plugins are not
  installed — `installed_plugins.json` has swift-lsp, ui-ux-pro-max and ponytail only. The
  reviews claimed as "owed" in phases 4 and 5 were owed to skills that do not exist here. What
  actually ran was the emilkowalski set. The table is corrected rather than left aspirational.
- **`frontend-design` indicts our own execution.** It names "broadsheet layout, hairline rules,
  zero border-radius" as one of three current AI defaults. That is a literal description of what
  5c shipped. Direction A is legitimate and chosen; the flat-vector execution of it was the
  default, and that is what the scene layer is correcting.
- **ponytail was ON via the SessionStart hook during a phase where CLAUDE.md says OFF.** Ignored
  for this work, per the standing rule that phases 3–6 are the product.

### Phase 6a — what the build actually found

Defects found by looking at the running app, not by tests going red:

- **The shader rendered a black rectangle.** `.colorEffect` fixes the first two parameters as
  `(float2 position, half4 color)` and mine omitted the colour. Omitting it compiles; it fails to
  *bind*, and the effect is dropped with no error.
- **The sky was mixed out of the paper tokens** and read as fog at every hour. Eau-de-nil chart
  stock darkened toward ink is not a sky. It now has its own colour ramp, pulled toward the
  paper's neutral so it still belongs beside the chart.
- **The roll's `DragGesture` and the page's vertical scroll fought over every touch.** Replaced
  by a real horizontal `ScrollView`, which is orthogonal-nesting-aware and already *is* every
  property the gesture reimplemented — 1:1 tracking, the real rubber-band curve, momentum,
  velocity handoff, interruption. About 60 lines of hand-rolled physics deleted.
- **The roll opened on the last forecast day while the header read TODAY.** `.scrollPosition(id:)`
  is applied before a lazy stack realises any row, so its initial value is dropped;
  `ScrollViewReader` called once the marks exist works.
- **Cell index was being treated as day offset.** Marks are sparse — the record only holds days
  the app was opened — so the strip runs -3, 0, 1, 2. The header sat on one day while the pen
  stood on another. Cells are now one per *day* across the span, and the focused mark is the one
  on exactly that day rather than the nearest one with data.
- **The trace drew straight through days that were never recorded**, inventing readings and
  making a sparse record look continuous. It now lifts across gaps, as a barograph does when the
  pen is off the paper.
- **A panel contradicted itself:** "23°" against "NORMAL 27°" labelled "-3°", because each
  reading was rounded on its own. Added `TimelineMark.displayAnomaly`, derived from the displayed
  figures, and used it for the header sentence too. Every number on screen now survives being
  checked with arithmetic.
- **Panel prose used `vaneReadingType()`** — the 148pt temperature face — for body text.
- **`1,016 hPa`.** Instruments do not group thousands.
- **Rain drew a regular lattice**, because it hashed by column: every drop in a column shared a
  phase and an x. Hashing the cell in both axes fixed it.
- **AX5 broke the panels**: titles wrapped mid-word through their own rules ("AGAINS / T /
  NORMAL") and the three-column row overlapped. Both now switch layout via `AnyLayout` at
  accessibility sizes.

Corrections to earlier decisions:

- **The equator-facing sun projection was wrong for this interface.** It is physically right —
  facing north from Sydney the sun does rise on your right — and it made the sun run backwards
  against the roll's own left-to-right time axis. The frame now fixes **east on the left**
  everywhere, using `sin(azimuth)`, which is monotonic across the day in both hemispheres and
  needs no latitude. This is the one deliberate departure from the physical view in the app.
- **Pressure is now mean-sea-level, not surface.** Surface pressure reads ~850 hPa in Denver,
  which against a 1013 standard looks like a storm at every altitude. MSL is what isobars,
  barograph charts and every pressure norm are quoted in.
- **The catalog is reachable** via `-VaneCatalog YES` (DEBUG only), with rain and wind controls.
  Nowhere on Earth was raining the day the sky was reviewed; a rendering path that only appears
  in bad weather otherwise ships unlooked-at.

### Phase 6b — the execution, after actually running design critique

Correction first: **the `design:` and `engineering:` skills are installed and invocable.** In 6a I
checked `~/.claude/plugins/installed_plugins.json`, saw three entries, concluded the rest were
missing, and rewrote the skill table in CLAUDE.md to say so. That file is not the roster — the
session's skill list is. The wrong check cost a phase of skipped `design:design-critique` and
`design:accessibility-review`, which is precisely how a screen ships looking like a mockup.
Verify a skill by invoking it, never by reading a manifest.

What critique found, and what changed:

- **The printed grid has been missing since GATE 2.** Direction A reads "Pale eau-de-nil stock,
  *printed hairline grid*, one aniline-violet pen trace" and the paper was a flat fill for four
  phases. Ruling is not decoration here: on a new install most of the roll is blank, and ruling
  is the entire difference between "chart stock with nothing recorded on it" and "broken app".
  Now: one vertical rule per day travelling with the paper, weighted every seventh for the week;
  labelled horizontal rules at each step with unlabelled half-steps between.
- **`ui-ux-pro-max` §Layout — "random spacing increments with no rhythm".** The screen used 10,
  14, 16, 18, 22, 26, 48 and 214pt gaps, each chosen on its own. Added `Space` — four tiers, not
  eight, because a scale with a step for every occasion is the same as no scale.
- **The chart was inset to 34pt while every line of text sat at 24pt.** Nothing aligned. The plot
  now starts at the text margin and its value labels sit *on* the paper, as a printed chart's
  scale does.
- **Two flat rectangles butt-joined by a hairline.** The sheet now has a cast shadow above its
  edge, a tonal falloff where the sky's light reaches across it, and the sky has horizon haze —
  the last few degrees above the ground look through far more atmosphere and lighten. Without
  it the gradient stopped dead at the edge, which is what made it read as paint.
- **The sun was an airbrush blob** — one falloff curve gives a uniform disc. Real forward scatter
  is a tight bright core riding on a very broad, very dim wash; added the second term, and
  antialiased the limb by the pixel's own footprint (`fwidth`) rather than a guessed constant.
- **The type hierarchy had two levels and a hole.** Three mono rows at one size and one opacity
  made a heading, metadata and a readout indistinguishable. The day label is now the largest and
  darkest of the three.
- **The degree ring never attached to the numeral.** Two failed attempts are worth recording:
  `.top` in an HStack aligns to the *ascender*, which on a 148pt condensed face sits far above
  the cap line; `baselineOffset` inside a stack moves the run's own baseline so the stack
  re-aligns around it and the ring floats free. Concatenating the runs into one `Text` makes the
  baseline shared by construction.
- **A 148pt face reserves ascender and descender whether the glyphs use them or not**, and "28"
  uses neither — about 60pt of dead air above the caps and 40 below the baseline, reading as two
  accidental gaps. Negative padding trims the box so the spacing scale controls the gaps instead
  of the font's metrics doing it by accident.
- **The streak was 28 unlabelled hairlines.** Nobody counts hairlines to learn they have a
  four-day streak. It now carries its number.

Accessibility, from `design:accessibility-review`:

- **Every reduced-emphasis label was `inkColor.opacity(0.45…0.8)`**, in 22 places, which throws
  away the contrast the palette spends its whole design earning — 10pt mono at 45% opacity
  measures about 2.2:1 against paper, less than half of AA. Opacity is a rendering trick;
  contrast is a measurement, and only one of them survives being checked. Added
  `Palette.secondary`: mixed halfway to paper, then pushed back to the 4.5:1 floor, giving the
  lightest tone that is still legal for text. Ruling and hairlines keep opacity, because they
  carry no information. Asserted across all 24 hours and three cloud covers so it cannot come
  back one `.opacity()` at a time.

## Phase 6d — the type performs, and the chart leaves the main screen

**Rule 1 is now in `CLAUDE.md`:** every decision consults a skill first, and where no installed
skill covers it, one gets found on the web and installed before deciding. This phase is the first
worked under it.

- **Installed `swiftui-pro`** (MIT, Paul Hudson) under Rule 1, after searching for a kinetic
  typography skill and finding none that was not React-bound. It is Swift-native and covers the
  SwiftUI animation and accessibility APIs that `write-swift` does not. It immediately paid for
  itself: it caught that `DisplayMetrics` was doing a CoreText font lookup inside `body`, twice
  per frame, on the drag path.
- **The chart is off the main screen.** It was the hero from GATE 2 and it was the wrong hero:
  dense, slow to read, and the single largest reason the opening surface looked like a report. It
  is now `RollPanel`, one detail among several, for anyone who scrolls to it. Direction A's
  signature survives — it just is not the first thing anybody sees.
- **Time travel is expressed by the figure, not by a plot.** The reading is a mechanical odometer:
  digit wheels, each engaging only as the wheel to its right passes nine. Same vocabulary as the
  drum the paper is wrapped around. The gate that licenses it: motion is 1:1 with the finger, so
  it is manipulation feedback rather than decoration, and a number that *travels* carries the
  direction and magnitude the chart used to carry.
- **No `Animation` is involved in the roll.** The wheels are a pure function of scrub position, so
  there is nothing to animate during a drag; only the release is animated, by the spring that
  settles the scrub, and the wheels follow it for free.
- **The sentence sets itself word by word on the way in, and crossfades on scrub.** Two
  behaviours, because the two moments sit at opposite ends of the frequency table — delight is
  licensed once per open, not dozens of times inside one gesture on text somebody is reading.
- **What is left of the roll on the main surface is 44 points of day ticks.** A gesture with no
  affordance is undiscoverable; a chart is clutter. The rim is neither.

Defects found and fixed on the way:

- The odometer's digit band was guessed as `size * 0.74` and clipped, leaving slivers of the
  neighbouring numerals around every digit. Positioned now from the font's own cap height and
  ascent, measured with CoreText. The digit advance was guessed too, which left a visible gap
  between the tens and units so the figure read as two numbers.
- The wheels sat **permanently mid-roll**, because they were fed the raw temperature: 25.4°C is a
  wheel 40% of the way from 5 to 6. The surface now interpolates between *rounded* day values, so
  a whole-numbered scrub always lands on a whole-numbered wheel.
- A day with no observation left a blank hole where the reading was, which read as the app having
  failed. It now prints an em dash — the notation climate records and METAR have always used for
  a missing observation.

## Phase 7 — rebase

The reference is Not Boring Weather. Direction A cannot reach it and is retired; the full plan is
in `docs/PLAN-phase7.md`. Summary of what changed at the level of a decision:

- **Direction A is dead.** "The chart, never the machine" — my own GATE 2 sentence — produced a
  static document, which is what a chart is. The brief asked for meteorological *instruments* and
  I shipped their output instead.
- **Position: their craft standard, our claim.** Not Boring renders the weather beautifully and
  does not compete on meaning at all. Matching its rendering is table stakes; the sentence is the
  differentiation. Decided with `product/discover-competitive-analysis`.
- **Steal the annotation overlay, not the clouds.** Callouts with leader lines into the scene is
  the right answer to progressive disclosure. Clay clouds on white is their signature and
  shipping it is a knock-off.
- **Recommended direction: the instruments as objects** — vane, aneroid, column, cups, gauge —
  not the sky. Needs sign-off before any view code.
- **Rendering: Metal SDF raymarching**, not RealityKit and not sprites. `ios-3d` (installed under
  Rule 1) surfaced that SceneKit is soft-deprecated as of iOS 26, which most training data still
  gets wrong. RealityKit was rejected for a reason worth recording: it needs authored USDZ assets
  that nobody on this project can produce, so it would make the look depend on a capability we do
  not have.
- **Skills installed under Rule 1:** `ios-3d` (MIT reference docs only — the upstream project also
  ships MCP servers and a CLI, which is infrastructure and needs agreement, not a side effect) and
  five `product/` skills (Apache 2.0, product-on-purpose).
- **~2,800 of 6,700 lines are discarded, and none of them are backend or VaneKit.** The parts
  built against the brief survived; the parts built against my reading of it did not.

## Phase 7.0 — the strip

**No graphs, anywhere.** Added to the hard constraints, not as a layout preference but as a
product rule: no plots, traces, curves, sparklines, axes or scatter. Every one built in phases
3–6 made its screen worse. This kills `BarographTrace`, `RollCanvas`, `RollPanel`, `HourlyCurve`,
`PressureTrace` and `AnomalyBar`.

It costs nothing, because the direction already answers it: **the instrument is the reading.** An
aneroid dial does not need a pressure graph beside it — it *is* the pressure. The column is the
temperature, the vane is the bearing, the cups are the strength. What an instrument cannot carry
becomes a number with a plain label or a sentence. The reference contains no graph either.

- **VaneUI: 4,013 → 1,000 lines.** Deleted the three graph files, Direction A's surfaces
  (`VaneScreen`, `DrumSheet`, `PaperScroll`, `ContextLine`, `Catalog`, `EmptyStateView`), and the
  superseded `RollingNumber`, `Palette` and `SkyView`.
- **Two things were carried out of the wreck rather than deleted with it.** `Sky.metal`'s noise
  field became `Noise.metal` — value noise and a four-octave fBm, tuned by looking rather than by
  copying constants, and exactly what the instrument scene needs for clay grain. And the sky's
  hemisphere-safe bearing projection became `VaneKit/SceneFrame`, with its tests: it is not about
  skies, it is the answer to "the sun is at azimuth 280°, where does that go on screen", which
  the instrument scene asks for its lighting and its vane. It cost two bugs to get right.
- **Backend and VaneKit are untouched.** 68 and 37 tests pass unchanged.
- **Type moved to Big Shoulders.** Archivo Narrow, JetBrains' partner since phase 3, is gone.
  `VaneType.display(_:weight:)` sets `wght` and `opsz` on the font descriptor, because SwiftUI's
  `.fontWeight()` does not reliably drive a custom variable face's weight axis and cannot address
  optical size at all — and `opsz` is the reason this face was chosen. **Big Shoulders' default
  instance is Thin**, so asking for the face by name without setting the axes silently gives the
  lightest cut in the family.
- A test asserts the axes bind. Counting entries in `CTFontCopyVariation` does *not* work:
  CoreText omits an axis whose value equals its default, and at a 180pt setting `opsz` clamps to
  72, which is this face's default — so it vanishes from the dictionary, which looks exactly like
  the axis being ignored and is the opposite.
- **graphify rebuilt: 742 nodes, 1,520 edges, 38 communities.** The god nodes are now
  `WeatherModel`, `OpenMeteoSource`, `Cell`, `choose()`, `LocationProvider` — all data layer. No
  view-layer node is a hub any more, which is the correct shape after a strip. The shrink guard
  refused the incremental update (958 → 460 nodes); a full rebuild was run rather than forcing
  past it, and the final write used `force=True` only because the reduction is this session's own
  deliberate deletion and is in git.

7.0's exit criterion is met: the app builds and shows real live data — place, condition, wind,
pressure, normals over 30 years, 10 forecast days, 240 hourly points, archive, streak — and the
context engine's sentence, today: *"Warmest September 9th in 30 years."*

## Phase 7 — Direction C, and Spline

Direction B lasted one mockup. The verdict — cold objects, flat, too serious — and the diagnosis
worth keeping: **I chose austere twice.** Direction A was a quiet instrument chart; B was a grey
technical apparatus. The brief asked for fun and not-boring every single time. That is taste
overriding brief, twice, and it cost six rounds plus a rebuild.

A second, structural error: **Direction B was signed off from a paragraph.** "The instruments,
rendered as heavy clay objects" reads well and renders as an engineering diagram. Text
descriptions of visual directions are close to worthless; mockups now come before sign-off, not
after it.

- **Direction C (locked): the weather itself, as soft clay objects.** Cloud, sun, rain, moon —
  charm can live in a cloud and cannot live in an anemometer.
- **The distance rule is retired.** "Don't look adjacent to the reference" was the constraint that
  produced the grey diagram. Adjacent is now the target; differentiation is the meaning layer.
- **What is ours: the ground is the real sky**, computed from the sun's true position. They are
  always white. Vane is never the same colour twice — and the one line of the original brief that
  outlived every direction change, *"light and dark is not a toggle"*, finally does something.
- **All thirteen surfaces are mocked before implementation**, at the user's instruction: main ×3,
  detail overlay, hour by hour, the week, thirty years, your record, first run, warming, offline,
  denied, settings, widgets, Live Activity, morning card.
- Two screens worth naming. **Hour by hour** is a band where each column is that hour's actual sky
  colour, with temperature as the dark fill — the day's light, not a plot. **Your record** is a
  quilt of sky swatches, one per day the app was opened: the return loop made visible, and
  unfakeable, because it only grows if you come back.
- **The old sun is deleted, not carried forward.** It was a radial-gradient blob and the user is
  right that it was bad. A sun in this direction is a dimensional object with grain and a cast
  shadow, not a glow.
- **Rendering moves to Spline — see ADR-0008**, which supersedes ADR-0007's Metal SDF plan. The
  bottleneck was never the renderer; it was that I cannot author art. Moving the art into a tool
  built for it, operated by someone with taste, is the actual fix.

## Phase 7 — the stack, researched properly, and one surface instead of thirteen

**ADR-0008 is withdrawn before any code.** It recorded "no source confirms what Not Boring uses"
and adopted Spline anyway. A caveat does not turn a hunch into a decision.

- **Not Boring is Blender + SceneKit** — Andy Allen and Mark Dawson at Andy Works, in their own
  words. **Vane is Blender → USDZ → RealityKit**: their architecture, current renderer, because
  SceneKit is soft-deprecated and they chose it years before that. See ADR-0009.
- Rejecting Spline is not only about the licence. Taking a closed 8.6 MB binary with no LICENSE
  file, in order to imitate a stack that turns out not to use it, is the worst of both worlds.
- **Thirteen mockups described thirteen pages.** That was the real UX failure and it contradicted
  the brief's own premise. Vane has **one scene and one sheet.** Hour by hour, the week, thirty
  years and the record are *sections of one continuous sheet*, pulled to whatever height the user
  wants. Detail annotates the scene in place and the composition never moves.
- The scene **recedes and dims rather than leaving**, so there is nothing to navigate back to.
- Mechanics, from `apple-design`: 1:1 tracking with nothing eased on the drag path, momentum
  projected to pick the detent, interruptible mid-flight from the presentation value, rubber-band
  at both ends, springs rather than durations because a duration cannot absorb an interruption.
- **Accessibility is the mechanism, not a fallback.** A drag-only interface is unusable with
  VoiceOver. The sheet is an adjustable control whose increments are exactly the detents, so
  VoiceOver swipes move it the way a drag does; Reduce Motion crossfades between detents instead
  of travelling.
- Delivered as a **draggable prototype rather than more stills**, because "organic and easy going"
  cannot be judged from a picture.
