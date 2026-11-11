import NexoraKit
import SwiftUI

/// Une conversation : les messages en flux, le choix du modèle, de l'effort et de
/// l'agent, et la barre de saisie (texte ou dictée).
struct ChatView: View {
    let conversationId: String

    @Environment(ChatStore.self) private var chats
    @Environment(SettingsStore.self) private var settings
    @Environment(AgentLibrary.self) private var agents
    @Environment(SpeechService.self) private var speech
    @Environment(GitHubSession.self) private var github
    @State private var input = ""
    /// Les fichiers d'un dépôt joints au prochain message.
    @State private var attachments: [ChatAttachment] = []
    @State private var pickingFile = false
    @State private var notice: String?
    @State private var showModels = false
    @State private var showAgents = false
    @State private var editing: ChatMessage?
    @State private var editText = ""
    @FocusState private var focused: Bool

    private var conversation: Conversation? { chats.conversation(conversationId) }
    private var running: Bool { chats.isRunning(conversationId) }
    private var agent: Agent? { conversation?.agentId.flatMap { agents.agent($0) } }

    var body: some View {
        VStack(spacing: 0) {
            messages
            inputBar
        }
        .navigationTitle(conversation?.title ?? "Conversation")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .task { await chats.ensureLoaded(conversationId) }
        .sheet(isPresented: $showModels) {
            ModelPickerSheet(selected: settings.resolve(agent?.model ?? conversation?.model)) { ref in
                chats.setModel(conversationId, ref)
            }
        }
        .sheet(isPresented: $showAgents) {
            AgentPickerSheet(selected: agent) { chats.setAgent(conversationId, $0) }
        }
        .alert("Modifier le message", isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
            TextField("Message", text: $editText, axis: .vertical)
            Button("Annuler", role: .cancel) {}
            Button("Renvoyer") {
                if let m = editing { chats.editAndResend(conversationId, messageId: m.id, text: editText) }
            }
        }
        .onChange(of: speech.transcript) { _, t in
            if speech.listening { input = t }
        }
        .sheet(isPresented: $pickingFile) {
            RepoFilePickerSheet { f in
                if !attachments.contains(f) { attachments.append(f) }
            }
        }
    }

    // MARK: - Messages

