# Phase 7 — the rebuild

Written before any code, under Rule 1. Every section below names the skill it was decided with.

---

## 1. The reckoning

**Direction A is dead.** It was locked at GATE 2 as *"The chart, never the machine. Pale
eau-de-nil stock, printed hairline grid, one aniline-violet pen trace."* The reference we are now
competing with is object-based, dimensional, maximalist, on pure white with a single screaming
red. There is no iteration that connects those two. Six rounds of feedback have felt like
polishing the wrong thing because they were.

The specific sentence that caused the most damage is one I wrote: **"the chart, never the
machine."** A chart is a static document. It produced a static document. The irony is that the
brief's own instruction — *"visual language derived from atmosphere and its instruments"* — points
at the machine, and I chose its output instead.

### What actually dies

| Layer | Lines | Verdict |
| --- | --- | --- |
| Backend (`backend/vane`) | 1,628 | **Survives whole.** The context engine, normals, ranking and backfill are the product's thesis and are unrelated to how it looks. |
| `VaneKit` | ~1,050 | **Survives whole.** Models, `SunPosition`, `VaneClient`, `SnapshotStore`, `LocationProvider`, `StreakStore`, `ArchiveStore`, `Timeline`. This is data, not design. |
| `VaneUI` | ~2,800 | **Mostly dies.** Keep `RGB`/contrast maths and `Sky.metal` as a starting point for the scene shader. Delete the roll, the drum, the panels, the odometer, the typography scale, the palette endpoints. |
| Tests | 1,723 | Backend (68) and VaneKit (34) survive. Most VaneUI tests (35) go with their subjects. |

Roughly **2,800 of 6,700 lines are discarded.** That is the honest number. Nothing in the backend
or the data layer is wasted, and the reason is worth stating: the parts built against *the brief*
survived, and the parts built against *my reading of the brief* did not.

---

## 2. Competitive position

*Decided with `product/discover-competitive-analysis`.*

| | Apple Weather | Not Boring Weather | **Vane** |
| --- | --- | --- | --- |
| What it renders | A conventional list | The weather, as delightful objects | The instruments, as objects |
| Craft ceiling | High, invisible | **Very high, the point** | Must match Not Boring or lose |
| Depth model | Vertical scroll | Annotation overlay on the same scene | Annotation overlay, same scene |
| What it tells you | What it is | What it is | **What it means** |
| History | None | None | 30 years, per calendar date |
| Return loop | Widget | Widget | Streak, archive, morning card |

**The finding: Not Boring wins on rendering and does not compete at all on meaning.** It will tell
you it is 54° and mostly cloudy, beautifully. It will never tell you this is the second-warmest
September 8th in thirty years.

So the position is: **their craft standard, our claim.** The scene tells you what it is like
outside. The sentence tells you what it means. Matching their craft is table stakes, not
differentiation — if we only match it we have built a worse version of a famous app.

### The thing to steal, and the thing not to

**Steal the annotation overlay.** Callouts with leader lines pointing into the scene is the right
answer to "details at people's fingertips" — far better than my vertical panel stack, because the
detail stays attached to the thing it describes and the composition never changes.

**Do not steal the clouds.** Clay clouds and a red sun on white is *their* signature, recognisable
to anyone who has seen the app. Shipping it is a knock-off.

---

## 3. What the app is

*Decided with `product/define-problem-statement` and `product/define-jtbd-canvas`.*

**Problem.** People check the weather several times a day and learn a number they cannot place. 54°
is meaningless without knowing whether 54° is remarkable here, now, for this date. Every weather
app answers "what is it?" and none answers "is this normal?" — which is the question actually
being asked when someone says *"is it cold out?"*

**The job.** *When I check the weather, I want to know whether today is worth remarking on, so I
can decide what to wear, what to do, and whether to mention it.*

**Success, measured.**
- Someone can state the day's context out loud after a two-second glance.
- Day-7 return rate — the streak and the archive are the return loop, and if they do not produce
  return the loop is decoration.
- First-run comprehension: a novice reads the main screen with no explanation. *This is the test
  the current build fails.*

**Explicitly not doing:** radar, severe-weather alerting beyond NWS pass-through, multi-city
management, social, AI chat.

---

## 4. The design direction — **needs sign-off**

*Framed with `frontend-design` and `product/develop-solution-brief`.*

The composition is settled by the reference: one object scene, one enormous figure, one line of
meaning, a technical overlay on demand. What is **not** settled is what the objects are, and that
is the whole question of whether Vane is itself or a tribute act.

**A — The instruments. (Recommended.)** Not clouds. The instruments that measure the weather,
rendered as heavy clay objects: a wind vane, an aneroid dial, a mercury column, anemometer cups,
a rain gauge filling. They assemble differently by conditions — the vane swings to the real
bearing, the column rises to the real temperature, the cups spin at the real speed. The app is
called **Vane**. The brief asked for meteorological instruments in the first place. It cannot be
confused with Not Boring, because Not Boring renders the *sky* and this renders the *apparatus*.

**B — The sky, our own palette.** Clay clouds and a sun, in our colours, our forms. Fastest to
build, closest to the reference, and the highest risk of reading as derivative.

**C — The specimen.** Each day is a physical object; today sits on the plinth and the archive is
a shelf receding behind it. The most original and the most likely to confuse someone who just
wants to know if they need a coat.

**Signed off: A, the instruments.**

### The display face — settled by looking

Also signed off: shortlist properly rather than licence or default. Six candidates were set at
54°/180pt on device (`-VaneSpecimen YES`) rather than judged from specimen sheets.

