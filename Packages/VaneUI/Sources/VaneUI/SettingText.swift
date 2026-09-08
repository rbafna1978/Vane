import SwiftUI

/// A sentence that sets itself, word by word.
///
/// **Gate.** Frequency is *rare* — this runs once per opening of the app, which is the tier
/// `find-animation-opportunities` reserves for delight. Purpose is delight, named honestly: the
/// sentence is the whole argument of the product, and it arriving as a line of type being set is
/// the one moment the app gets to have a personality.
///
/// It deliberately does **not** run on scrub. Re-setting the sentence every time the day changes
/// under a finger would move text somebody is reading, dozens of times inside one gesture, which
/// the same gate forbids. Scrubbing crossfades instead. One behaviour for the rare moment, a
/// quieter one for the frequent one.
struct SettingText: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let text: String
    /// 0 to 1. Words are revealed across this, not on a timer, so the whole sentence is a pure
    /// function of the entrance and inherits its interruptibility for free.
    let progress: Double

    private var words: [String] { text.split(separator: " ").map(String.init) }

    var body: some View {
        // The words are laid out by the real layout system and only *revealed* by progress, so
        // line breaks are final from the first frame. Animating the layout instead would make
        // the paragraph reflow under the reader as words arrive, which is the one thing text
        // must never do.
        WrappingWords(words: words) { index, word in
            Text(word)
                .opacity(reveal(index))
                .offset(y: (1 - reveal(index)) * 8)
                .blur(radius: (1 - reveal(index)) * 2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }

    private func reveal(_ index: Int) -> Double {
        guard !reduceMotion else { return 1 }
        // Overlapping windows: each word starts before the one before it has finished, so the
        // line reads as one movement passing along it rather than as words appearing in turn.
        let start = Double(index) * 0.055
        let raw = min(max((progress - start) / 0.34, 0), 1)
        return 1 - pow(1 - raw, 3)
    }
}

/// Lays words out in flowing lines, so each can be revealed on its own.
///
/// SwiftUI has no way to address the individual words inside a `Text`, and concatenating them
/// with `+` produces one run that can only be revealed as a whole. A `Layout` is the cheapest
/// correct answer: real line breaking, one subview per word.
struct WrappingWords<Content: View>: View {
    let words: [String]
    @ViewBuilder let content: (Int, String) -> Content

    var body: some View {
        FlowLayout {
            ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                content(index, word)
            }
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 7
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = arrange(subviews: subviews, width: width)
        let height = rows.reduce(0) { $0 + $1.height } + lineSpacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width == .infinity ? rows.map(\.width).max() ?? 0 : width,
                      height: height)
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        var y = bounds.minY
        for row in arrange(subviews: subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), anchor: .topLeading,
                                      proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let projected = row.width == 0 ? size.width : row.width + spacing + size.width
            if projected > width, !row.indices.isEmpty {
                rows.append(row)
                row = Row()
                row.indices = [index]
                row.width = size.width
                row.height = size.height
            } else {
                row.indices.append(index)
                row.width = projected
                row.height = max(row.height, size.height)
            }
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}
