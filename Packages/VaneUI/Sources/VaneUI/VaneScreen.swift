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
        .task { await model.refresh() }
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
                    .padding(.horizontal, 24)
                    // Sky-side room. Roughly a third of the screen, which is what it takes for
                    // the sun to sit in open sky rather than in a letterbox. At accessibility
                    // sizes it collapses first — the sky is content, but it is not content
                    // anyone needs at AX5, where the reading has to be the whole screen.
                    .padding(.bottom, typeSize.isAccessibilitySize ? 24 : 214)

                // 2. The paper sheet. Everything from here down is ink on stock.
                VStack(alignment: .leading, spacing: 0) {
                    Header(mark: focused, day: focusedDay, snapshot: snapshot,
                           scrub: scrub, palette: palette)
                        .padding(.top, 22)

                    roll(palette: palette)
                        .padding(.top, 16)

                    Readout(mark: focused, snapshot: snapshot, palette: palette)
                        .padding(.top, 14)

                    StreakBar(count: model.streak, palette: palette)
                        .padding(.top, 18)

                    panels(snapshot: snapshot, palette: palette)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 48)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(alignment: .top) {
                    // The sheet's own top edge, drawn as a rule. This is where the sky stops and
                    // the chart begins, and it is the only hard boundary on the surface.
                    palette.paperColor
                        .overlay(alignment: .top) {
                            Rectangle().fill(palette.gridColor).frame(height: 0.5)
                        }
                        .ignoresSafeArea(edges: .bottom)
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
    @ViewBuilder
    private func roll(palette: Palette) -> some View {
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
                    RollCanvas(
                        marks: marks, scrub: scrub, dayWidth: dayWidth,
                        palette: palette, isDragging: isDragging,
                        onAdjust: { step in
                            withAnimation(VaneMotion.figure) {
                                scrub = min(max(scrub + step, bounds.first), bounds.last)
                            }
                        }
                    )
                    // The scroll view underneath owns the touch; the canvas is what you look at.
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
        .frame(height: 176)
        .accessibilityHidden(span <= 0)
    }
}
