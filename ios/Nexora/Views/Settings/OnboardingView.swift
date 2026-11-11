import SwiftUI

/// L'accueil au premier lancement (`ui/onboarding.dart`) : trois pages avec le logo
/// animé, un fond qui dérive, et des pages qui tournent en 3D.
struct OnboardingView: View {
    private struct Page {
        let eyebrow, title, text: String
        let points: [(String, String)]
    }

    private let pages: [Page] = [
        Page(
            eyebrow: "Bienvenue",
            title: "Tous les modèles d'IA,\ndans votre poche.",
            text: "NEXORA réunit plus de 20 fournisseurs : des modèles gratuits, vos modèles Ollama locaux, et les meilleurs modèles du marché.",
            points: [
                ("🌸", "Pollinations : gratuit, sans clé, prêt tout de suite"),
                ("🦙", "Ollama sur votre ordinateur, via le Wi-Fi"),
                ("⚡", "Groq, Gemini, Mistral, OpenRouter… offres gratuites"),
            ]
        ),
        Page(
            eyebrow: "Agents",
            title: "Des agents qui\ntravaillent pour vous.",
            text: "Choisissez un expert, installez des agents depuis GitHub, ou laissez un agent autonome modifier votre code puis ouvrir une pull request.",
            points: [
                ("🤖", "14 agents intégrés, et les vôtres"),
                ("📥", "Installation depuis n'importe quel dépôt GitHub"),
                ("☁️", "Claude Code, Gemini CLI, Codex, Aider sur GitHub Actions"),
            ]
        ),
        Page(
            eyebrow: "GitHub",
            title: "Hébergez et codez\ndepuis votre téléphone.",
            text: "Connectez GitHub : créez des dépôts, éditez vos fichiers, faites des commits, gérez issues, pull requests et workflows.",
            points: [
                ("🐙", "Connexion sécurisée, jeton dans le trousseau"),
                ("✍️", "Éditeur de code et commits multi-fichiers"),
                ("🚀", "Lancez vos workflows avec une instruction"),
            ]
        ),
    ]

    @Environment(SettingsStore.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page: Int? = 0
    @State private var tapped = 0

    private var current: Int { page ?? 0 }
    private var last: Bool { current >= pages.count - 1 }

    var body: some View {
        let motion = Motion(settings.animations, reduceMotion: reduceMotion)
        VStack(spacing: 0) {
            HStack {
                GradientText("NEXORA", font: .title3.weight(.black), tracking: 4)
                Spacer()
                Button("Passer") { settings.finishOnboarding() }
            }
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
                ForEach(pages.indices, id: \.self) { i in
                    Capsule()
                        .fill(i == current ? AnyShapeStyle(Theme.gradient(settings.accent)) : AnyShapeStyle(Color.primary.opacity(0.2)))
                        .frame(width: i == current ? 26 : 8, height: 8)
                        .animation(.easeOut(duration: 0.3), value: current)
                }
                Spacer()
                Button {
                    tapped += 1
                    if last {
                        settings.finishOnboarding()
                    } else {
                        withAnimation(.timingCurve(0.33, 1, 0.68, 1, duration: 0.52)) { page = current + 1 }
                    }
                } label: {
                    Label(last ? "Commencer gratuitement" : "Suivant", systemImage: last ? "paperplane.fill" : "arrow.right")
                        .fontWeight(.bold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
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

    private func pageView(_ p: Page, index i: Int) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                NexusOrb(size: 240, satellites: 10 + i * 4, speed: 1 + Double(i) * 0.3)
                    .frame(maxWidth: .infinity)
                Text(p.eyebrow.uppercased())
                    .font(.subheadline.weight(.heavy))
                    .tracking(2)
                    .foregroundStyle(.tint)
                Text(p.title)
                    .font(.largeTitle.weight(.black))
                    .tracking(-0.8)
                Text(p.text)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 6)
                ForEach(Array(p.points.enumerated()), id: \.offset) { k, point in
                    GlassCard(padding: 12) {
                        HStack(spacing: 12) {
                            Text(point.0).font(.title2)
                            Text(point.1)
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
