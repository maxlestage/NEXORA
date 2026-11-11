import NexoraKit
import SwiftUI

/// Le centre d'aide : des réponses courtes, par thème, avec une recherche
/// (`ui/help/help_screen.dart`).
struct HelpView: View {
    /// Le titre d'un thème à ouvrir directement (ex. « Clés et modèles »).
    var initialSection: String?

    @State private var query = ""
    @State private var open: Set<String> = []

    var body: some View {
        let found = Help.search(query)
        let searching = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        List {
            Section {
                HStack(spacing: 12) {
                    Text("🧭").font(.system(size: 30))
                    Text("Toutes les réponses pour bien utiliser NEXORA : clés gratuites, crédit, Ollama, agents et GitHub.")
                        .font(.subheadline)
                }
                .padding(.vertical, 4)
            }
            if found.isEmpty {
                ContentUnavailableView("Aucune réponse : essayez un autre mot.", systemImage: "magnifyingglass")
            }
            ForEach(found, id: \.section.id) { entry in
                Section("\(entry.section.emoji)  \(entry.section.title)") {
                    ForEach(entry.topics) { t in
                        DisclosureGroup(isExpanded: binding(entry.section, t, searching: searching)) {
                            MarkdownView(text: t.answer)
                                .padding(.vertical, 6)
                        } label: {
                            Text(t.question).font(.body.weight(.semibold))
                        }
                    }
                }
            }
        }
        .searchable(text: $query, prompt: "Chercher (clé, ollama, limite, token…)")
        .navigationTitle("Aide et guides")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Le thème demandé s'ouvre sur sa première question.
            if let s = initialSection, let first = Help.sections.first(where: { $0.title == s })?.topics.first {
                open.insert(first.id)
            }
        }
    }

    /// Ouverte pendant une recherche, ou quand vous l'avez touchée.
    private func binding(_ s: HelpSection, _ t: HelpTopic, searching: Bool) -> Binding<Bool> {
        Binding(
            get: { searching || open.contains(t.id) },
            set: { on in
                if on { open.insert(t.id) } else { open.remove(t.id) }
            }
        )
    }
}

/// « Premiers pas » : quatre étapes pour tout découvrir, cochées automatiquement.
/// Disparaît une fois terminé ou masqué (`ui/help/getting_started.dart`).
struct GettingStartedCard: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(ChatStore.self) private var chats
    @Environment(GitHubSession.self) private var github
    @Environment(AgentLibrary.self) private var agents
    @Environment(AppNavigation.self) private var navigation: AppNavigation?
    @State private var hidden = false
    @State private var help = false

    private var steps: [GettingStartedStep] {
        GettingStartedStep.steps(
            hasChatted: chats.index.contains { $0.count > 0 },
            hasOwnKey: settings.providers.contains { $0.needsKey && settings.hasOwnKey($0.id) },
            githubConnected: github.connected,
            triedAgent: chats.index.contains { $0.agentId != nil } || !agents.custom.isEmpty
        )
    }

    var body: some View {
        // Masquée : rien à calculer (les clés se lisent dans le trousseau, à chaque
        // rendu de l'onglet Chat).
        let list: [GettingStartedStep] = hidden || settings.gettingStartedHidden ? [] : steps
        let done = list.filter(\.done).count
        if !list.isEmpty && done < list.count {
            GlassCard(glow: Theme.violet) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text("Premiers pas").font(.headline.weight(.heavy))
                        Text("\(done) / \(list.count)").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            help = true
                        } label: {
                            Image(systemName: "questionmark.circle")
                        }
                        .accessibilityLabel("Aide")
                        Button {
                            settings.gettingStartedHidden = true
                            hidden = true
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .accessibilityLabel("Masquer")
                    }
                    .buttonStyle(.borderless)
                    ProgressView(value: Double(done), total: Double(list.count))
                        .animation(.easeOut(duration: 0.6), value: done)
                    ForEach(list) { s in
                        Button {
                            if let tab = s.tab, !s.done { go(tab) }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: s.done ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(s.done ? Theme.green : .secondary)
                                    .contentTransition(.symbolEffect(.replace))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(s.title).font(.subheadline.weight(.bold)).strikethrough(s.done)
                                    Text(s.text).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if !s.done && s.tab != nil {
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(s.done || s.tab == nil)
                        .accessibilityValue(s.done ? "fait" : "à faire")
                    }
                }
            }
            .sheet(isPresented: $help) {
                NavigationStack {
                    HelpView()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) { Button("Fermer") { help = false } }
                        }
                }
            }
        }
    }

    private func go(_ tab: GettingStartedStep.Tab) {
        switch tab {
        case .agents: navigation?.tab = .agents
        case .github: navigation?.tab = .github
        case .models: navigation?.tab = .models
        }
    }
}

/// « Comment faire » d'un fournisseur : les étapes, l'offre gratuite et les astuces.
struct ProviderHelpSection: View {
    let provider: ProviderDef

    @Environment(SettingsStore.self) private var settings

    var body: some View {
        if let help = ProviderHelp.of(provider) {
            Section("Comment faire") {
                ForEach(Array(help.steps.enumerated()), id: \.offset) { i, step in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(i + 1)")
                            .font(.caption.weight(.heavy))
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(Theme.gradient(settings.accent), in: .circle)
                        Text(step).textSelection(.enabled)
                    }
                }
                Label {
                    Text(help.freeTier)
                } icon: {
                    Image(systemName: provider.free ? "gift" : "creditcard").foregroundStyle(provider.free ? Theme.green : Theme.amber)
                }
                ForEach(help.tips, id: \.self) { tip in
                    Label {
                        Text(tip)
                    } icon: {
                        Image(systemName: "lightbulb").foregroundStyle(.tint)
                    }
                }
                if let u = help.usageUrl.flatMap(URL.init(string:)) {
                    Link(destination: u) { Label("Consommation chez \(provider.name)", systemImage: "chart.bar") }
                }
            }
        }
    }
}
