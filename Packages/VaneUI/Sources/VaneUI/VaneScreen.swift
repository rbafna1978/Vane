import SwiftUI
import VaneKit

/// The whole app, on one surface, with two axes.
///
/// **Horizontal is time.** The pen is fixed, the paper moves under it, and the reading, the
/// sentence and every panel are continuous functions of where the pen sits.
///
/// **Vertical is depth.** Sky at the top, chart paper below it, and the paper rises over the sky
/// as you scroll — you descend out of the weather and into the record. Nothing is pushed and
/// there is no back button, because depth and navigation are not the same thing. Phase 5c
/// collapsed three pushed screens into one and deleted the depth along with them; this is the
/// correction.
///
/// The two axes compose: scrub sideways to a day and every panel below reads that day.
public struct VaneScreen: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    @State private var model: WeatherModel
    /// Days from today. Continuous rather than an index, so content responds at every frame —
    /// which is the difference between manipulating a roll and navigating a carousel.
    @State private var scrub: Double = 0
    /// Whether the roll is being touched, from the scroll view's own phase rather than
    /// inferred from a gesture. The pen's guide line firms up while you are moving the paper.
    @State private var isDragging = false

    /// The entrance, 0 to 1.
    ///
    /// One orchestrated moment, which is the budget `CLAUDE.md` allows per screen and the tier
    /// `find-animation-opportunities` licenses for delight — a weather app is opened once or
    /// twice a day, which is the rare end of its frequency table, not the hundred-times-a-day
    /// end where motion has to be removed. Everything downstream reads this one value and
    /// derives its own slice of it, so the sequence is a single interruptible animation rather
    /// than a chain of nested delays that cannot be cancelled.
    @State private var entrance: Double = 0

    /// Whether the roll has been placed on today yet. Once only — re-centring on every change
    /// would yank the paper out from under a finger each time a refresh landed.
    @State private var hasCentred = false

    private let dayWidth: CGFloat = 46

    public init(model: WeatherModel) {
        _model = State(initialValue: model)
    }

    private var marks: [TimelineMark] { model.timeline }
    private var bounds: (first: Double, last: Double) {
        (marks.first?.offset ?? 0, marks.last?.offset ?? 0)
    }
    /// Every day on the strip, including the ones with no reading. The axis is time, so a day
    /// the app never saw still occupies its place on the paper.
    private var days: [Int] {
        guard !marks.isEmpty else { return [] }
        return Array(Int(bounds.first)...Int(bounds.last))
    }

    /// The mark on the day under the pen — exactly that day, not the nearest one that happens
    /// to have data. Snapping to the nearest *mark* would let the pen sit on Sep 6 while the
    /// header read Sep 5, and would quietly present one day's figures as another's.
    private var focused: TimelineMark? {
        let day = scrub.rounded()
        return marks.first { $0.offset == day }
    }

    /// The day under the pen, whether or not anything was recorded on it.
    private var focusedDay: Int { Int(scrub.rounded()) }

    /// The figure on the wheels: this day's reading and the next one's, mixed by how far the
    /// scrub sits between them.
    ///
    /// Interpolating between the **rounded** day values, not the raw ones, is what makes the
    /// odometer land clean. Fed the live temperature directly it sat permanently mid-roll —
    /// 25.4°C is a wheel 40% of the way from 5 to 6, so the reading was never legible at rest.
    /// Rounding first means a whole-numbered scrub always produces a whole-numbered wheel, and
    /// everything in between is the honest travel from one to the other.
    private func displayReading(snapshot: Snapshot) -> Double {
        func value(day: Int) -> Double? {
            if day == 0 { return snapshot.current.tempC.rounded() }
            return marks.first { $0.offset == Double(day) }?.highC.rounded()
        }
        let lower = Int(scrub.rounded(.down))
        let fraction = scrub - Double(lower)
        switch (value(day: lower), value(day: lower + 1)) {
        case let (start?, end?): return start + (end - start) * fraction
        case let (start?, nil): return start
        case let (nil, end?): return end
        // A gap in the record on both sides: hold the live reading rather than invent a journey
        // between two days that have none.
        default: return snapshot.current.tempC.rounded()
        }
    }

    public var body: some View {
        let palette = model.sky.palette

        ZStack(alignment: .top) {
            if let scene = model.scene {
                // Fixed, not scrolled. The sky does not slide when you move a piece of paper.
                SkyView(scene: scene, phaseLabel: model.sky.phase.label)
            } else {
                palette.paperColor.ignoresSafeArea()
            }

            if let snapshot = model.snapshot {
                content(snapshot: snapshot, palette: palette)
            } else {
                EmptyStateView(screen: model.screen, palette: palette) {
                    Task { await model.refresh() }
                }
            }
        }
        .animation(VaneMotion.sky, value: palette)
        .task {
            // The entrance runs *before* the refresh, not after it.
            //
            // `WeatherModel.init` loads the cached snapshot synchronously, so there is already
            // content on screen at the first frame — running the entrance after the network
            // meant the interface sat there fully formed and then animated itself in a second
            // later, which is worse than not animating at all. Offline-first means the opening
            // moment belongs to the cache, and the refresh just updates the numbers underneath.
            if reduceMotion {
                entrance = 1
            } else {
                withAnimation(.smooth(duration: 1.1)) { entrance = 1 }
            }
            await model.refresh()
        }
    }

    @ViewBuilder
    private func content(snapshot: Snapshot, palette: Palette) -> some View {
        // Text over the rendered sky cannot borrow the paper's contrast guarantee, so it gets
        // its own, held against the darkest the scene can be.
        let skyInk = (model.scene?.ink(palette) ?? palette.ink).color

        ScrollView(.vertical) {
            VStack(spacing: 0) {
                // 1. Over the sky.
                StationLine(snapshot: snapshot, place: model.placeName, palette: palette)
                    .foregroundStyle(skyInk)
                    .padding(.horizontal, Space.margin)
                    // Sky-side room. Roughly a third of the screen, which is what it takes for
                    // the sun to sit in open sky rather than in a letterbox. At accessibility
                    // sizes it collapses first — the sky is content, but it is not content
                    // anyone needs at AX5, where the reading has to be the whole screen.
                    .padding(.bottom, typeSize.isAccessibilitySize ? Space.group : 208)

                // 2. The paper sheet. Everything from here down is ink on stock.
                VStack(alignment: .leading, spacing: 0) {
                    Header(mark: focused, day: focusedDay, snapshot: snapshot,
                           reading: displayReading(snapshot: snapshot),
                           scrub: scrub, palette: palette, entrance: entrance)
                        .padding(.top, Space.group)

                    // The time control.
                    //
                    // The chart used to live here and it was the wrong hero: dense, unreadable
                    // at a glance, and the single thing that made the opening screen read as a
                    // report. Time travel is now expressed by the figure itself rolling, so all
                    // that is left is the drum's rim — a rule of day ticks, which exists to say
                    // "this surface moves" and nothing else. Without any affordance at all the
                    // gesture is undiscoverable; with a chart it is clutter.
                    dayRule(palette: palette, snapshot: snapshot)
                        .padding(.top, Space.block)

                    StreakBar(count: model.streak, palette: palette)
                        .padding(.top, Space.group)
                        .modifier(Enter(entrancePhase(entrance, start: 0.42)))

                    panels(snapshot: snapshot, palette: palette)
                }
                .padding(.horizontal, Space.margin)
                .padding(.bottom, Space.section)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(alignment: .top) {
                    DrumSheet(palette: palette)
                }
            }
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    @ViewBuilder
    private func panels(snapshot: Snapshot, palette: Palette) -> some View {
        let hours = hoursForFocusedDay(snapshot: snapshot)
        let isToday = abs(scrub) < 0.5

        VStack(spacing: 0) {
            HourlyPanel(hours: hours, palette: palette)
            // The chart, demoted from hero to detail. It is a genuinely good instrument and a
            // genuinely bad opening screen — dense, slow to read, and the reason the surface
            // looked like a report. Down here it is one panel among several, available to
            // anyone who wants it and in nobody's way.
            RollPanel(
                marks: marks, scrub: scrub, dayWidth: dayWidth, palette: palette,
                timeZone: snapshot.timeZone, observedAt: snapshot.observedAt
            )
            PressurePanel(hours: hours, palette: palette)
            WindPanel(
                // Today reads the live observation; any other day in the forecast window reads
                // the middle of that day, which is the single figure that best represents it.
                knots: isToday ? snapshot.current.windKt : middayHour(hours)?.windKt,
                degrees: isToday ? snapshot.current.windDeg : middayHour(hours)?.windDeg,
                palette: palette
            )
            NormalPanel(mark: focused, years: snapshot.normal?.years, palette: palette)
        }
    }

    /// The hourly series belonging to the day the pen is on, in that location's own zone.
    ///
    /// Empty for archive days, and the panels say so rather than drawing a flat line — the
    /// record genuinely keeps one high and one low per past day.
    private func hoursForFocusedDay(snapshot: Snapshot) -> [ForecastHour] {
        guard let focused, let hourly = model.forecast?.hourly else { return [] }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = snapshot.timeZone
        let formatter = Timeline.dayFormatter(in: snapshot.timeZone)
        return hourly.filter { formatter.string(from: $0.t) == focused.dayKey }
    }

    private func middayHour(_ hours: [ForecastHour]) -> ForecastHour? {
        hours.isEmpty ? nil : hours[hours.count / 2]
    }

    /// The roll, driven by a real horizontal scroll view.
    ///
    /// This replaces a hand-rolled `DragGesture` that tracked 1:1, projected momentum with
    /// `predictedEndTranslation`, handed velocity to an `interpolatingSpring` and rubber-banded
    /// at the ends. All of that was correct and all of it is now deleted, for two reasons.
    ///
    /// The first is that it could not coexist with the vertical scroll: a `simultaneousGesture`
    /// on the canvas claimed the touch and the page stopped scrolling. The second is that every
    /// property it reimplemented — 1:1 tracking, the real rubber-band curve, momentum, velocity
    /// handoff, mid-flight interruption — is what `UIScrollView` already is, and it is
    /// orthogonal-nesting-aware in a way two competing gestures never will be.
    ///
    /// The content is invisible: it exists only to give the scroll view a length to travel. The
    /// canvas is an overlay reading `scrub`, so the pen stays fixed and the paper still moves
    /// under it — the rendering is unchanged, the physics underneath it is now Apple's.
    /// The drum's rim: day ticks and the day under the pen. Not a chart — no values, no axis,
    /// no trace. It is the affordance for the horizontal gesture and the readout of where that
    /// gesture has got to, in about a fortieth of the height the chart took.
    @ViewBuilder
    private func dayRule(palette: Palette, snapshot: Snapshot) -> some View {
        let span = bounds.last - bounds.first

        GeometryReader { proxy in
            ScrollViewReader { scroller in
                ScrollView(.horizontal) {
                    // One cell per *day* across the whole span, not one per mark.
                    //
                    // Marks are sparse: the record only holds days the app was actually
                    // opened, so on a new install the strip runs -3, 0, 1, 2 … With one cell
                    // per mark, cell index stopped equalling day offset and the scroll
                    // position mapped to the wrong day — the header read Sep 5 while the pen
                    // stood on Sep 6. Days are the axis, so days are the cells.
                    LazyHStack(spacing: 0) {
                        ForEach(days, id: \.self) { day in
                            Color.clear
                                .frame(width: dayWidth, height: 1)
                                .id(day)
                        }
                    }
                    .scrollTargetLayout()
                    // Half a viewport of lead-in at each end, so the first and last day can
                    // both reach the pen at the centre instead of stopping short of it.
                    .padding(.horizontal, proxy.size.width / 2 - dayWidth / 2)
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollIndicators(.hidden)
                .onScrollPhaseChange { _, phase in
                    isDragging = phase == .interacting || phase == .decelerating
                }
                // Continuous, every frame, straight from the live content offset — which is
                // what makes the header a function of position rather than a thing that
                // switches when a day "arrives".
                .onScrollGeometryChange(for: Double.self) { geometry in
                    geometry.contentOffset.x / dayWidth
                } action: { _, days in
                    scrub = min(max(bounds.first + days, bounds.first - 2), bounds.last + 2)
                }
                .overlay {
                    DayRule(
                        days: days, marks: marks, scrub: scrub, dayWidth: dayWidth,
                        palette: palette, isDragging: isDragging, entrance: entrance,
                        timeZone: snapshot.timeZone, observedAt: snapshot.observedAt,
                        onAdjust: { step in
                            withAnimation(VaneMotion.figure) {
                                scrub = min(max(scrub + step, bounds.first), bounds.last)
                            }
                        }
                    )
                    // The scroll view underneath owns the touch; the rule is what you look at.
                    .allowsHitTesting(false)
                }
                // The roll opens on today, not on the oldest day in the record.
                //
                // `.scrollPosition(id:)` was tried first and does not work here: the binding is
                // applied before the lazy stack has realised any row, so the initial value is
                // dropped and the scroll view stays at its leading default. A reader called
                // once the marks exist scrolls content that is actually there.
                .onChange(of: days, initial: true) {
                    guard !hasCentred, days.contains(0) else { return }
                    hasCentred = true
                    scroller.scrollTo(0, anchor: .center)
                }
            }
        }
        .frame(height: 44)
        .accessibilityHidden(span <= 0)
    }
}
