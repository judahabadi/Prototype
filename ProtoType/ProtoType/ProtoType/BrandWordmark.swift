import SwiftUI
import CoreText

/// Inter is bundled (Fonts/Inter-*.ttf) and registered at runtime because the
/// app target uses a generated Info.plist (no UIAppFonts key available).
enum BrandFont {
    private static let registerOnce: Void = {
        for name in ["Inter-Bold", "Inter-Regular"] {
            if let url = Bundle.main.url(forResource: name, withExtension: "ttf") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }()

    static func bold(_ size: CGFloat) -> Font {
        _ = registerOnce
        return .custom("Inter-Bold", fixedSize: size)
    }

    static func regular(_ size: CGFloat) -> Font {
        _ = registerOnce
        return .custom("Inter-Regular", fixedSize: size)
    }
}

enum BrandColor {
    static let navy = Color(red: 0x1E / 255, green: 0x3C / 255, blue: 0x78 / 255)
    static let green = Color(red: 0x30 / 255, green: 0xD1 / 255, blue: 0x58 / 255)
}

/// The P-mark + Proto(Type) logotype lockup — navy ink (white in dark mode),
/// bold Inter letters, regular-weight green parens, −0.02em tracking.
struct BrandWordmark: View {
    var markSize: CGFloat = 44
    var fontSize: CGFloat = 44
    @Environment(\.colorScheme) private var colorScheme

    private var ink: Color { colorScheme == .dark ? .white : BrandColor.navy }

    var body: some View {
        HStack(spacing: markSize * 13 / 44) {
            PMark(size: markSize, ink: ink)
            logotype
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    private var logotype: Text {
        let tracking = fontSize * -0.02
        return Text("Proto").font(BrandFont.bold(fontSize)).foregroundStyle(ink).tracking(tracking)
            + Text("(").font(BrandFont.regular(fontSize)).foregroundStyle(BrandColor.green).tracking(tracking)
            + Text("Type").font(BrandFont.bold(fontSize)).foregroundStyle(ink).tracking(tracking)
            + Text(")").font(BrandFont.regular(fontSize)).foregroundStyle(BrandColor.green)
    }
}

/// Abstract "P" — vertical stem + circular bowl, proportions from the brand spec.
private struct PMark: View {
    let size: CGFloat
    let ink: Color

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: size * 3 / 44)
                .fill(ink)
                .frame(width: size * 0.15, height: size * 0.84)
                .offset(x: size * 0.21, y: size * 0.08)
            Circle()
                .fill(ink)
                .frame(width: size * 0.50, height: size * 0.50)
                .offset(x: size * 0.40, y: size * 0.09)
        }
        .frame(width: size, height: size, alignment: .topLeading)
    }
}

#Preview {
    VStack(spacing: 40) {
        BrandWordmark()
        BrandWordmark(markSize: 40, fontSize: 40)
    }
}
