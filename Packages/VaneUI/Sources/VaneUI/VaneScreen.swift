import SwiftUI
import VaneKit

/// Phase 7.0: the strip.
///
/// Deliberately unstyled. Direction A's entire view layer is gone — the roll, the drum, the
/// panels, the palette, the sky shader — and this exists only to prove the thing underneath
/// still works: location, the cached snapshot, the live refresh, the context engine's sentence,
/// the forecast and the archive. Every one of those is untouched by the rebuild, and this screen
/// is the evidence rather than the claim.
///
/// It is replaced wholesale in 7.1 when the instrument scene arrives. Nothing here is a design
/// decision and nothing here should be defended.
public struct VaneScreen: View {
    @State private var model: WeatherModel

    public init(model: WeatherModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.block) {
                Text("PHASE 7.0 — STRIPPED")
                    .font(.vaneData).foregroundStyle(.secondary)

                if let snapshot = model.snapshot {
                    // The face, at the size and axes it will actually run at, so the strip also
                    // proves Big Shoulders resolves and its variation axes bind.
                    Text("\(Int(snapshot.current.tempC.rounded()))°")
                        .font(VaneType.display(180, weight: 900))

                    row("place", model.placeName ?? "—")
                    row("condition", snapshot.current.condition.label)
                    row("feels", "\(Int(snapshot.current.feelsC.rounded()))°")
                    row("wind", "\(Int(snapshot.current.windKt.rounded())) kt @ \(snapshot.current.windDeg)°")
                    row("pressure", "\(Int(snapshot.current.pressureHpa.rounded())) hPa")
                    row("cloud", snapshot.current.cloudCover.map { "\($0)%" } ?? "—")
                    row("normal high", snapshot.normal.map { "\(Int($0.tmaxC.rounded()))° over \($0.years)y" } ?? "warming")
                    row("forecast days", "\(model.forecast?.daily.count ?? 0)")
                    row("hourly points", "\(model.forecast?.hourly.count ?? 0)")
                    row("archive days", "\(model.timeline.filter { $0.kind == .recorded }.count)")
                    row("streak", "\(model.streak)")

                    // The whole reason the product exists. If this is blank, the context engine
                    // is the thing to look at, not the view layer.
                    Text(snapshot.context?.headline ?? "no context yet")
                        .font(.system(.title2))
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("no snapshot — screen: \(String(describing: model.screen))")
                        .font(.vaneBody)
                }
            }
            .padding(Space.margin)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task { await model.refresh() }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label.uppercased()).font(.vaneData).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.vaneData)
        }
    }
}
