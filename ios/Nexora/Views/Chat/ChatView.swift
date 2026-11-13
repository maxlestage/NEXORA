import NexoraKit
import PhotosUI
import SwiftUI
import UIKit

/// Une conversation (`ui/chat/chat_screen.dart`) : les messages en flux, l'agent, le
/// modèle et l'effort réglables d'un geste, la dictée (et la conversation vocale),
/// et des flèches pour aller tout en haut ou tout en bas.
struct ChatView: View {
    let conversationId: String
    /// Le texte à placer dans la saisie à l'ouverture (départs rapides).
    var initialPrompt: String?
    /// Ouvre une autre conversation à la place de celle-ci (« Nouvelle conversation »).
    var onReplace: ((String) -> Void)?

    @Environment(ChatStore.self) private var chats
    @Environment(SettingsStore.self) private var settings
    @Environment(AgentLibrary.self) private var agents
    @Environment(SpeechService.self) private var speech
    @Environment(GitHubSession.self) private var github
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var input = ""
    /// Les fichiers d'un dépôt joints au prochain message.
    @State private var attachments: [ChatAttachment] = []
    @State private var pickingFile = false
    /// Les photos jointes au prochain message (4 au plus).
    @State private var photos: [ChatPhotoDraft] = []
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var pickingPhotos = false
    @State private var takingPhoto = false
    @State private var loadingPhotos = false
    @State private var creatingImage = false
    @State private var notice: String?
    @State private var showAgents = false
    @State private var editing: ChatMessage?
    @State private var editText = ""
    @State private var renaming = false
    @State private var newTitle = ""
    @State private var changeModelFor: ChatMessage?
    @State private var toast: Toast?
    @State private var voiceMode = false
    @State private var position = ScrollPosition(edge: .bottom)
    @State private var metrics = ScrollMetrics()
    @State private var dragging = false
    @State private var stickToBottom = true
    @State private var sent = 0
    @FocusState private var focused: Bool

    private var conversation: Conversation? { chats.conversation(conversationId) }
    private var running: Bool { chats.isRunning(conversationId) }
    private var agent: Agent? { conversation?.agentId.flatMap { agents.agent($0) } }
    private var ref: ModelRef { settings.resolve(agent?.model ?? conversation?.model) }

