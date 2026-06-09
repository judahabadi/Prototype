import XCTest
import SwiftUI
import UIKit
@testable import ProtoType

/// Renders the QuickType bar (`ChipToolbar`) across typing states, widths, and
/// light/dark, and attaches each as a PNG. CI exports these attachments so the
/// bar's height/centering/layout can be inspected without a device.
final class BarSnapshotTests: XCTestCase {

    @MainActor
    func testBarSnapshots() {
        let states: [(name: String, suggestions: [BarSuggestion])] = [
            ("typing", [
                BarSuggestion(text: "\u{201C}Testin\u{201D}"),
                BarSuggestion(text: "Testing", subtitle: "Probando", isAutocorrect: true),
                BarSuggestion(text: "Tester", subtitle: "Probador")
            ]),
            ("nextword", [
                BarSuggestion(text: "the", subtitle: "el"),
                BarSuggestion(text: "a", subtitle: "un"),
                BarSuggestion(text: "to", subtitle: "a")
            ]),
            ("longword", [
                BarSuggestion(text: "internationalization", subtitle: "internacionalización"),
                BarSuggestion(text: "the", subtitle: "el"),
                BarSuggestion(text: "and", subtitle: "y")
            ])
        ]
        let widths: [CGFloat] = [320, 393, 430]   // SE, standard, Pro Max (points)

        for state in states {
            for width in widths {
                for scheme in [ColorScheme.light, ColorScheme.dark] {
                    let bar = ChipToolbar(suggestions: state.suggestions, targetFlag: "\u{1F1EA}\u{1F1F8}")
                        .frame(width: width, height: ChipToolbar.barHeight)
                        .background(Color(uiColor: .secondarySystemBackground))
                        .environment(\.colorScheme, scheme)

                    let renderer = ImageRenderer(content: bar)
                    renderer.scale = 3
                    guard let image = renderer.uiImage, let data = image.pngData() else {
                        XCTFail("Failed to render \(state.name) w\(Int(width)) \(scheme)")
                        continue
                    }
                    let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
                    attachment.name = "bar_\(state.name)_w\(Int(width))_\(scheme == .dark ? "dark" : "light").png"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                }
            }
        }
    }
}
