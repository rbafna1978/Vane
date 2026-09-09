import CoreText
import SwiftUI

/// Candidate display faces, at the size they will actually be used.
///
/// A display face cannot be chosen from a specimen sheet or a popularity rank. The figure on
/// Vane's main screen is roughly 180 points tall and is the single most-looked-at object in the
/// product, so the only honest way to pick is to set the real number at the real size and look
/// at it. `-VaneSpecimen YES` opens this; it is DEBUG-only and the fonts here ship with it, so
/// all of it comes out once the choice is made.
public struct Specimen: View {
    /// Registered separately from the product faces: these are candidates, not the design system.
    public static func register() {
        for name in ["Anton", "BigShoulders", "Oswald", "SpecialGothic"] {
            guard let url = Bundle.module.url(forResource: name, withExtension: "ttf") else {
                continue
            }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    private struct Candidate: Identifiable {
        let id = UUID()
        let label: String
        let postScript: String
        /// Big Shoulders carries `wght` and `opsz` axes; the rest are single instances.
        var weight: CGFloat?
        var opticalSize: CGFloat?
        let note: String
    }

    private let candidates: [Candidate] = [
        .init(label: "BIG SHOULDERS 900 / opsz 72", postScript: "BigShoulders-Thin",
              weight: 900, opticalSize: 72,
              note: "Variable wght + opsz. An optical-size axis is the rare thing here: the same family can be cut for 180pt and for 12pt."),
        .init(label: "BIG SHOULDERS 700 / opsz 72", postScript: "BigShoulders-Thin",
              weight: 700, opticalSize: 72,
              note: "Same family, lighter. Worth seeing whether 900 is too heavy against a rendered scene."),
        .init(label: "ANTON", postScript: "Anton-Regular",
              note: "One weight, very heavy, closest to the reference's mass. No range at all — nothing to set small text in."),
        .init(label: "OSWALD BOLD", postScript: "Oswald-Regular", weight: 700,
              note: "Variable weight. Rank 9 on Google Fonts — competent and everywhere, which is its problem."),
        .init(label: "SPECIAL GOTHIC CONDENSED", postScript: "SpecialGothicCondensedOne-Regular",
              note: "Newer, more character, single weight."),
        .init(label: "ARCHIVO NARROW (incumbent)", postScript: VaneFont.display,
              note: "What Vane ships today, chosen as a fallback for FF DIN Condensed and never revisited."),
    ]

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 34) {
                Text("DISPLAY FACE — 54° AT 180PT")
                    .font(.custom(VaneFont.mono, size: 12)).tracking(1.6)
                    .foregroundStyle(.secondary)

                ForEach(candidates) { candidate in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(candidate.label)
                            .font(.custom(VaneFont.mono, size: 11)).tracking(1.4)
                            .foregroundStyle(.secondary)

                        // The real figure, at the real size. Two digits and the ring, because
                        // that is what the screen shows and because numerals are where condensed
                        // faces differ most — a 4 with a closed counter reads very differently
                        // at 180pt than one with an open one.
                        Text("54°")
                            .font(font(candidate, size: 180))
                            .lineLimit(1).minimumScaleFactor(0.5)

                        // Every numeral, to catch a bad 1 or a 7 that collides.
                        Text("0123456789")
                            .font(font(candidate, size: 34))
                            .foregroundStyle(.secondary)

                        Text("MOSTLY CLOUDY")
                            .font(font(candidate, size: 26)).tracking(1.2)

                        Text(candidate.note)
                            .font(.system(.footnote))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Divider()
                }
            }
            .padding(24)
        }
    }

    /// Applies the variation axes where a face has them.
    ///
    /// SwiftUI's `.fontWeight()` does not reliably drive a variable font's `wght` axis for a
    /// custom face, and it cannot address `opsz` at all. Setting the axes on the descriptor is
    /// the only way to see what the family can actually do.
    private func font(_ candidate: Candidate, size: CGFloat) -> Font {
        guard candidate.weight != nil || candidate.opticalSize != nil else {
            return .custom(candidate.postScript, fixedSize: size)
        }
        var variations: [Int: CGFloat] = [:]
        // Four-character axis tags as big-endian integers, which is how CoreText keys them.
        if let weight = candidate.weight { variations[tag("wght")] = weight }
        if let optical = candidate.opticalSize { variations[tag("opsz")] = optical }

        let descriptor = CTFontDescriptorCreateWithAttributes([
            kCTFontNameAttribute: candidate.postScript,
            kCTFontVariationAttribute: variations,
        ] as CFDictionary)
        return Font(CTFontCreateWithFontDescriptor(descriptor, size, nil))
    }

    private func tag(_ string: String) -> Int {
        string.utf8.reduce(0) { $0 << 8 | Int($1) }
    }
}
