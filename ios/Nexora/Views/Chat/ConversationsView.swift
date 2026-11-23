import NexoraKit
import SwiftUI

/// Une conversation à ouvrir, avec un texte à placer dans la saisie.
struct ChatRoute: Hashable {
    let id: String
    var prompt: String?
}

/// L'onglet Chat (`ui/chat/conversations_screen.dart`) : le logo, des départs
/// rapides, les premiers pas, et la liste des conversations (recherche dans tous
/// les messages, épinglées d'abord).
struct ConversationsView: View {
    @Environment(ChatStore.self) private var chats
    @Environment(AgentLibrary.self) private var agents
    @Environment(SettingsStore.self) private var settings
    @Environment(AppNavigation.self) private var navigation: AppNavigation?
    @State private var path: [ChatRoute] = []
    @State private var query = ""
    @State private var results: [ConversationStore.Meta]?
    @State private var renaming: ConversationStore.Meta?
    @State private var newTitle = ""
    @State private var pickAgent = false
    @State private var toast: Toast?
    @State private var deleted = 0

    /// Les conversations en attente de suppression sont cachées, même dans les
    /// résultats d'une recherche (« Annuler » les fait revenir).
    private var list: [ConversationStore.Meta] {
        results.map { ChatDisplay.hiding($0, chats.pendingDeletes) } ?? chats.index
    }
    private var searching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                // Pendant une recherche : seulement les résultats.
                if !searching {
                    Group {
                        header
                        // Avec plusieurs conversations, la liste passe avant les idées
                        // (on les retrouve dans un nouveau chat vide).
                        if ChatDisplay.showStarters(conversations: chats.index.count) {
                            starters
                        }
                        GettingStartedCard()
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }

                if list.isEmpty {
                    empty
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                } else {
                    // Rangées par groupes (épinglées, aujourd'hui, hier…), chacune avec
                    // sa date : on retrouve une conversation d'un coup d'œil.
                    ForEach(ChatDisplay.groups(list)) { group in
                        Text(group.title)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .accessibilityAddTraits(.isHeader)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 14, leading: 20, bottom: 2, trailing: 12))
                        ForEach(Array(group.items.enumerated()), id: \.element.id) { i, meta in
                            row(meta)
                                .reveal(i)
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                                .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) { delete(meta) } label: {
                                        Label("Supprimer", systemImage: "trash")
                                    }
                                }
                                .swipeActions(edge: .leading) {
                                    Button { chats.togglePin(meta.id) } label: {
                                        Label(meta.pinned ? "Désépingler" : "Épingler", systemImage: meta.pinned ? "pin.slash" : "pin")
                                    }
                                    .tint(Theme.amber)
                                }
                        }
                    }
                }
            }
            .listStyle(.plain)
            // Le bouton « Nouveau chat » flotte en bas : la dernière conversation
            // n'est pas cachée dessous.
            .contentMargins(.bottom, 84, for: .scrollContent)
            .scrollContentBackground(.hidden)
            .auroraBackground()
            .searchable(text: $query, prompt: "Rechercher dans les conversations")
            .task(id: query) {
                if query.trimmingCharacters(in: .whitespaces).isEmpty { results = nil; return }
                try? await Task.sleep(for: .milliseconds(250))
                results = await chats.search(query)
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    GradientText("NEXORA", font: .title3.weight(.black), tracking: 4)
                }
                ToolbarItem(placement: .topBarLeading) {
                    // Les nouveautés de chaque version, toujours à portée de main.
                    NavigationLink {
                        WhatsNewView()
                    } label: {
                        Label("v\(SettingsStore.appVersion)", systemImage: "sparkles")
                            .labelStyle(.titleAndIcon)
                            .font(.caption.weight(.semibold))
                    }
                    .accessibilityLabel("Nouveautés de chaque version")
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    NavigationLink {
                        HelpView()
                    } label: {
                        Image(systemName: "questionmark.circle")
                    }
                    .accessibilityLabel("Aide et guides")
                    // « Nouveau chat » est le bouton flottant : la barre ne le double
                    // plus et garde seulement le départ avec un agent.
                    Button { pickAgent = true } label: {
                        Image(systemName: "person.crop.circle.badge.plus")
                    }
                    .accessibilityLabel(ChatDisplay.agentChatLabel)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .overlay(alignment: .bottomTrailing) {
                // Liste vide : le bouton est dans le contenu (il ne cache rien).
                if ChatDisplay.showsFloatingNewChat(isEmpty: list.isEmpty, searching: !query.isEmpty) {
                    Button { newChat() } label: {
                        Label("Nouveau chat", systemImage: "plus.bubble.fill")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 14)
                            .background(Theme.gradient(settings.accent), in: .capsule)
                            .shadow(color: Theme.violet.opacity(0.3), radius: 12, y: 6)
                    }
                    .contextMenu {
                        Button("Nouveau chat", systemImage: "plus.bubble") { newChat() }
                        Button("Avec un agent…", systemImage: "person.crop.circle.badge.plus") { pickAgent = true }
                    }
                    .accessibilityHint(ChatDisplay.newChatHint)
                    .padding(20)
                }
            }
            .navigationDestination(for: ChatRoute.self) { route in
                ChatView(conversationId: route.id, initialPrompt: route.prompt) { newId in
                    if !path.isEmpty { path[path.count - 1] = ChatRoute(id: newId) }
                }
            }
            .sheet(isPresented: $pickAgent) {
                AgentPickerSheet(selected: nil) { agent in
                    let c = chats.create(agent: agent)
                    path.append(ChatRoute(id: c.id))
                }
            }
            .alert("Renommer", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Titre", text: $newTitle)
                    .accessibilityLabel("Nouveau titre de la conversation")
                Button("Annuler", role: .cancel) {}
                Button("OK") {
                    if let r = renaming, let t = ChatDisplay.renamed(newTitle, current: r.title) {
                        chats.rename(r.id, t)
                        toast = Toast(text: "Conversation renommée")
                    }
                }
                .disabled(ChatDisplay.renamed(newTitle, current: renaming?.title ?? "") == nil)
            }
            // Au-dessus du bouton « Nouveau chat » flottant : l'avis ne le cache pas.
            .toast($toast, bottom: 84)
            .sensoryFeedback(.impact(weight: .light), trigger: deleted) { _, _ in settings.haptics }
        }
    }

    // MARK: - En-tête

    private var header: some View {
        let current = settings.resolve(settings.defaultModel)
        let provider = settings.provider(current.providerId)
        // Avec des conversations, le logo se fait plus petit : la liste remonte.
        let orb: CGFloat = chats.index.isEmpty ? 180 : 110
        return VStack(spacing: 6) {
            NexusOrb(size: orb, pulse: !chats.running.isEmpty)
            // L'orbite dépasse du globe : le titre reste en dessous.
            Spacer().frame(height: orb / 6)
            Text("Que voulez-vous créer aujourd'hui ?")
                .font(.headline)
                .multilineTextAlignment(.center)
            // Un toucher mène aux modèles : changer de fournisseur ou ajouter une clé.
            Button {
                navigation?.tab = .models
            } label: {
                Text(ChatDisplay.homeSubtitle(
                    emoji: provider?.emoji ?? "",
                    model: settings.displayName(current),
                    ready: settings.readyProviders.count
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(minHeight: 44)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Ouvre l'onglet Modèles")
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    private var starters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(ChatDisplay.starters.enumerated()), id: \.offset) { i, s in
                    GlassCard(padding: 12, action: { newChat(prompt: s.text) }) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(s.emoji).font(.title2)
                            Text(s.text)
                                .font(.caption)
                                .lineLimit(2, reservesSpace: true)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    .frame(width: 200)
                    .tilt3D()
                    .reveal(i)
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 0))
    }

    private var empty: some View {
        VStack(spacing: 14) {
            Text("💬").font(.system(size: 48))
            Text(query.isEmpty ? "Aucune conversation" : "Rien trouvé").font(.title2.weight(.heavy))
            Text(query.isEmpty
                ? "Lancez-vous : Pollinations répond gratuitement, sans clé. Ajoutez d'autres fournisseurs dans l'onglet Modèles."
                : "Essayez un autre mot.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if query.isEmpty {
                Button("Nouveau chat", systemImage: "plus.bubble.fill") { newChat() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(28)
    }

    // MARK: - Conversations

    private func row(_ meta: ConversationStore.Meta) -> some View {
        let agent = meta.agentId.flatMap { agents.agent($0) }
        let running = chats.isRunning(meta.id)
        return GlassCard(padding: 12) {
            HStack(spacing: 12) {
                EmojiAvatar(agent?.emoji ?? "💬", color: running ? Theme.accent(settings.accent) : Theme.violet)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        if meta.pinned { Image(systemName: "pin.fill").font(.caption) }
                        Text(meta.title).font(.subheadline.weight(.bold)).lineLimit(1)
                        Spacer(minLength: 6)
                        Text(ChatDisplay.when(meta.updated))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .layoutPriority(1)
                    }
                    if running {
                        // Une réponse s'écrit : on le voit sans ouvrir la conversation.
                        Label("Réponse en cours…", systemImage: "ellipsis.bubble")
                            .font(.caption)
                            .foregroundStyle(.tint)
                            .lineLimit(1)
                    } else {
                        Text(meta.preview.isEmpty ? (ModelRef.parse(meta.model)?.model ?? "") : meta.preview)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Menu {
                    Button(meta.pinned ? "Désépingler" : "Épingler", systemImage: "pin") { chats.togglePin(meta.id) }
                    Button("Renommer", systemImage: "pencil") {
                        newTitle = meta.title
                        renaming = meta
                    }
                    Button("Supprimer", systemImage: "trash", role: .destructive) { delete(meta) }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Options de « \(meta.title) »")
            }
        }
        // Le menu reste touchable : l'ouverture passe par un toucher sur la carte.
        .contentShape(.rect(cornerRadius: 22))
        .onTapGesture { path.append(ChatRoute(id: meta.id)) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { path.append(ChatRoute(id: meta.id)) }
        .accessibilityActions {
            Button(meta.pinned ? "Désépingler" : "Épingler") { chats.togglePin(meta.id) }
            Button("Renommer") {
                newTitle = meta.title
                renaming = meta
            }
            Button("Supprimer") { delete(meta) }
        }
    }

    private func newChat(prompt: String? = nil) {
        let c = chats.create()
        path.append(ChatRoute(id: c.id, prompt: prompt))
    }

    /// Supprime avec « Annuler » quelques secondes : rien n'est effacé avant.
    private func delete(_ meta: ConversationStore.Meta) {
        let id = meta.id
        chats.deleteLater(id)
        deleted += 1
        toast = Toast(text: ChatDisplay.deletedToast(title: meta.title), actionTitle: "Annuler") { [chats] in
            chats.undoDelete(id)
        }
    }
}
