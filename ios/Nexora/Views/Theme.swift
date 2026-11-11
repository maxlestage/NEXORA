import NexoraKit
import SwiftUI

/// Les couleurs de NEXORA (mêmes jeux de couleurs que l'app Flutter).
enum Theme {
    static let cyan = Color(hex: 0x22D3EE)
    static let violet = Color(hex: 0x8B5CF6)
    static let magenta = Color(hex: 0xF472B6)
    static let green = Color(hex: 0x34D399)
    static let amber = Color(hex: 0xFBBF24)
    static let red = Color(hex: 0xF87171)

    struct Palette: Identifiable {
        let id: Int
        let name: String
        let colors: [Color]
    }

    static let palettes: [Palette] = [
        Palette(id: 0, name: "Néon", colors: [cyan, violet, magenta]),
        Palette(id: 1, name: "Océan", colors: [Color(hex: 0x38BDF8), Color(hex: 0x2563EB), Color(hex: 0x14B8A6)]),
        Palette(id: 2, name: "Aurore", colors: [Color(hex: 0x34D399), Color(hex: 0x22D3EE), Color(hex: 0xA78BFA)]),
        Palette(id: 3, name: "Coucher de soleil", colors: [Color(hex: 0xFB923C), Color(hex: 0xF43F5E), Color(hex: 0xA855F7)]),
        Palette(id: 4, name: "Rubis", colors: [Color(hex: 0xF87171), Color(hex: 0xEC4899), Color(hex: 0xF59E0B)]),
        Palette(id: 5, name: "Forêt", colors: [Color(hex: 0x84CC16), Color(hex: 0x10B981), Color(hex: 0x06B6D4)]),
    ]

    static func palette(_ i: Int) -> Palette { palettes.indices.contains(i) ? palettes[i] : palettes[0] }

    static func accent(_ i: Int) -> Color { palette(i).colors[0] }

    static func gradient(_ i: Int) -> LinearGradient {
        LinearGradient(colors: palette(i).colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static func color(_ p: ProviderDef) -> Color { Color(argb: p.color) }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    init(argb: UInt32) {
        self.init(hex: argb & 0xFFFFFF)
    }
}

/// La pastille d'un fournisseur (emoji sur sa couleur).
struct ProviderBadge: View {
    let provider: ProviderDef
    var size: CGFloat = 32

    var body: some View {
        Text(provider.emoji)
            .font(.system(size: size * 0.55))
            .frame(width: size, height: size)
            .background(Theme.color(provider).opacity(0.18), in: .rect(cornerRadius: size * 0.3))
            .accessibilityHidden(true)
    }
}

/// Un petit badge texte (« Gratuit », « Local »…).
struct Pill: View {
    let text: String
    var color: Color = .accentColor

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(color)
            .background(color.opacity(0.15), in: .capsule)
    }
}

extension Double {
    /// Un montant en dollars lisible (« 0,0012 $ »).
    var dollars: String {
        let format = self < 0.01 ? "%.4f" : "%.2f"
        return String(format: format, self).replacingOccurrences(of: ".", with: ",") + " $"
    }
}
