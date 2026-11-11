import SwiftUI

// Les effets visuels de NEXORA (`ui/widgets/fx.dart`) : fond animé, verre dépoli,
// cartes inclinables, apparitions en cascade, texte en dégradé. Tous respectent le
// réglage d'animations (toutes, douces, aucune) et « Réduire les animations » d'iOS.

/// Un fond animé : trois halos colorés qui dérivent lentement (18 s par tour).
struct Aurora: View {
    var intensity: Double = 1

    @Environment(SettingsStore.self) private var settings
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let colors = Theme.palette(settings.accent).colors
        let dark = scheme == .dark
        let strength = intensity
        let still = Motion(rawValue: settings.animations) == .off || reduceMotion
        TimelineView(.animation(minimumInterval: 1 / 30, paused: still)) { timeline in
            let v = still ? 0 : timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 18) / 18
            Canvas { ctx, size in
                let a = v * .pi * 2
                let blobs: [(Color, CGPoint)] = [
                    (colors[1], CGPoint(x: 0.2 + 0.15 * sin(a), y: 0.15 + 0.1 * cos(a))),
                    (colors[0], CGPoint(x: 0.85 + 0.1 * cos(a * 1.3), y: 0.3 + 0.12 * sin(a))),
                    (colors[2], CGPoint(x: 0.5 + 0.2 * sin(a * 0.7), y: 0.9 + 0.08 * cos(a))),
                ]
                let r = min(size.width, size.height) * 0.75
                for (color, pos) in blobs {
                    let center = CGPoint(x: pos.x * size.width, y: pos.y * size.height)
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)),
                        with: .radialGradient(
                            Gradient(colors: [color.opacity(min(1, (dark ? 0.22 : 0.12) * strength)), .clear]),
                            center: center, startRadius: 0, endRadius: r
                        )
                    )
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Un texte rempli du dégradé NEXORA.
struct GradientText: View {
    let text: String
    var font: Font = .title2.weight(.black)
    var tracking: CGFloat = 0

    @Environment(SettingsStore.self) private var settings

    init(_ text: String, font: Font = .title2.weight(.black), tracking: CGFloat = 0) {
        self.text = text
        self.font = font
        self.tracking = tracking
    }

    var body: some View {
        Text(text)
            .font(font)
            .tracking(tracking)
            .foregroundStyle(Theme.gradient(settings.accent))
    }
}

/// Une carte en verre dépoli, avec une bordure lumineuse (`Glass`).
struct GlassCard<Content: View>: View {
    var glow: Color?
    var radius: CGFloat = 22
    var padding: CGFloat = 16
    var action: (() -> Void)?
    @ViewBuilder let content: Content

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if let action {
            Button(action: action) { card }
                .buttonStyle(GlassPressStyle())
        } else {
            card
        }
    }

    private var card: some View {
        let dark = scheme == .dark
        return content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(dark ? Color.white.opacity(0.045) : Color.white.opacity(0.75), in: .rect(cornerRadius: radius))
            .background(.ultraThinMaterial, in: .rect(cornerRadius: radius))
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder((glow ?? (dark ? .white : .black)).opacity(glow != nil ? 0.45 : 0.08), lineWidth: 1)
            )
            .contentShape(.rect(cornerRadius: radius))
    }
}

/// Le toucher d'une carte en verre : légèrement assombrie.
private struct GlassPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.primary)
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

/// Une carte qui s'incline en 3D sous le doigt et revient en douceur (`Tilt3D`).
private struct Tilt3D: ViewModifier {
    var maxAngle: Double

    @Environment(SettingsStore.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tilt: CGSize = .zero
    @State private var size: CGSize = CGSize(width: 300, height: 200)

    func body(content: Content) -> some View {
        if Motion(settings.animations, reduceMotion: reduceMotion).allowsMovement {
            content
                .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
                .rotation3DEffect(.radians(-tilt.height * maxAngle), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
                .rotation3DEffect(.radians(tilt.width * maxAngle), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
                .animation(.easeOut(duration: 0.22), value: tilt)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            let w = max(size.width, 1), h = max(size.height, 1)
                            tilt = CGSize(
                                width: min(max((v.location.x / w - 0.5) * 2, -1), 1),
                                height: min(max((v.location.y / h - 0.5) * 2, -1), 1)
                            )
                        }
                        .onEnded { _ in tilt = .zero }
                )
        } else {
            content
        }
    }
}

/// Fait apparaître une vue en glissant, avec un délai (listes en cascade, `Reveal`).
private struct Reveal: ViewModifier {
    var index: Int
    var dy: CGFloat

