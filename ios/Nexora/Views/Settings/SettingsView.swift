import NexoraKit
import SwiftUI
import UIKit

/// L'onglet Réglages (`ui/settings/settings_screen.dart`) : aide, personnalisation,
/// modèle par défaut, GitHub, données (place, ménage, export), à propos.
struct SettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(ChatStore.self) private var chats
    @Environment(AgentLibrary.self) private var agents
    @Environment(GitHubSession.self) private var github
    @State private var pickModel = false
    @State private var confirmDelete = false
    @State private var confirmReset = false
    @State private var cleaning = false
    @State private var editingClientId = false
    @State private var clientId = ""
    @State private var size: Int?
    @State private var toast: Toast?
    /// Incrémenté après une action réussie (ménage, export, effacement) : vibration.
    @State private var done = 0

    /// L'auteur de NEXORA.
    static let author = "Maxime Nathan Lestage"

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        HelpView()
                    } label: {
                        card("🧭", "Aide et guides", "Clés gratuites, crédit, Ollama, agents, GitHub…")
                    }
                    NavigationLink {
                        PersonalizeView()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "paintpalette")
                                .foregroundStyle(.white)
                                .frame(width: 40, height: 40)
                                .background(Theme.gradient(settings.accent), in: .circle)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Personnaliser").font(.subheadline.weight(.heavy))
                                Text("Couleurs, thème, texte, animations, effort, messages, assistant, onglets…")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("Modèle") {
                    Button {
                        pickModel = true
                    } label: {
                        LabeledContent("Modèle par défaut", value: settings.displayName(settings.resolve(nil)))
                    }
                }

                ImageSettingsSection()

                Section("Crédits et consommation") {
                    UsageSettingsRow()
                }

                Section("GitHub") {
                    HStack {
                        Label(SettingsDisplay.github(login: github.user?.login, connected: github.connected), systemImage: "person.crop.circle")
                        Spacer()
                        if github.connected {
                            Button("Déconnexion") { github.signOut() }
                                .buttonStyle(.borderless)
                                .frame(minHeight: 44)
                        }
                    }
                    DisclosureGroup("Avancé") {
                        Button {
                            clientId = settings.githubClientId
                            editingClientId = true
                        } label: {
                            LabeledContent("Client ID OAuth", value: SettingsDisplay.clientIdDetail(settings.githubClientId))
                        }
                    }
                }

                Section("Données") {
                    HStack {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(SettingsDisplay.storage(conversations: chats.index.count, bytes: size))
                                Text(size == nil ? "Calcul de la place…" : "Sur cet appareil")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "internaldrive")
                        }
                        Spacer()
                        Button {
                            Task { size = await chats.sizeOnDisk() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .frame(width: 44, height: 44)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Recalculer la place")
                    }
                    Button {
                        cleaning = true
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Label("Supprimer les anciennes conversations", systemImage: "sparkles.rectangle.stack")
                            Text("Les épinglées sont gardées").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Button("Exporter mes agents", systemImage: "square.and.arrow.up") { exportAgents() }
                }

                Section("À propos") {
                    VStack(spacing: 6) {
                        NexusOrb(size: 120, satellites: 8, interactive: false)
                        GradientText("NEXORA", font: .title.weight(.black), tracking: 6)
                        Text("Version \(SettingsStore.appVersion)").font(.caption).foregroundStyle(.secondary)
                        Text("Conçu et développé par \(Self.author)")
                            .font(.subheadline.weight(.bold))
                            .multilineTextAlignment(.center)
                            .padding(.top, 6)
                        Text("Aucun serveur intermédiaire : l'app parle directement aux fournisseurs et à GitHub. Vos clés restent sur l'appareil.")
                            .font(.footnote)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    NavigationLink {
                        WhatsNewView()
                    } label: {
                        Label("Nouveautés", systemImage: "sparkles")
                    }
                    NavigationLink {
                        CreditsView()
                    } label: {
                        Label("Crédits", systemImage: "heart")
                    }
                    Link(destination: URL(string: "https://github.com/maxlestage/NEXORA")!) {
                        Label("Code source", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                    Link(destination: URL(string: "https://maxlestage.github.io/NEXORA/")!) {
                        Label("Le site de NEXORA", systemImage: "globe")
                    }
                    Button("Revoir la présentation", systemImage: "play.rectangle") { settings.onboarded = false }
                }

                // Actions irréversibles, rangées tout en bas (chacune demande confirmation).
                Section {
                    Button("Effacer toutes les conversations", systemImage: "trash", role: .destructive) { confirmDelete = true }
                    Button(role: .destructive) {
                        confirmReset = true
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Label("Tout réinitialiser", systemImage: "exclamationmark.triangle")
                            Text("Clés, jeton GitHub, agents, conversations").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Effacer")
                }
            }
            .navigationTitle("Réglages")
            .task { size = await chats.sizeOnDisk() }
            .sheet(isPresented: $pickModel) {
                ModelPickerSheet(selected: settings.resolve(nil)) { settings.defaultModel = $0.key }
            }
            .confirmationDialog("Supprimer les conversations inactives depuis…", isPresented: $cleaning, titleVisibility: .visible) {
                ForEach([30, 90, 180, 365], id: \.self) { d in
                    Button(d == 365 ? "1 an" : "\(d) jours") { clean(d) }
                }
            }
            .alert("Effacer toutes les conversations ?", isPresented: $confirmDelete) {
                Button("Annuler", role: .cancel) {}
                Button("Confirmer", role: .destructive) { deleteAll() }
            }
            .alert("Tout effacer de cet appareil ?", isPresented: $confirmReset) {
                Button("Annuler", role: .cancel) {}
                Button("Confirmer", role: .destructive) { resetAll() }
            } message: {
                Text("Action irréversible.")
            }
            .alert("OAuth App GitHub", isPresented: $editingClientId) {
                TextField("Client ID", text: $clientId)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Annuler", role: .cancel) {}
                Button("OK") { settings.githubClientId = clientId.trimmingCharacters(in: .whitespacesAndNewlines) }
            } message: {
                Text("GitHub → Settings → Developer settings → OAuth Apps → New. Cochez « Enable Device Flow », puis collez le Client ID (pas de secret nécessaire). L'app se crée sur github.com/settings/applications/new.")
            }
            .toast($toast)
            .sensoryFeedback(.success, trigger: done) { _, _ in settings.haptics }
        }
    }

    private func card(_ emoji: String, _ title: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Text(emoji).font(.system(size: 26))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.heavy))
                Text(text).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func clean(_ days: Int) {
        let n = chats.deleteOlderThan(days)
        toast = Toast(text: SettingsDisplay.cleaned(n))
        if n > 0 { done += 1 }
        refreshSize()
    }

    private func deleteAll() {
        let n = chats.index.count
        chats.deleteAll()
        toast = Toast(text: SettingsDisplay.deletedAll(n))
        if n > 0 { done += 1 }
        refreshSize()
    }

    /// Recalcule la place un peu après une suppression (les fichiers partent en tâche de fond).
    private func refreshSize() {
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            size = await chats.sizeOnDisk()
        }
    }

    private func exportAgents() {
        let mine = agents.custom
        guard !mine.isEmpty else {
            toast = Toast(text: SettingsDisplay.exported(0))
            return
        }
        UIPasteboard.general.string = mine.map { $0.toMarkdown() }.joined(separator: "\n\n<!-- --- -->\n\n")
        toast = Toast(text: SettingsDisplay.exported(mine.count))
        done += 1
    }

    private func resetAll() {
        chats.deleteAll()
        github.signOut()
        settings.resetAll()
        toast = Toast(text: "Réinitialisé. Relancez l'app.")
    }
}