    var body: some View {
        VStack(spacing: 0) {
            if let c = conversation {
                header(c)
                ZStack(alignment: .bottomTrailing) {
                    messages(c)
                    if !c.messages.isEmpty { scrollArrows }
                }
                if let t = chats.trimmed[conversationId], t > 0 {
                    Label(ChatDisplay.trimmedNote(t), systemImage: "memorychip")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if !attachments.isEmpty { attachmentChips.padding(.horizontal, 10) }
                if !photos.isEmpty || loadingPhotos { photoBar.padding(.horizontal, 10) }
                // « / » : les commandes ; « @ » : les sous-agents.
                suggestionList.padding(.horizontal, 10)
                if voiceMode { voiceBar }
                composerWithImages
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.background(dark: scheme == .dark, oled: settings.oledBlack).opacity(scheme == .dark ? 1 : 0))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .task {
            if let p = initialPrompt, input.isEmpty { input = p }
            await chats.ensureLoaded(conversationId)
        }
        .onDisappear {
            speech.cancelListening()
            speech.stopSpeaking()
        }
        .onChange(of: chats.spokenTurn?.count) { onSpokenTurn() }
        .sheet(isPresented: $showAgents) {
            AgentPickerSheet(selected: agent) { chats.setAgent(conversationId, $0) }
        }
        .sheet(item: $changeModelFor) { _ in
            ModelPickerSheet(selected: ref) { r in
                // Réessayer avec un autre modèle : la dernière réponse est refaite.
                chats.setModel(conversationId, r)
                if agent != nil && ChatDisplay.agentKept(afterChoosingModel: agent) == nil { chats.setAgent(conversationId, nil) }
                chats.regenerate(conversationId)
            }
        }
        .alert("Modifier le message", isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
            TextField("Message", text: $editText, axis: .vertical)
            Button("Annuler", role: .cancel) {}
            Button("OK") {
                let t = editText.trimmingCharacters(in: .whitespacesAndNewlines)
                if let m = editing, !t.isEmpty { chats.editAndResend(conversationId, messageId: m.id, text: t) }
            }
        }
        .alert("Renommer", isPresented: $renaming) {
            TextField("Titre", text: $newTitle)
            Button("Annuler", role: .cancel) {}
            Button("OK") {
                let t = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { chats.rename(conversationId, t) }
            }
        }
        .sheet(isPresented: $pickingFile) {
            RepoFilePickerSheet { f in
                if !attachments.contains(f) { attachments.append(f) }
            }
        }
        .alert(notice ?? "", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button("OK", role: .cancel) {}
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: sent) { _, _ in settings.haptics }
        .toast($toast)
    }

    // MARK: - En-tête

    /// Une vue à part, comparée par ses données : elle n'est pas recalculée à
    /// chaque morceau de la réponse en cours (la clé manquante se lit dans le
    /// trousseau).
    private func header(_ c: Conversation) -> some View {
        ChatHeaderBar(
            agentName: agent?.name ?? "Assistant",
            agentEmoji: agent?.emoji ?? "💬",
            current: ref,
            level: chats.level(for: c, agent: agent),
            onAgents: { showAgents = true },
            onModel: chooseModel,
            onLevel: { chats.setLevel(conversationId, $0) }
        )
        .equatable()
    }

    // MARK: - Messages

    private func messages(_ c: Conversation) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                if c.messages.isEmpty {
                    emptyState
                } else {
                    let lastId = c.messages.last?.id
                    ForEach(c.messages) { m in
                        let isLast = m.id == lastId
                        MessageBubble(
                            message: m,
                            streaming: running && isLast,
                            showThinking: settings.showThinking,
                            provider: ModelRef.parse(m.model).flatMap { settings.provider($0.providerId) },
                            onRate: { chats.rate(conversationId, messageId: m.id, $0) },
                            onEdit: m.role == .user && !running ? {
                                editText = m.content
                                editing = m
                            } : nil,
                            onRegenerate: isLast && m.role == .assistant && !running ? {
                                chats.regenerate(conversationId)
                            } : nil,
                            onChangeModel: { changeModelFor = m },
                            onCopied: { toast = Toast(text: "Copié") },
                            onRedoImages: m.imagePrompt != nil && !running ? {
                                chats.redoImages(conversationId, messageId: m.id)
                            } : nil
                        )
                        // Une bulle n'est redessinée que si SES données changent (pas
                        // toutes les bulles à chaque morceau de la réponse en cours).
                        .equatable()
                        .id(m.id)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        .scrollPosition($position)
        .defaultScrollAnchor(.bottom)
        .scrollDismissesKeyboard(.interactively)
        .onScrollGeometryChange(for: ScrollMetrics.self) { g in
            ScrollMetrics(
                fromTop: g.contentOffset.y + g.contentInsets.top,
                toBottom: g.contentSize.height + g.contentInsets.bottom - g.contentOffset.y - g.containerSize.height
            )
        } action: { _, m in
            metrics = m
            if !dragging && m.toBottom < 80 { stickToBottom = true }
        }
        .onScrollPhaseChange { _, phase in
            dragging = phase == .interacting
            // Le doigt remonte dans la conversation : on ne la fait plus défiler à sa place.
            if dragging { stickToBottom = false }
            if phase == .idle { stickToBottom = metrics.toBottom < 80 }
        }
        // `utf8.count` : immédiat (`count` parcourt tout le texte à chaque morceau).
        .onChange(of: c.messages.last?.content.utf8.count) {
            // Pendant une réponse : on suit le texte, sauf si vous êtes remonté.
            if running && stickToBottom && !dragging { position.scrollTo(edge: .bottom) }
        }
        .onChange(of: c.messages.count) {
            stickToBottom = true
            withAnimation(.easeOut(duration: 0.22)) { position.scrollTo(edge: .bottom) }
        }
    }

    /// Deux flèches pour aller tout en haut ou tout en bas ; chacune n'apparaît que
    /// si elle sert.
    private var scrollArrows: some View {
        VStack(spacing: 8) {
            arrow("arrow.up.to.line", "Tout en haut", visible: metrics.fromTop > 400) {
                position.scrollTo(edge: .top)
            }
            arrow("arrow.down.to.line", "Tout en bas", visible: metrics.toBottom > 300) {
                stickToBottom = true
                position.scrollTo(edge: .bottom)
            }
        }
        .padding(.trailing, 14)
        .padding(.bottom, 12)
    }

    private func arrow(_ symbol: String, _ label: String, visible: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .frame(width: 40, height: 40)
                .background(.regularMaterial, in: .circle)
                .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .scaleEffect(visible ? 1 : 0.01)
        .opacity(visible ? 1 : 0)
        .animation(.easeOut(duration: 0.18), value: visible)
        .allowsHitTesting(visible)
        .accessibilityHidden(!visible)
        .accessibilityLabel(label)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            // Logo plus petit : les 4 idées restent visibles au-dessus du clavier.
            NexusOrb(size: 150)
            Text(ChatDisplay.emptyTitle(agent: agent))
                .font(.title2.weight(.heavy))
                .multilineTextAlignment(.center)
            Text(ChatDisplay.emptyText(agent: agent))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 12)
            ForEach(Array(ChatDisplay.ideas(agent: agent).enumerated()), id: \.offset) { i, idea in
                GlassCard(padding: 12, action: {
                    input = idea
                    focused = true
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: "sparkles").foregroundStyle(.tint)
                        Text(idea).multilineTextAlignment(.leading)
                    }
                }
                .reveal(i)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(12)
    }

    // MARK: - Saisie

    private var voiceBar: some View {
        HStack(spacing: 8) {
            Image(systemName: speech.listening ? "ear" : speech.speaking ? "speaker.wave.2.fill" : "headphones")
                .foregroundStyle(.tint)
            Text(speech.listening ? "Je vous écoute…" : speech.speaking ? "Je réponds à voix haute…" : "Conversation vocale")
                .font(.footnote)
            Spacer()
            Button("Terminer", systemImage: "stop.circle") { stopVoice() }
                .font(.footnote)
        }
        .padding(.horizontal, 14)
        .padding(.top, 4)
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 6) {
            attachMenu
            TextField("Écrivez une instruction…", text: $input, axis: .vertical)
                .lineLimit(1...8)
                .focused($focused)
                .submitLabel(settings.sendOnEnter ? .send : .return)
                .padding(.leading, 14)
                .padding(.vertical, 10)
                .onChange(of: input) { _, v in
                    // Entrée pour envoyer : le retour à la ligne tapé envoie le message.
                    if settings.sendOnEnter, v.hasSuffix("\n") {
                        input = String(v.dropLast())
                        send()
                    }
                }
                .onKeyPress(.return, phases: .down) { press in
                    guard settings.sendOnEnter, !press.modifiers.contains(.shift) else { return .ignored }
                    send()
                    return .handled
                }
            micButton
            if running {
                Button { chats.stop(conversationId) } label: {
                    Image(systemName: "stop.fill")
                        .font(.body.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(Theme.red, in: .circle)
                }
                .accessibilityLabel("Arrêter la réponse")
                .transition(.scale.combined(with: .opacity))
            } else {
                // Rien à envoyer : le bouton s'efface (on voit tout de suite qu'il
                // faut écrire d'abord).
                let ready = ChatDisplay.canSend(input, photos: photos.count)
                Button(action: { send() }) {
                    Image(systemName: "arrow.up")
                        .font(.body.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(Theme.gradient(settings.accent), in: .circle)
                        .opacity(ready ? 1 : 0.35)
                }
                .disabled(!ready)
                .accessibilityLabel("Envoyer")
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: running)
        .padding(4)
        .background(scheme == .dark ? Theme.panel2 : Color.white, in: .rect(cornerRadius: 26))
        .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(scheme == .dark ? Color.white.opacity(0.13) : Color.black.opacity(0.08)))
        .shadow(color: Theme.violet.opacity(0.12), radius: 12, y: 8)
        .padding(.horizontal, 10)
        .padding(.top, 4)
        .padding(.bottom, 10)
    }

    /// Le micro : rouge et animé pendant l'écoute.
    private var micButton: some View {
        let on = speech.listening
        return Button { dictate() } label: {
            Image(systemName: on ? "mic.fill" : "mic")
                .font(.title3)
                .foregroundStyle(on ? Theme.red : .secondary)
                .frame(width: 38, height: 38)
                .background(on ? Theme.red.opacity(0.15) : .clear, in: .circle)
                .shadow(color: on ? Theme.red.opacity(0.45) : .clear, radius: 3 + speech.level * 9)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(on ? "Arrêter la dictée" : "Parler")
    }

    private func send(voice: Bool = false) {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard conversation != nil, !running else { return }
        // « /image [nombre] description » : crée des images.
        if let cmd = ImageGenCommand.parse(text) {
            guard !cmd.prompt.isEmpty else {
                notice = ImageGenCommand.missingPrompt
                return
            }
            sent += 1
            input = ""
            stickToBottom = true
            chats.createImages(conversationId, prompt: cmd.prompt, count: cmd.count)
            return
        }
        guard !text.isEmpty || !photos.isEmpty else { return }
        // Les photos sont enregistrées sur l'appareil, puis jointes au message.
        let images = chats.saveImages(photos.map(\.data))
        if text.isEmpty && images.isEmpty {
            notice = "Impossible d'enregistrer les photos sur l'appareil."
            return
        }
        sent += 1
        input = ""
        stickToBottom = true
        chats.send(conversationId, text: ChatLibrary.withAttachments(text, attachments), voice: voice, images: images)
        attachments.removeAll()
        photos.removeAll()
    }

    // MARK: - Photos et images

    /// Le trombone : photos, appareil photo, création d'image, fichier d'un dépôt.
    private var attachMenu: some View {
        Menu {
            Button("Photo", systemImage: "photo.on.rectangle") { pickPhotos() }
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("Appareil photo", systemImage: "camera") {
                    guard photos.count < ChatImages.maxPerMessage else {
                        notice = Self.tooManyPhotos
                        return
                    }
                    takingPhoto = true
                }
            }
            Button("Créer une image", systemImage: "wand.and.stars") { creatingImage = true }
            Divider()
            Button("Fichier d'un dépôt", systemImage: "doc.text") { attach() }
        } label: {
            Image(systemName: "paperclip")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 38, height: 38)
        }
        .menuOrder(.fixed)
        .accessibilityLabel("Joindre ou créer")
    }

    static let tooManyPhotos = "4 photos au plus par message."

    private func pickPhotos() {
        guard photos.count < ChatImages.maxPerMessage else {
            notice = Self.tooManyPhotos
            return
        }
        pickingPhotos = true
    }

    /// La saisie, avec le choix des photos, l'appareil photo et la création
    /// d'images.
    private var composerWithImages: some View {
        composer
            .photosPicker(
                isPresented: $pickingPhotos, selection: $photoItems,
                maxSelectionCount: max(1, ChatImages.maxPerMessage - photos.count),
                matching: .images, preferredItemEncoding: .compatible
            )
            .onChange(of: photoItems) { _, items in
                guard !items.isEmpty else { return }
                photoItems = []
                Task { await addPhotos(items) }
            }
            .fullScreenCover(isPresented: $takingPhoto) {
                NexoraCameraPicker { data in
                    takingPhoto = false
                    Task { await addPhoto(data) }
                } onCancel: {
                    takingPhoto = false
                }
                .ignoresSafeArea()
            }
            .sheet(isPresented: $creatingImage) {
                ImagePromptSheet(initial: ImageGenCommand.parse(input)?.prompt ?? input, engine: chats.imageEngine) { prompt, count in
                    createImages(prompt, count)
                }
            }
            .onChange(of: chats.notices[conversationId]) { _, n in
                // Le modèle a refusé les images : on le dit clairement.
                if let n {
                    notice = n
                    chats.dismissNotice(conversationId)
                }
            }
    }

    private func createImages(_ prompt: String, _ count: Int) {
        guard !prompt.isEmpty, !running else { return }
        input = ""
        sent += 1
        stickToBottom = true
        chats.createImages(conversationId, prompt: prompt, count: count)
    }

    /// Les photos choisies dans la photothèque, réduites avant l'envoi.
    private func addPhotos(_ items: [PhotosPickerItem]) async {
        loadingPhotos = true
        var failed = 0
        for item in items {
            guard photos.count < ChatImages.maxPerMessage else { break }
            guard let raw = try? await item.loadTransferable(type: Data.self),
                  let draft = await ChatPhotoDraft.make(raw) else {
                failed += 1
                continue
            }
            photos.append(draft)
        }
        loadingPhotos = false
        if failed > 0 {
            notice = failed > 1 ? "\(failed) photos n'ont pas pu être lues." : "Une photo n'a pas pu être lue."
        }
    }

    /// La photo prise avec l'appareil photo.
    private func addPhoto(_ data: Data) async {
        loadingPhotos = true
        let draft = await ChatPhotoDraft.make(data)
        loadingPhotos = false
        if let draft, photos.count < ChatImages.maxPerMessage {
            photos.append(draft)
        } else if draft == nil {
            notice = "La photo n'a pas pu être lue."
        }
    }

    /// Les photos jointes, et un avertissement si le modèle ne les voit pas.
    private var photoBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            PhotoDraftStrip(photos: $photos, loading: loadingPhotos)
            if !photos.isEmpty && !ModelVision.likelySees(providerId: ref.providerId, model: ref.model) {
                Label(
                    "\(settings.displayName(ref)) ne voit probablement pas les images. Choisissez un modèle « vision » (GPT-4o, Claude, Gemini, Llava…).",
                    systemImage: "eye.slash"
                )
                .font(.caption)
                .foregroundStyle(Theme.amber)
            }
        }
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

    /// Les propositions : `/image` (intégrée) puis les commandes et les agents.
    private var suggestions: [ChatSuggestion]? {
        // Rien à proposer hors de « / » et « @ » en tête : l'écran se redessine à
        // chaque morceau d'une réponse, inutile d'y relancer la recherche (regex).
        let first = input.unicodeScalars.first
        guard first == "/" || first == "@" else { return nil }
        let list = ChatLibrary.suggestions(for: input, library: agents.library, agents: agents.all)
        guard let image = ImageGenCommand.suggestion(for: input) else { return list }
        return [image] + (list ?? []).filter { $0.insert != image.insert }
    }

    @ViewBuilder
    private var suggestionList: some View {
        if let list = suggestions {
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

    /// Dicte un message. Envoyé dès la fin de la dictée (si réglé ainsi), et la
    /// réponse est lue à voix haute.
    private func dictate() {
        if speech.listening {
            speech.stopListening()
            return
        }
        speech.rate = settings.voiceRate
        let before = input.trimmingCharacters(in: .whitespacesAndNewlines)
        speech.listen { t in
            input = before.isEmpty ? t : "\(before) \(t)"
        } onFinal: { _ in
            if settings.voiceAutoSend {
                voiceMode = settings.voiceConversation
                send(voice: true)
            }
        }
    }

    private func stopVoice() {
        voiceMode = false
        speech.cancelListening()
        speech.stopSpeaking()
    }

    /// La réponse lue est finie : en conversation vocale, on écoute de nouveau.
    private func onSpokenTurn() {
        guard voiceMode, chats.spokenTurn?.id == conversationId, !speech.listening else { return }
        dictate()
    }

    /// Un modèle choisi dans le bouton de la barre de saisie.
    private func chooseModel(_ r: ModelRef) {
        let wasRunning = running
        chats.setModel(conversationId, r)
        // Un agent qui impose son modèle est retiré, pour que le modèle choisi soit
        // bien utilisé.
        if agent != nil && ChatDisplay.agentKept(afterChoosingModel: agent) == nil { chats.setAgent(conversationId, nil) }
        // Changé pendant une réponse : elle repart tout de suite avec le nouveau modèle.
        if wasRunning {
            chats.stop(conversationId)
            chats.regenerate(conversationId)
        }
    }

    // MARK: - Barre d'outils

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Button {
                newTitle = conversation?.title ?? ""
                renaming = true
            } label: {
                // Le titre (toucher pour renommer) et, dessous, ce que la
                // conversation a coûté.
                VStack(spacing: 0) {
                    Text(conversation?.title ?? "Conversation")
                        .font(.headline)
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                    if let c = conversation {
                        Text(ChatDisplay.spendLine(c))
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .accessibilityHint("Renommer la conversation")
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                let c = conversation
                let n = chats.create(agent: agent, model: c?.model)
                if let onReplace { onReplace(n.id) }
            } label: {
                Image(systemName: "square.and.pencil")
            }
            .accessibilityLabel("Nouvelle conversation")
            Menu {
                if let c = conversation {
                    Button("Copier en Markdown", systemImage: "doc.on.doc") {
                        UIPasteboard.general.string = ChatDisplay.export(c)
                        toast = Toast(text: "Conversation copiée")
                    }
                    // Le Markdown n'est construit qu'au moment du partage.
                    ShareLink(item: ConversationShare(conversation: c), preview: SharePreview(c.title)) {
                        Label("Partager", systemImage: "square.and.arrow.up")
                    }
                    Button("Effacer les messages", systemImage: "eraser") { chats.clearMessages(conversationId) }
                    Button("Supprimer", systemImage: "trash", role: .destructive) {
                        chats.delete(conversationId)
                        dismiss()
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("Options de la conversation")
        }
    }
}

/// La barre du haut d'une conversation, sur une seule ligne : l'agent, le modèle
/// et l'effort (toucher pour en changer), « Clé manquante » si besoin (toucher pour
/// l'ajouter), et le crédit restant chez le fournisseur.
struct ChatHeaderBar: View {
    let agentName: String
    let agentEmoji: String
    let current: ModelRef
    let level: ThinkLevel
    var onAgents: () -> Void
    var onModel: (ModelRef) -> Void
    var onLevel: (ThinkLevel) -> Void

    @Environment(SettingsStore.self) private var settings
    @Environment(AppNavigation.self) private var navigation: AppNavigation?

    var body: some View {
        HStack(spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    Button(action: onAgents) {
                        Label { Text(agentName).lineLimit(1) } icon: { Text(agentEmoji) }
                            .font(.subheadline)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .accessibilityLabel("Agent : \(agentName)")
                    .accessibilityHint("Changer d'agent")
                    ModelEffortButton(current: current, level: level, onModel: onModel, onLevel: onLevel)
                    if let p = settings.provider(current.providerId), !settings.isReady(p) {
                        Button {
                            navigation?.tab = .models
                        } label: {
                            Label("Clé manquante", systemImage: "key.slash")
                                .font(.subheadline)
                                .foregroundStyle(Theme.amber)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Theme.amber.opacity(0.12), in: .capsule)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Ouvrir l'onglet Modèles pour ajouter la clé")
                    }
                }
                .padding(.leading, 12)
            }
            // Le crédit de l'IA de CETTE conversation (et pas du modèle par défaut).
            QuotaBadge(providerId: current.providerId, dense: true)
                .frame(maxWidth: 140, alignment: .trailing)
                .padding(.trailing, 8)
        }
        .padding(.vertical, 4)
    }
}

extension ChatHeaderBar: @preconcurrency Equatable {
    /// Les actions ne font qu'ouvrir un choix : seules les données comptent.
    static func == (a: ChatHeaderBar, b: ChatHeaderBar) -> Bool {
        a.agentName == b.agentName && a.agentEmoji == b.agentEmoji && a.current == b.current && a.level == b.level
    }
}

/// Une conversation à partager en Markdown : le texte n'est construit qu'au moment
/// du partage (et non à chaque rendu de l'écran, donc à chaque morceau reçu).
struct ConversationShare: Transferable {
    let conversation: Conversation

    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(exporting: { (share: ConversationShare) -> String in
            ChatDisplay.export(share.conversation)
        })
    }
}

/// La position dans la liste des messages : distance au haut et au bas.
struct ScrollMetrics: Equatable {
    var fromTop: CGFloat = 0
    var toBottom: CGFloat = 0
}

/// Un texte entier, sélectionnable et copiable, en plein écran.
struct FullTextView: View {
    let title: String
    let text: String

    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        UIPasteboard.general.string = text
                        copied = true
                    } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    }
                    .accessibilityLabel("Copier")
                }
            }
        }
    }
}
