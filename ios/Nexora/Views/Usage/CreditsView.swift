import NexoraKit
import SwiftUI
import UIKit

/// Les crédits de l'application (Réglages → Crédits). À pousser dans une pile de
/// navigation.
struct CreditsView: View {
    /// Le créateur de l'application, affiché dans les crédits et les licences.
    static let appAuthor = "Maxime Nathan Lestage"

    @Environment(SettingsStore.self) private var settings

    private let builtWith: [(String, String)] = [
        ("Swift et SwiftUI", "L'application iPhone et iPad"),
        ("Flutter et Dart", "L'application Android"),
        ("Paquets 📦", "Le site de présentation, en Rust et WebAssembly"),
        ("GitHub Actions", "Tests, fusion automatique, TestFlight, Pages, Heroku"),
    ]

    private let frameworks: [(String, String)] = [
        ("Foundation · Observation", "Appels aux fournisseurs et à GitHub, état de l'application"),
        ("Security", "Clés dans le trousseau de l'appareil"),
        ("SwiftUI", "Interface et affichage des réponses"),
        ("Speech · AVFoundation", "Dictée et lecture à voix haute"),
    ]

    /// Tirés des catalogues livrés : la liste reste juste quand un fournisseur s'ajoute.
    private var services: [(String, String)] {
        let providers = Catalog.providers.map(\.name)
        return [
            (CreditsDisplay.providersTitle(providers), CreditsDisplay.providersDetail(providers)),
            ("Agents cloud", CreditsDisplay.cloudAgentsDetail(Catalog.cloudAgents.map(\.name))),
            (
                "Catalogues d'agents",
                "wshobson/agents, VoltAgent/awesome-claude-code-subagents, 0xfurai/claude-code-subagents, iannuttall/claude-agents"
            ),
        ]
    }

    @State private var toast: Toast?
    @State private var copied = 0

    var body: some View {
        List {
            Section {
                VStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 64))
                        .foregroundStyle(Theme.gradient(settings.accent))
                        .padding(.top, 8)
                        .accessibilityHidden(true)
                    Text("NEXORA")
                        .font(.system(size: 30, weight: .black))
                        .tracking(8)
                        .foregroundStyle(Theme.gradient(settings.accent))
                        .accessibilityAddTraits(.isHeader)
                    Button(action: copyVersion) {
                        Label("Version \(SettingsStore.appVersion)", systemImage: "doc.on.doc")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(minHeight: 44)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Copie le numéro de version")
                    Text("Conception, design et développement")
                        .font(.subheadline.weight(.heavy))
                        .tracking(1.2)
                        .foregroundStyle(Theme.accent(settings.accent))
                        .padding(.top, 12)
                    Text(Self.appAuthor)
                        .font(.title2.weight(.black))
                    Text("Application mobile, site de présentation, agents et intégrations GitHub.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            group("Fabriqué avec", builtWith)
            group("Bibliothèques", frameworks)
            group("Services utilisés", services)

            Section {
                Link(destination: URL(string: "https://github.com/maxlestage/NEXORA")!) {
                    Label("Code source", systemImage: "chevron.left.forwardslash.chevron.right")
                }
            } footer: {
                VStack(spacing: 14) {
                    Text("Les noms et marques des fournisseurs appartiennent à leurs propriétaires respectifs. NEXORA n'est affilié à aucun d'eux.")
                    Text("© 2026 \(Self.appAuthor)")
                        .font(.footnote.weight(.bold))
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
            }
        }
        .navigationTitle("Crédits")
        .navigationBarTitleDisplayMode(.inline)
        .toast($toast)
        .sensoryFeedback(.success, trigger: copied) { _, _ in settings.haptics }
    }

    private func copyVersion() {
        UIPasteboard.general.string = CreditsDisplay.versionText(SettingsStore.appVersion)
        copied += 1
        toast = Toast(text: CreditsDisplay.versionCopied(SettingsStore.appVersion))
    }

    private func group(_ title: String, _ items: [(String, String)]) -> some View {
        Section(title) {
            ForEach(items, id: \.0) { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.0).fontWeight(.bold)
                    Text(item.1).font(.caption).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(CreditsDisplay.rowAccessibility(item.0, item.1))
            }
        }
    }
}
