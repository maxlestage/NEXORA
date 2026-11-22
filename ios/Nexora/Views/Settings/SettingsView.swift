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
    /// Choix du ménage calculés à l'ouverture : durée et nombre de conversations supprimées.
    @State private var cleanChoices: [(days: Int, count: Int)] = []
    @State private var editingClientId = false
    /// Confirmation avant de se déconnecter de GitHub (le jeton serait à recoller).
    @State private var confirmSignOut = false
    /// Écran de connexion à GitHub ouvert depuis les Réglages (refermé une fois connecté).
    @State private var signingIn = false
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
                                Text("Couleurs, texte, assistant, onglets…")
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
                    if github.connected {
                        HStack {
                            Label(SettingsDisplay.github(login: github.user?.login, connected: true), systemImage: "person.crop.circle")
                            Spacer()
                            Button("Déconnexion") { confirmSignOut = true }
                                .buttonStyle(.borderless)
                                .frame(minHeight: 44)
                        }
                    } else {
                        // Action principale quand on n'est pas connecté : se connecter, ici même.
                        Button {
                            signingIn = true
                        } label: {
                            LabeledContent {
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            } label: {
                                Label("Se connecter à GitHub", systemImage: "person.crop.circle.badge.plus")
                            }
                        }
                        .frame(minHeight: 44)
                    }
                    DisclosureGroup("Avancé") {
                        Button {
                            clientId = settings.githubClientId
                            editingClientId = true
                        } label: {
                            LabeledContent("Client ID OAuth", value: SettingsDisplay.clientIdDetail(
                                settings.githubClientId,
                                builtIn: !((Bundle.main.object(forInfoDictionaryKey: "GitHubClientID") as? String) ?? "").isEmpty))
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
                        cleanChoices = SettingsDisplay.cleanChoices(
                            SettingsDisplay.cleanPeriods.map { (days: $0, count: chats.staleCount($0)) })
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
                    NavigationLink {
                        WhatsNewView()
                    } label: {
                        Label("Nouveautés", systemImage: "sparkles")
                    }
                    NavigationLink {
                        AboutNexoraView()
                    } label: {
                        LabeledContent {
                            Text(SettingsDisplay.aboutDetail(version: SettingsStore.appVersion))
                        } label: {
                            Label("À propos de NEXORA", systemImage: "info.circle")
                        }
                    }
                }

                // Actions irréversibles, rangées tout en bas (chacune demande confirmation).
                Section {
                    Button("Effacer toutes les conversations", systemImage: "trash", role: .destructive) {
                        // Rien à effacer : on le dit tout de suite, sans confirmation inutile.
                        if chats.index.isEmpty { deleteAll() } else { confirmDelete = true }
                    }
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
                ForEach(cleanChoices.map { $0.days }, id: \.self) { d in
                    let n = cleanChoices.first { $0.days == d }?.count ?? 0
                    Button(SettingsDisplay.cleanOption(days: d, count: n), role: .destructive) { clean(d) }
                }
                Button(cleanChoices.isEmpty ? "OK" : "Annuler", role: .cancel) {}
            } message: {
                Text(SettingsDisplay.cleanMessage(hasChoices: !cleanChoices.isEmpty))
            }
            .navigationDestination(isPresented: $signingIn) {
                GitHubSignInView().navigationTitle("GitHub")
            }
            .onChange(of: github.connected) { _, connected in
                guard connected, signingIn else { return }
                signingIn = false
                done += 1
                toast = Toast(text: SettingsDisplay.signedIn(login: github.user?.login))
            }
            .alert(SettingsDisplay.signOutTitle(login: github.user?.login), isPresented: $confirmSignOut) {
                Button("Annuler", role: .cancel) {}
                Button("Se déconnecter", role: .destructive) { github.signOut() }
            } message: {
                Text(SettingsDisplay.signOutMessage)
            }
            .alert(SettingsDisplay.deleteAllTitle(chats.index.count), isPresented: $confirmDelete) {
                Button("Annuler", role: .cancel) {}
                Button("Effacer", role: .destructive) { deleteAll() }
            } message: {
                Text(SettingsDisplay.deleteAllMessage(count: chats.index.count, pinned: chats.index.filter(\.pinned).count))
            }
            .alert("Tout effacer de cet appareil ?", isPresented: $confirmReset) {
                Button("Annuler", role: .cancel) {}
                Button("Tout effacer", role: .destructive) { resetAll() }
            } message: {
                Text(SettingsDisplay.resetMessage)
            }
            .alert("OAuth App GitHub", isPresented: $editingClientId) {
                TextField("Client ID", text: $clientId)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Annuler", role: .cancel) {}
                // Identifiant inutilisable (secret collé, URL…) : « OK » éteint.
                Button("OK") {
                    if let id = SettingsDisplay.clientId(clientId) { settings.githubClientId = id }
                }
                .disabled(SettingsDisplay.clientId(clientId) == nil)
            } message: {
                Text(SettingsDisplay.clientIdMessage)
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

/// Page « À propos de NEXORA » (ouverte depuis les Réglages) : l'orbe, l'auteur, la promesse
/// de confidentialité, puis les liens rares (crédits, code source, site, présentation).
/// Avant 3.0.112, tout cela occupait la moitié de l'onglet Réglages.
private struct AboutNexoraView: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        List {
            Section {
                VStack(spacing: 6) {
                    NexusOrb(size: 120, satellites: 8, interactive: false)
                    GradientText("NEXORA", font: .title.weight(.black), tracking: 6)
                    Text(SettingsDisplay.aboutDetail(version: SettingsStore.appVersion))
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Conçu et développé par \(SettingsView.author)")
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
                .accessibilityElement(children: .combine)
            }
            Section {
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
        }
        .navigationTitle("À propos")
        .navigationBarTitleDisplayMode(.inline)
    }
}
