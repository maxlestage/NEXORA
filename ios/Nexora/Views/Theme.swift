import NexoraKit
import SwiftUI
import UIKit

/// Les couleurs de NEXORA (mêmes jeux de couleurs que l'app Flutter, `ui/theme.dart`).
enum Theme {
    static let cyan = Color(hex: 0x22D3EE)
    static let violet = Color(hex: 0x8B5CF6)
    static let magenta = Color(hex: 0xF472B6)
    static let green = Color(hex: 0x34D399)
    static let amber = Color(hex: 0xFBBF24)
    static let red = Color(hex: 0xF87171)
    /// Le fond sombre de NEXORA, et ses panneaux.
    static let ink = Color(hex: 0x07070D)
    static let panel = Color(hex: 0x10101A)
    static let panel2 = Color(hex: 0x171726)

    /// Un jeu de couleurs : la principale, puis celles du dégradé, et la principale
    /// en thème clair (plus foncée, pour le contraste).
    struct Palette: Identifiable {
        let id: Int
        let name: String
        let colors: [Color]
        let lightPrimary: Color
    }

    static let palettes: [Palette] = [
        Palette(id: 0, name: "Néon", colors: [cyan, violet, magenta], lightPrimary: Color(hex: 0x0E7490)),
        Palette(id: 1, name: "Océan", colors: [Color(hex: 0x38BDF8), Color(hex: 0x2563EB), Color(hex: 0x14B8A6)], lightPrimary: Color(hex: 0x1D4ED8)),
        Palette(id: 2, name: "Aurore", colors: [Color(hex: 0x34D399), Color(hex: 0x22D3EE), Color(hex: 0xA78BFA)], lightPrimary: Color(hex: 0x047857)),
        Palette(id: 3, name: "Coucher de soleil", colors: [Color(hex: 0xFB923C), Color(hex: 0xF43F5E), Color(hex: 0xA855F7)], lightPrimary: Color(hex: 0xC2410C)),
        Palette(id: 4, name: "Rubis", colors: [Color(hex: 0xF87171), Color(hex: 0xEC4899), Color(hex: 0xF59E0B)], lightPrimary: Color(hex: 0xBE123C)),
        Palette(id: 5, name: "Forêt", colors: [Color(hex: 0x84CC16), Color(hex: 0x10B981), Color(hex: 0x0EA5E9)], lightPrimary: Color(hex: 0x4D7C0F)),
        Palette(id: 6, name: "Or", colors: [Color(hex: 0xFBBF24), Color(hex: 0xF97316), Color(hex: 0xFB7185)], lightPrimary: Color(hex: 0xB45309)),
        Palette(id: 7, name: "Monochrome", colors: [Color(hex: 0xE5E7EB), Color(hex: 0x9CA3AF), Color(hex: 0xF9FAFB)], lightPrimary: Color(hex: 0x374151)),
    ]

    static func palette(_ i: Int) -> Palette { palettes.indices.contains(i) ? palettes[i] : palettes[0] }

    /// La couleur principale du jeu choisi : vive en thème sombre, plus foncée en
    /// thème clair.
    static func accent(_ i: Int) -> Color {
        let p = palette(i)
        let dark = UIColor(p.colors[0])
        let light = UIColor(p.lightPrimary)
        return Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }

    static func gradient(_ i: Int) -> LinearGradient {
        LinearGradient(colors: palette(i).colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Le fond des écrans NEXORA : noir pur (OLED) ou encre en thème sombre.
    static func background(dark: Bool, oled: Bool) -> Color {
        dark ? (oled ? .black : ink) : Color(hex: 0xF7F7FB)
    }

    static func color(_ p: ProviderDef) -> Color { Color(argb: p.color) }

    /// La couleur d'un type de changement (Nouveautés).
    static func color(_ k: ChangeKind) -> Color {
        switch k {
        case .nouveau: green
        case .ameliore: violet
        case .corrige: amber
        }
    }

    static func symbol(_ k: ChangeKind) -> String {
        switch k {
        case .nouveau: "plus.circle"
        case .ameliore: "chart.line.uptrend.xyaxis"
        case .corrige: "wrench.and.screwdriver"
        }
    }
}

/// Le niveau d'animation choisi (Personnaliser → Animations), combiné avec
/// « Réduire les animations » d'iOS.
enum Motion: String {
    case full, reduced, off

    init(_ setting: String, reduceMotion: Bool) {
        let m = Motion(rawValue: setting) ?? .full
        // iOS demande moins de mouvement : au plus des animations douces.
        self = reduceMotion && m == .full ? .reduced : m
    }

    /// La vitesse des animations continues (orbe, fonds) : 1, 0,25 ou 0.
    var speed: Double {
        switch self {
        case .full: 1
        case .reduced: 0.25
        case .off: 0
        }
    }

    var isOff: Bool { self == .off }
    /// Les effets de mouvement (inclinaison 3D, apparitions en cascade).
    var allowsMovement: Bool { self == .full }
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
    var systemImage: String?

    var body: some View {
        HStack(spacing: 3) {
            if let systemImage { Image(systemName: systemImage).font(.system(size: 9, weight: .bold)) }
            Text(text)
        }
        .font(.caption2.weight(.semibold))
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .foregroundStyle(color)
        .background(color.opacity(0.14), in: .capsule)
        .overlay(Capsule().strokeBorder(color.opacity(0.4), lineWidth: 0.5))
    }
}

extension Double {
    /// Un montant en dollars lisible (« 0,0012 $ »), comme dans l'app Flutter.
    var dollars: String { ChatDisplay.cost(self) }
}
