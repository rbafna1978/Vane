import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

/// Shown only when there is nothing cached at all. With a cache the screen shows the last
/// reading and says nothing — a failed refresh is not an event worth interrupting someone for.
///
/// Copy through `design:ux-copy`. Vocabulary is the product's own: a *station* is a place we
/// read from, a *reading* is what it produces. Same words as the station line at the top of the
/// screen, so people learn one set of terms rather than two.
struct EmptyStateView: View {
    let screen: WeatherModel.Screen
    let palette: Palette
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .vaneContextType()
                .foregroundStyle(palette.inkColor)
            Text(message)
                .font(.vaneBody)
                .foregroundStyle(palette.inkColor.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)

            Button(action: act) {
                Text(action)
                    .font(.vaneData).tracking(1.4)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 11)
                    .overlay(RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(palette.traceColor, lineWidth: 1))
            }
            .foregroundStyle(palette.traceColor)
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
    }

    private var title: String {
        switch screen {
        case .needsLocation, .content: "No station set."
        case .locationDenied: "Location is off."
        case .unreachable: "No connection."
        }
    }

    private var message: String {
        switch screen {
        case .needsLocation, .content:
            "A reading needs somewhere to be from. Allow location to set one."
        case .locationDenied:
            "Without it there is no station to read from. Turn on location in Settings."
        case .unreachable:
            // Says what happened, what to do, and that it is a one-time cost — after the first
            // reading the screen opens from cache with no network at all.
            "The first reading needs the network. After that this screen opens without one."
        }
    }

    private var action: String {
        switch screen {
        case .needsLocation, .content: "ALLOW LOCATION"
        case .locationDenied: "OPEN SETTINGS"
        case .unreachable: "TRY AGAIN"
        }
    }

    private func act() {
        #if canImport(UIKit)
        // The denied case is the one we cannot fix from inside the app; sending someone to
        // hunt through Settings themselves would be a dead end, which the spec forbids.
        if screen == .locationDenied,
           let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
            return
        }
        #endif
        retry()
    }
}