    @Environment(SettingsStore.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        let motion = Motion(settings.animations, reduceMotion: reduceMotion)
        if motion.isOff {
            content
        } else {
            // Animations douces : un simple fondu, sans mouvement.
            let move = motion.allowsMovement
            content
                .opacity(shown ? 1 : 0)
                .offset(y: shown || !move ? 0 : dy)
                .rotation3DEffect(.radians(shown || !move ? 0 : 0.35), axis: (x: 1, y: 0, z: 0), anchor: .bottom, perspective: 0.5)
                .onAppear {
                    let delay = Double(min(max(index, 0), 12)) * 0.045
                    withAnimation(.timingCurve(0.33, 1, 0.68, 1, duration: 0.42).delay(delay)) { shown = true }
                }
        }
    }
}

extension View {
    /// Incline la vue en 3D sous le doigt.
    func tilt3D(_ maxAngle: Double = 0.18) -> some View { modifier(Tilt3D(maxAngle: maxAngle)) }

    /// Fait apparaître la vue en glissant, après les `index` précédentes.
    func reveal(_ index: Int = 0, dy: CGFloat = 24) -> some View { modifier(Reveal(index: index, dy: dy)) }

    /// Le fond animé de NEXORA derrière la vue.
    func auroraBackground(_ intensity: Double = 1) -> some View {
        background { Aurora(intensity: intensity) }
    }
}

/// Une pastille ronde avec un emoji, sur fond coloré.
struct EmojiAvatar: View {
    let emoji: String
    var color: Color = Theme.violet
    var size: CGFloat = 44

    init(_ emoji: String, color: Color = Theme.violet, size: CGFloat = 44) {
        self.emoji = emoji
        self.color = color
        self.size = size
    }

    var body: some View {
        Text(emoji)
            .font(.system(size: size * 0.48))
            .frame(width: size, height: size)
            .background(
                Circle().fill(RadialGradient(colors: [color.opacity(0.45), color.opacity(0.12)], center: .center, startRadius: 0, endRadius: size / 2))
            )
            .overlay(Circle().strokeBorder(color.opacity(0.5), lineWidth: 1))
            .accessibilityHidden(true)
    }
}

/// Un en-tête de section : en capitales, espacé, dans la couleur principale.
struct SectionTitle<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(.caption.weight(.heavy))
                .tracking(1.4)
                .foregroundStyle(.tint)
                .lineLimit(1)
            Spacer()
            trailing
        }
        .padding(.horizontal, 4)
        .padding(.top, 20)
        .padding(.bottom, 10)
    }
}

extension SectionTitle where Trailing == EmptyView {
    init(_ title: String) {
        self.title = title
        trailing = EmptyView()
    }
}

/// Un message bref en bas de l'écran (« Copié », « Réglages importés »).
struct Toast: Equatable {
    var text: String
    var error = false
}

private struct ToastModifier: ViewModifier {
    @Binding var toast: Toast?

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let toast {
                Text(toast.text)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(toast.error ? Theme.red.opacity(0.95) : Color.black.opacity(0.85), in: .rect(cornerRadius: 14))
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: toast) {
                        try? await Task.sleep(for: .seconds(2.2))
                        withAnimation { self.toast = nil }
                    }
                    .accessibilityAddTraits(.isStaticText)
            }
        }
        .animation(.easeOut(duration: 0.2), value: toast)
    }
}

extension View {
    /// Affiche `toast` quelques secondes en bas de la vue.
    func toast(_ toast: Binding<Toast?>) -> some View { modifier(ToastModifier(toast: toast)) }
}
