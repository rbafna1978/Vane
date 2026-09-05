import CoreText
import Foundation
import Testing

@testable import VaneUI

/// Font registration fails silently: `Font.custom` with a name iOS cannot resolve falls back to
/// the system face and renders something perfectly reasonable-looking. Since the display face is
/// the identity of this design, a silent fallback would ship a different app than the one
/// designed. These tests are the only thing standing between that and a release.
@Suite(.serialized)
struct FontRegistration {

    @Test func `display and mono faces resolve after registration`() {
        VaneFont.register()

        for name in [VaneFont.display, VaneFont.mono] {
            let font = CTFontCreateWithName(name as CFString, 24, nil)
            let resolved = CTFontCopyPostScriptName(font) as String
            #expect(
                resolved == name,
                "\(name) fell back to \(resolved) — the identity face is not loading"
            )
        }
    }

    @Test func `the font files are actually in the resource bundle`() {
        // A missing resource is the usual cause of the fallback above, and it is invisible
        // until someone looks at a screenshot and says "that looks like Helvetica".
        for name in [VaneFont.display, VaneFont.mono] {
            #expect(VaneFont.fontURL(for: name) != nil, "\(name) ttf missing from VaneUI resources")
        }
    }

    @Test func `registering twice does not break the second call`() {
        VaneFont.register()
        VaneFont.register()
        let font = CTFontCreateWithName(VaneFont.display as CFString, 24, nil)
        #expect(CTFontCopyPostScriptName(font) as String == VaneFont.display)
    }
}