**Chosen: Big Shoulders**, variable `wght` 100–900 and `opsz` 10–72, at 900/72 for the figure.

- The optical-size axis is the rare property and the deciding one: one family cut correctly for a
  180pt figure *and* a 12pt label, which no other candidate offers.
- Archivo Narrow, the incumbent, has no mass beside it — set together, it is thin and would
  disappear against a rendered scene. It was a fallback for FF DIN Condensed and was never
  reconsidered after the direction changed under it.
- Rejected: Anton (right mass, one weight, nothing to set small text in), Oswald (rank 9 on
  Google Fonts — competent and everywhere), Special Gothic Condensed (character, but light).

The specimen screen and the losing faces come out of the bundle in 7.0.

---

## 5. How the scene gets rendered

*Decided with `ios-3d`, installed under Rule 1 because nothing covered this.*

**The finding that changes the architecture: `SceneKit` is soft-deprecated as of iOS 26.** Most
training data still recommends it. New 3D work uses RealityKit — but that is not what we want
either, and here is the reasoning:

| Approach | Verdict |
| --- | --- |
| RealityKit + USDZ assets | **Rejected.** Needs authored 3D models. I cannot model, texture and light USDZ assets, so this makes the look depend on assets nobody on this project can produce. |
| Pre-rendered sprite sheets | **Rejected.** Exact art control, but the scene must vary continuously with cloud cover, wind bearing, sun elevation and pressure. A finite set of images cannot, and the payload is large. |
| **Metal SDF raymarching** | **Chosen.** The forms in the reference are literally unions of spheres, which is what a signed distance field is best at. Fully parametric, so the scene is a continuous function of the real weather rather than a lookup. Tiny binary. We already ship a working Metal pipeline. |
| SwiftUI Canvas + gradients | **Rejected.** This is what the current build does and it is why everything looks flat. |

**Cost, stated up front.** A full-screen raymarch is the most expensive thing in the app. Budget:
render at half resolution into an offscreen texture and upscale, 30Hz for the ambient state,
pause entirely on `thermalState >= .serious` and under Reduce Motion. If it cannot hold frame on
a real device, the scene loses resolution before the app loses its frame rate. **These numbers
come from a physical device or they are not numbers** — the simulator has told us nothing useful
about GPU cost all project.

**Dimensional type** is layered offset glyph copies with a darkened extrusion and a lit face —
not real 3D — because a glyph extruded properly needs mesh generation for a shape that is only
ever seen from one angle.

---

## 6. Phases

Each ends with `design:design-critique`, `design:accessibility-review`, `review-animations` and
`engineering:code-review` **run and shown**. That is the definition of done and it has been
skipped twice.

| # | What | Ends when |
| --- | --- | --- |
| 7.0 | Strip `VaneUI` to `RGB` + the shader. Keep VaneKit and the backend untouched. Regenerate the graphify map. | The app builds and shows one unstyled label from real data. |
| 7.1 | **Direction sign-off**, then the scene shader for one condition only — clear day. Physical-device frame numbers. | The scene holds 60fps on device, or the budget changes. |
| 7.2 | The scene as a function of real weather: cover, wind bearing, sun position, precipitation, pressure. | Every condition renders and none is a special case. |
| 7.3 | The figure and the sentence. Dimensional type, the odometer roll rebuilt against the new type. | A novice reads the main screen unaided. |
| 7.4 | The annotation overlay — callouts, leader lines, and Vane's own version pointing at *history*, not just instrument readings. | Details reachable in one gesture, composition unchanged. |
| 7.5 | Forecast days, archive, streak — as objects and figures, never as a plot. | The return loop is real. |
| 7.6 | Widget, Live Activity, morning push. | Phase 6 of the original brief, finally. |
| 7.7 | Deploy, device auth, rate limiting. | Shipping. |

---

## 6a. No line charts

A hard constraint, added after the direction was locked: **no lines, traces, curves, sparklines
or scatter anywhere in the product.** A line asks the reader to decode an axis, a scale and a
slope before it says anything, and every one built in phases 3-6 made its screen worse.

**Bars are allowed**, read by length, which needs no decoding. They earn their place on
comparisons between discrete things — and the most important one in the product turns out to be
exactly that shape: this calendar date across thirty years, with today's bar tallest. That single
figure *shows* "warmest September 9th in 30 years" without anybody reading a word.

This is not a loss, because the direction already answers it. **The instrument is the reading.**
An aneroid dial does not need a pressure graph beside it — it *is* the pressure, and it shows the
trend by where the needle sits against the standard. A mercury column is the temperature. The vane
is the bearing. Anything an instrument cannot carry becomes a number with a plain label, or a
sentence. The reference contains no graph either: objects, figures, and a single range scale.

Deleted by this rule: `BarographTrace`, `RollCanvas`, `RollPanel`, `HourlyCurve`, `PressureTrace`,
`AnomalyBar`.

## 7. Where this could still go wrong

Named now so they are not discovered at 7.4.

- **The scene is not fast enough on device.** Most likely failure. Mitigation in 7.1, deliberately
  early, and the fallback is fewer raymarch steps and a lower internal resolution — not a
  different look.
- **We build a Not Boring clone anyway.** Mitigated by direction A, and by a critique at every
  phase that asks the question directly.
- **The display face is still a fallback.** Archivo Narrow is standing in for FF DIN Condensed. On
  a screen this typographic that is the largest remaining identity gap and it costs money, not
  effort.
- **My taste is the bottleneck.** Six rounds of feedback say so plainly. The mitigation is that
  design critique now runs *before* you see it, not after.
