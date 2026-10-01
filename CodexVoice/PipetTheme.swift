import AppKit
import SwiftUI

enum PipetTheme {
    static let background = adaptive(light: 0xF6F2EA, dark: 0x252321)
    static let surface = adaptive(light: 0xFDFBF6, dark: 0x302D2A)
    static let inset = adaptive(light: 0xEEE8DF, dark: 0x393530)
    static let ink = adaptive(light: 0x3A3730, dark: 0xF6F2EA)
    static let secondary = adaptive(light: 0x6B6559, dark: 0xC5BDB0)
    static let accent = adaptive(light: 0xA94428, dark: 0xFFAF8D)
    static let softAccent = adaptive(light: 0xFBE0D3, dark: 0x4A332B)
    static let rule = adaptive(light: 0xD9CFC1, dark: 0x655C51)
    static let success = adaptive(light: 0x32654D, dark: 0xA1D5B6)

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255, alpha: 1)
        })
    }
}

struct PipetCard<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        content.padding(18)
            .background(PipetTheme.surface, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(PipetTheme.rule.opacity(0.65), lineWidth: 1))
    }
}

struct PipetLogo: View {
    var size: CGFloat = 80
    var body: some View {
        if let url = Bundle.main.url(forResource: "PipetLogo", withExtension: "png"), let image = NSImage(contentsOf: url) {
            Image(nsImage: image).resizable().scaledToFit().frame(width: size, height: size).accessibilityHidden(true)
        } else {
            Image(systemName: "bubble.left.and.text.bubble.right.fill").font(.system(size: size * 0.6)).foregroundStyle(PipetTheme.accent).frame(width: size, height: size).accessibilityHidden(true)
        }
    }
}

struct ShortcutKeys: View {
    var body: some View {
        HStack(spacing: 6) {
            key("⌃", label: "Control")
            Text("+").foregroundStyle(PipetTheme.secondary)
            key("M", label: "M")
        }.accessibilityElement(children: .ignore).accessibilityLabel("Hold Control M to dictate")
    }
    private func key(_ text: String, label: String) -> some View {
        Text(text).font(.system(size: 17, weight: .semibold, design: .rounded))
            .frame(width: 38, height: 34)
            .background(PipetTheme.surface, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(PipetTheme.rule, lineWidth: 1))
    }
}