    private var messages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if let c = conversation {
                        if c.messages.isEmpty { emptyState }
                        if let dropped = chats.trimmed[conversationId], dropped > 0 {
                            Label("Les \(dropped) premiers messages n'ont pas été envoyés au modèle (mémoire réglée dans Réglages).", systemImage: "info.circle")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(c.messages) { m in
                            MessageBubble(
                                message: m,
                                running: running && m.id == c.messages.last?.id,
                                showThinking: settings.showThinking,
                                onRate: { chats.rate(conversationId, messageId: m.id, $0) },
                                onEdit: m.role == .user ? {
                                    editText = m.content
                                    editing = m
                                } : nil,
                                onRegenerate: m.role == .assistant && m.id == c.messages.last?.id && !running ? {
                                    chats.regenerate(conversationId)
                                } : nil,
                                onSpeak: { speech.speak(SpeechService.clean(m.content)) }
                            )
                            .id(m.id)
                        }
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .defaultScrollAnchor(.bottom)
            .onChange(of: conversation?.messages.last?.content) {
                if running { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: conversation?.messages.count) {
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text(agent?.emoji ?? "✨").font(.system(size: 52))
            Text(agent?.name ?? "Que puis-je faire pour vous ?").font(.title3.bold())
            if let d = agent?.description, !d.isEmpty {
                Text(d).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            let suggestions = ["Explique-moi un concept simplement", "Écris une fonction Swift qui trie une liste", "Résume ce texte en 3 points", "Aide-moi à rédiger un e-mail"]
            VStack(spacing: 8) {
                ForEach(suggestions, id: \.self) { s in
                    Button(s) { input = s; focused = true }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    // MARK: - Saisie

    private var inputBar: some View {
        VStack(spacing: 6) {
            if let e = speech.error {
                Text(e).font(.caption).foregroundStyle(Theme.red)
            }
            if !attachments.isEmpty { attachmentChips }
            // « / » : les commandes ; « @ » : les sous-agents.
            suggestionList
            HStack(alignment: .bottom, spacing: 8) {
                Button(action: attach) {
                    Image(systemName: "paperclip").font(.title3)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Joindre un fichier d'un dépôt")

                Button {
                    speech.toggleListening()
                } label: {
                    Image(systemName: speech.listening ? "waveform.circle.fill" : "mic")
                        .font(.title3)
                        .symbolEffect(.pulse, isActive: speech.listening)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(speech.listening ? "Arrêter la dictée" : "Dicter")

                TextField(agent.map { "Message à \($0.name)…" } ?? "Votre message…", text: $input, axis: .vertical)
                    .lineLimit(1...8)
                    .focused($focused)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.fill.tertiary, in: .rect(cornerRadius: 18))
                    .onSubmit(send)

                if running {
                    Button { chats.stop(conversationId) } label: {
                        Image(systemName: "stop.circle.fill").font(.title)
                    }
                    .accessibilityLabel("Arrêter la réponse")
                } else {
                    Button(action: send) {
                        Image(systemName: "arrow.up.circle.fill").font(.title)
                    }
                    .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("Envoyer")
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
        .sensoryFeedback(.impact(weight: .light), trigger: chats.conversation(conversationId)?.messages.count ?? 0) { _, _ in settings.haptics }
        .alert(notice ?? "", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button("OK", role: .cancel) {}
        }
    }

    private func send() {
        let text = input
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !running else { return }
        if speech.listening { speech.stopListening() }
        input = ""
        chats.send(conversationId, text: ChatLibrary.withAttachments(text.trimmingCharacters(in: .whitespacesAndNewlines), attachments))
        attachments.removeAll()
    }

    // MARK: - Fichiers joints et propositions

    private func attach() {
        guard github.connected else {
            notice = "Connectez GitHub (onglet GitHub) pour joindre des fichiers."
            return
        }
        pickingFile = true
    }

    private var attachmentChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(attachments) { a in
                    HStack(spacing: 4) {
                        Image(systemName: "doc.text")
                        Text(a.fileName).lineLimit(1)
                        Button {
                            attachments.removeAll { $0.id == a.id }
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Retirer \(a.fileName)")
                    }
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.fill.tertiary, in: .capsule)
                }
            }
        }
    }

    @ViewBuilder
    private var suggestionList: some View {
        if let list = ChatLibrary.suggestions(for: input, library: agents.library, agents: agents.all) {
            if list.isEmpty {
                Text(ChatLibrary.noSuggestion(for: input))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(list.prefix(30)) { s in
                            Button {
                                input = s.insert
                                focused = true
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(s.title).font(.subheadline.monospaced().weight(.bold)).foregroundStyle(.primary)
                                    if !s.subtitle.isEmpty {
                                        Text(s.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(height: min(220, CGFloat(min(list.count, 30)) * 48))
                .background(.fill.quaternary, in: .rect(cornerRadius: 14))
            }
        }
    }

    // MARK: - Barre d'outils

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Button { showModels = true } label: {
                let ref = settings.resolve(agent?.model ?? conversation?.model)
                HStack(spacing: 4) {
                    if let p = settings.provider(ref.providerId) { Text(p.emoji) }
                    Text(ref.model).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Image(systemName: "chevron.down").font(.caption2)
                }
            }
            .accessibilityLabel("Changer de modèle")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                if let c = conversation {
                    let current = chats.level(for: c, agent: agent)
                    Picker("Effort", selection: Binding(get: { current }, set: { chats.setLevel(conversationId, $0) })) {
                        ForEach(ThinkLevel.allCases) { l in
                            Label("\(l.label)\(l.badge.map { " · \($0)" } ?? "")", systemImage: levelSymbol(l)).tag(l)
                        }
                    }
                    Button("Agent : \(agent?.name ?? "aucun")", systemImage: "person.crop.circle") { showAgents = true }
                    Divider()
                    ShareLink(item: c.markdown(), preview: SharePreview(c.title)) {
                        Label("Exporter en Markdown", systemImage: "square.and.arrow.up")
                    }
                    if c.cost > 0 || c.tokens > 0 {
                        Text("\(c.tokens) tokens · \(c.cost.dollars)")
                    }
                    Button("Effacer les messages", systemImage: "eraser", role: .destructive) { chats.clearMessages(conversationId) }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("Options de la conversation")
        }
    }

    private func levelSymbol(_ l: ThinkLevel) -> String {
        switch l {
        case .faible: "hare"
        case .moyen: "scalemass"
        case .eleve: "brain"
        case .extra: "atom"
        case .max: "flame"
        }
    }
}
