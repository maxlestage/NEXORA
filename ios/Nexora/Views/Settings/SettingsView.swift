import NexoraKit
import SwiftUI

/// Les réglages : modèle et effort par défaut, mémoire, personnalisation, voix,
/// apparence, données, nouveautés.
struct SettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(ChatStore.self) private var chats
    @State private var pickModel = false
    @State private var confirmDelete = false
    @State private var confirmReset = false

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                Section("Réponses") {
                    Button {
                        pickModel = true
                    } label: {
                        LabeledContent("Modèle par défaut", value: settings.resolve(nil).model)
                    }
                    Picker("Effort par défaut", selection: $settings.defaultLevel) {
                        ForEach(ThinkLevel.allCases) { l in
                            Text("\(l.emoji) \(l.label)").tag(l)
                        }
                    }
                    Text(settings.defaultLevel.summary).font(.caption).foregroundStyle(.secondary)
                    Picker("Mémoire de la conversation", selection: $settings.contextTokens) {
                        Text("8 000 tokens").tag(8000)
                        Text("32 000 tokens").tag(32000)
                        Text("128 000 tokens").tag(128_000)
                        Text("Tout").tag(0)
                    }
                    Toggle("Température personnalisée", isOn: $settings.useTemperature)
                    if settings.useTemperature {
                        VStack(alignment: .leading) {
                            Slider(value: $settings.temperature, in: 0...2, step: 0.1)
                            Text("Température : \(settings.temperature, specifier: "%.1f") (bas = précis, haut = créatif)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Toggle("Afficher le raisonnement", isOn: $settings.showThinking)
                }

                Section {
                    NavigationLink("Personnaliser l'assistant") { PersonalizeView() }
                }

                Section("Voix et sensations") {
                    Toggle("Lire les réponses à voix haute", isOn: $settings.speakReplies)
                    Toggle("Retours haptiques", isOn: $settings.haptics)
                }

                Section("Apparence") {
                    Picker("Thème", selection: $settings.theme) {
                        Text("Système").tag("system")
                        Text("Clair").tag("light")
                        Text("Sombre").tag("dark")
                    }
                    Picker("Couleurs", selection: $settings.accent) {
                        ForEach(Theme.palettes) { p in
                            HStack {
                                Circle().fill(LinearGradient(colors: p.colors, startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: 18, height: 18)
                                Text(p.name)
                            }
                            .tag(p.id)
                        }
                    }
                }

                Section("Données") {
                    LabeledContent("Conversations", value: "\(chats.index.count)")
                    Button("Supprimer toutes les conversations", role: .destructive) { confirmDelete = true }
                    Button("Tout réinitialiser (réglages et clés)", role: .destructive) { confirmReset = true }
                }

                Section("À propos") {
                    NavigationLink("Nouveautés") { WhatsNewView() }
                    LabeledContent("Version", value: SettingsStore.appVersion)
                    Link("Le site de NEXORA", destination: URL(string: "https://maxlestage.github.io/NEXORA/")!)
                    Link("Code source sur GitHub", destination: URL(string: "https://github.com/maxlestage/NEXORA")!)
                    Button("Revoir la présentation") { settings.onboarded = false }
                }
            }
            .navigationTitle("Réglages")
            .sheet(isPresented: $pickModel) {
                ModelPickerSheet(selected: settings.resolve(nil)) { settings.defaultModel = $0.key }
            }
            .confirmationDialog("Supprimer toutes les conversations ?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Supprimer", role: .destructive) { chats.deleteAll() }
            }
            .confirmationDialog("Tout réinitialiser ?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Réinitialiser", role: .destructive) {
                    settings.resetAll()
                    chats.deleteAll()
                }
            } message: {
                Text("Les réglages, les clés d'API et le jeton GitHub seront effacés de cet iPhone.")
            }
        }
    }
}

/// Le nom de l'assistant et vos instructions personnelles.
struct PersonalizeView: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section("Nom de l'assistant") {
                TextField("NEXORA", text: $settings.assistantName)
            }
            Section {
                Toggle("Utiliser mes instructions", isOn: $settings.customInstructions)
            }
            Section {
                TextEditor(text: $settings.aboutMe).frame(minHeight: 100)
            } header: {
                Text("À propos de vous")
            } footer: {
                Text("Métier, centres d'intérêt, langages préférés… L'assistant en tient compte dans ses réponses.")
            }
            Section {
                TextEditor(text: $settings.responseStyle).frame(minHeight: 100)
            } header: {
                Text("Comment répondre")
            } footer: {
                Text("Ton, longueur, format (ex. « réponses courtes, exemples en Swift »).")
            }
        }
        .navigationTitle("Personnaliser")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Les nouveautés, lues dans le même fichier que le site et l'app Flutter.
struct WhatsNewView: View {
    private var text: String {
        guard let url = Bundle.main.url(forResource: "nouveautes", withExtension: "md"),
              let s = try? String(contentsOf: url, encoding: .utf8) else { return "Aucune nouveauté." }
        // Sans le commentaire d'en-tête.
        return s.replacingOccurrences(of: "<!--[\\s\\S]*?-->", with: "", options: .regularExpression)
    }

    var body: some View {
        ScrollView {
            MarkdownView(text: text).padding()
        }
        .navigationTitle("Nouveautés")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// La présentation au premier lancement.
struct OnboardingView: View {
    @Environment(SettingsStore.self) private var settings
    @State private var page = 0

    private let pages: [(String, String, String)] = [
        ("sparkles", "Toutes les IA dans votre poche", "Plus de 20 fournisseurs, dont des modèles gratuits. Pollinations répond tout de suite, sans clé ni compte."),
        ("person.2.badge.gearshape", "Vos agents", "Des agents prêts à l'emploi, et les vôtres : créez-les ou importez-les depuis GitHub (format .claude/agents)."),
        ("chevron.left.forwardslash.chevron.right", "Votre GitHub", "Parcourez et modifiez vos dépôts, gérez issues, pull requests et GitHub Actions depuis l'iPhone."),
        ("lock.shield", "Vos clés restent chez vous", "Les clés d'API et le jeton GitHub sont rangés dans le trousseau de l'iPhone. Les conversations restent sur l'appareil."),
    ]

    var body: some View {
        VStack {
            TabView(selection: $page) {
                ForEach(Array(pages.enumerated()), id: \.offset) { i, p in
                    VStack(spacing: 20) {
                        Image(systemName: p.0)
                            .font(.system(size: 72))
                            .foregroundStyle(Theme.gradient(settings.accent))
                        Text(p.1).font(.title.bold()).multilineTextAlignment(.center)
                        Text(p.2).font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    .padding(32)
                    .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            Button {
                if page < pages.count - 1 { withAnimation { page += 1 } } else { settings.onboarded = true }
            } label: {
                Text(page < pages.count - 1 ? "Continuer" : "Commencer").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding()
        }
    }
}
