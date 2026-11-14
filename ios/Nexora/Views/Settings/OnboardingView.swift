import NexoraKit
import SwiftUI

/// L'accueil au premier lancement (`ui/onboarding.dart`) : trois pages avec le logo
/// animé, un fond qui dérive, et des pages qui tournent en 3D.
struct OnboardingView: View {
    /// Textes et chiffres dans NexoraKit (`OnboardingDisplay`), testés sous Linux.
    private let pages = OnboardingDisplay.pages(
        providers: Catalog.providers.count,
        agents: Catalog.builtinAgents.count
    )

    @Environment(SettingsStore.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var page: Int? = 0
    @State private var tapped = 0

    private var current: Int { page ?? 0 }
    private var last: Bool { OnboardingDisplay.isLast(current, of: pages.count) }

    var body: some View {
        let motion = Motion(settings.animations, reduceMotion: reduceMotion)
        VStack(spacing: 0) {
            HStack {
                GradientText("NEXORA", font: .title3.weight(.black), tracking: 4)
                Spacer()
                // Inutile sur la dernière page : « Commencer » fait la même chose.
                if OnboardingDisplay.showsSkip(current, of: pages.count) {
                    Button("Passer") { settings.finishOnboarding() }
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
            }
            .frame(minHeight: 44)
            .padding(.horizontal, 20)
            .padding(.top, 8)

            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(pages.indices, id: \.self) { i in
                        pageView(pages[i], index: i)
                            .containerRelativeFrame(.horizontal)
                            .scrollTransition(axis: .horizontal) { content, phase in
                                // La page tourne en 3D en partant, et s'efface.
                                content
                                    .rotation3DEffect(
                                        .radians(motion.allowsMovement ? phase.value * 0.9 : 0),
                                        axis: (x: 0, y: 1, z: 0),
                                        anchor: phase.value > 0 ? .leading : .trailing,
                                        perspective: 0.6
                                    )
                                    .opacity(1 - abs(phase.value))
                            }
                            .id(i)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollIndicators(.hidden)
            .scrollPosition(id: $page)

            HStack(spacing: 6) {
                HStack(spacing: 6) {
                    ForEach(pages.indices, id: \.self) { i in
                        Capsule()
                            .fill(i == current ? AnyShapeStyle(Theme.gradient(settings.accent)) : AnyShapeStyle(Color.primary.opacity(0.2)))
                            .frame(width: i == current ? 26 : 8, height: 8)
                            .animation(.easeOut(duration: 0.3), value: current)
                    }
                }
                // VoiceOver lit « Page 2 sur 3 » au lieu de trois formes sans nom.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(OnboardingDisplay.progress(current, of: pages.count))
                Spacer()
                Button {
                    tapped += 1
                    if last {
                        settings.finishOnboarding()
                    } else {
                        withAnimation(.timingCurve(0.33, 1, 0.68, 1, duration: 0.52)) { page = current + 1 }
                    }
                } label: {
                    Label(OnboardingDisplay.primaryLabel(current, of: pages.count), systemImage: last ? "paperplane.fill" : "arrow.right")
                        .fontWeight(.bold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: 14))
            }
            .accessibilityElement(children: .contain)
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
        .auroraBackground(1.3)
        .sensoryFeedback(.impact(weight: .light), trigger: tapped) { _, _ in settings.haptics }
    }

    private func pageView(_ p: OnboardingDisplay.Page, index i: Int) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Plus petit en grands caractères : le texte reste visible sans défiler.
                NexusOrb(size: typeSize.isAccessibilitySize ? 120 : 240, satellites: 10 + i * 4, speed: 1 + Double(i) * 0.3)
                    .frame(maxWidth: .infinity)
                Text(p.eyebrow.uppercased())
                    .font(.subheadline.weight(.heavy))
                    .tracking(2)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text(p.title)
                    .accessibilityAddTraits(.isHeader)
                    .font(.largeTitle.weight(.black))
                    .tracking(-0.8)
                Text(p.text)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 6)
                ForEach(Array(p.points.enumerated()), id: \.offset) { k, point in
                    GlassCard(padding: 12) {
                        HStack(spacing: 12) {
                            Text(point.icon).font(.title2).accessibilityHidden(true)
                            Text(point.text)
                        }
                    }
                    .reveal(k)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
        }
    }
}
