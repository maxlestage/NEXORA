import Foundation
import NexoraKit
import Observation

/// Les conversations et les réponses en cours. Une seule réponse à la fois par
/// conversation ; le texte reçu est recopié dans le message au plus toutes les
/// 60 ms pour garder l'interface fluide, même avec de très longues réponses.
@MainActor
@Observable
final class ChatStore {
    private(set) var index: [ConversationStore.Meta] = []
    /// Les conversations ouvertes (messages chargés).
    private(set) var open: [String: Conversation] = [:]
    private(set) var running: Set<String> = []
    /// Les messages laissés de côté lors de la dernière réponse (mémoire limitée).
    private(set) var trimmed: [String: Int] = [:]
    /// Quand une réponse lue à voix haute est finie : sa conversation, et un compteur
    /// qui change à chaque fois (pour la conversation vocale, qui écoute de nouveau).
    private(set) var spokenTurn: (id: String, count: Int)?
    /// Un avis à montrer dans une conversation (ex. : le modèle a refusé les images).
    private(set) var notices: [String: String] = [:]
    /// Les photos jointes et les images créées, sur l'appareil.
    @ObservationIgnored let imageFiles = ChatImageStore.standard
    @ObservationIgnored private let imageGen = ImageGenClient()

    @ObservationIgnored private let store: ConversationStore
    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let agents: AgentLibrary
    @ObservationIgnored private let llm: LLMClient
    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var runIds: [String: UUID] = [:]
    @ObservationIgnored private var saveTasks: [String: Task<Void, Never>] = [:]
    var speech: SpeechService?
    /// Le témoin de crédit : chaque réponse y est comptée (tokens, coût, limites
    /// lues dans les en-têtes, erreurs de clé ou de crédit). Facultatif.
    var usage: UsageStore?

    init(settings: SettingsStore, agents: AgentLibrary, store: ConversationStore = ConversationStore(directory: ConversationStore.defaultDirectory()), llm: LLMClient = LLMClient()) {
        self.settings = settings
        self.agents = agents
        self.store = store
        self.llm = llm
        Task { await reloadIndex() }
    }

    func reloadIndex() async {
        index = await store.index()
    }

    func isRunning(_ id: String) -> Bool { running.contains(id) }

    func conversation(_ id: String) -> Conversation? { open[id] }

    /// Charge les messages d'une conversation de la liste.
    func ensureLoaded(_ id: String) async {
        if open[id] != nil { return }
        if let c = await store.load(id) { open[id] = c }
    }

    func create(agent: Agent? = nil, model: String? = nil) -> Conversation {
        let c = Conversation(
            model: model ?? agent?.model ?? settings.defaultModel,
            agentId: agent?.id,
            level: agent?.level
        )
        open[c.id] = c
        return c
    }

    func search(_ q: String) async -> [ConversationStore.Meta] { await store.search(q) }

    /// Place occupée par les conversations, en octets.
    func sizeOnDisk() async -> Int {
        let files = imageFiles
        let images = await Task.detached { files.sizeOnDisk() }.value
        return await store.sizeOnDisk() + images
    }

    /// Supprime les conversations non épinglées sans activité depuis `days` jours.
    @discardableResult
    func deleteOlderThan(_ days: Int) -> Int {
        let old = ConversationStore.stale(index, days: days, running: running)
        for id in old {
            saveTasks.removeValue(forKey: id)?.cancel()
            open[id] = nil
        }
        index.removeAll { old.contains($0.id) }
        let files = imageFiles
        Task {
            for id in old {
                // Les images de la conversation partent avec elle.
                if let c = await store.load(id) { files.delete(c.imageNames) }
                try? await store.delete(id)
            }
            await reloadIndex()
        }
        return old.count
    }

    // MARK: - Modifications

    private func mutate(_ id: String, now: Bool = false, _ f: (inout Conversation) -> Void) {
        guard var c = open[id] else { return }
        f(&c)
        open[id] = c
        scheduleSave(id, now: now)
    }

    private func scheduleSave(_ id: String, now: Bool) {
        saveTasks[id]?.cancel()
        saveTasks[id] = Task { [weak self] in
            if !now { try? await Task.sleep(for: .milliseconds(600)) }
            guard !Task.isCancelled, let self, let c = self.open[id], !c.messages.isEmpty else { return }
            try? await self.store.save(c)
            await self.reloadIndex()
        }
    }

    func rename(_ id: String, _ title: String) {
        Task {
            await ensureLoaded(id)
            mutate(id, now: true) { $0.title = title }
        }
    }

    func togglePin(_ id: String) {
        Task {
            await ensureLoaded(id)
            mutate(id, now: true) { $0.pinned.toggle() }
        }
    }

    func delete(_ id: String) {
        stop(id)
        let loaded = open[id]
        open[id] = nil
        let files = imageFiles
        Task {
            // Les images de la conversation partent avec elle.
            var c = loaded
            if c == nil { c = await store.load(id) }
            if let c { files.delete(c.imageNames) }
            try? await store.delete(id)
            await reloadIndex()
        }
    }

    func deleteAll() {
        for id in running { stop(id) }
        open.removeAll()
        let files = imageFiles
        Task {
            files.deleteAll()
            try? await store.deleteAll()
            await reloadIndex()
        }
    }

    func setModel(_ id: String, _ ref: ModelRef) { mutate(id) { $0.model = ref.key } }

    func setLevel(_ id: String, _ level: ThinkLevel?) { mutate(id) { $0.level = level?.rawValue } }

    func setAgent(_ id: String, _ agent: Agent?) {
        mutate(id) {
            $0.agentId = agent?.id
            if let m = agent?.model { $0.model = m }
        }
    }

    func rate(_ id: String, messageId: UUID, _ value: Int) {
        mutate(id) { c in
            if let i = c.messages.firstIndex(where: { $0.id == messageId }) {
                c.messages[i].rating = c.messages[i].rating == value ? 0 : value
            }
        }
    }

    func clearMessages(_ id: String) {
        stop(id)
        let names = open[id]?.imageNames ?? []
        mutate(id, now: true) { $0.messages.removeAll() }
        imageFiles.delete(names)
    }

    func level(for c: Conversation, agent: Agent?) -> ThinkLevel {
        ThinkLevel.named(c.level) ?? ThinkLevel.named(agent?.level) ?? settings.defaultLevel
    }

    // MARK: - Envoi et réponse

    /// Envoie `text`. `voice` : le message a été dicté (la réponse sera lue).
    /// `images` : les photos jointes (noms de fichiers, voir `saveImages`).
    func send(_ id: String, text: String, context: String? = nil, voice: Bool = false, images: [String] = []) {
        guard let c = open[id], !isRunning(id) else { return }
        let typed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty || !images.isEmpty else { return }
        var content = typed
        // « /nom arguments » : la commande installée, avec ses arguments.
        var command: String?
        if let cmd = ChatLibrary.expandCommand(typed, library: agents.library) {
            content = cmd.content
            command = cmd.command
        }
        var agent = c.agentId.flatMap { agents.agent($0) }
        var by: String?
        // « @agent … » : ce sous-agent répond à ce message.
        if let name = ChatLogic.mention(in: content), let who = agents.named(name) {
            agent = who
            by = "\(who.emoji) \(who.name)"
        }
        mutate(id) { c in
            c.messages.append(ChatMessage(role: .user, content: content, command: command, images: images))
            if c.messages.filter({ $0.role == .user }).count == 1 {
                c.title = typed.isEmpty ? (images.count > 1 ? "Photos" : "Photo") : ChatLogic.quickTitle(command ?? typed)
            }
            c.updated = Date()
        }
        speech?.stopSpeaking()
        let speak = ChatLogic.speaks(voice: voice, speakReplies: settings.speakReplies, text: text)
        respond(id, agent: agent, by: by, context: context, speak: speak)
    }

    /// Refait la dernière réponse.
    func regenerate(_ id: String) {
        guard let c = open[id], !isRunning(id) else { return }
        // Des images créées : on en crée de nouvelles pour la même description.
        if let last = c.messages.last, last.role == .assistant, last.imagePrompt != nil {
            redoImages(id, messageId: last.id)
            return
        }
        let removed = c.messages.reversed().prefix(while: { $0.role == .assistant }).flatMap(\.images)
        mutate(id) { c in
            while c.messages.last?.role == .assistant { c.messages.removeLast() }
        }
        imageFiles.delete(removed)
        guard open[id]?.messages.isEmpty == false else { return }
        respond(id, agent: c.agentId.flatMap { agents.agent($0) }, by: nil, context: nil)
    }

    /// Modifie un message de l'utilisateur et relance à partir de lui.
    func editAndResend(_ id: String, messageId: UUID, text: String) {
        stop(id)
        // Les photos du message modifié restent jointes ; celles des messages
        // suivants (retirés) sont supprimées.
        var kept: [String] = []
        var removed: [String] = []
        if let c = open[id], let i = c.messages.firstIndex(where: { $0.id == messageId }) {
            kept = c.messages[i].images
            removed = c.messages[i...].flatMap(\.images).filter { !kept.contains($0) }
        }
        mutate(id) { c in
            if let i = c.messages.firstIndex(where: { $0.id == messageId }) {
                c.messages.removeSubrange(i...)
            }
        }
        imageFiles.delete(removed)
        send(id, text: text, images: kept)
    }

    func stop(_ id: String) {
        BackgroundWork.shared.jobs.release("chat:\(id)")
        runIds[id] = nil
        tasks.removeValue(forKey: id)?.cancel()
        running.remove(id)
        speech?.stopSpeaking()
    }

    /// `loaded` : les skills demandées pendant ce tour (affichées sur la réponse) ;
    /// `round` : combien de fois l'assistant a déjà demandé des skills.
    private func respond(_ id: String, agent: Agent?, by: String?, context: String?, loaded: [String] = [], round: Int = 0, speak: Bool = false) {
        guard let c = open[id] else { return }
        let ref = settings.resolve(agent?.model ?? c.model)
        guard let provider = settings.provider(ref.providerId) else { return }
        let apiKey = settings.key(provider.id)
        let level = level(for: c, agent: agent)
        let (plain, dropped) = ChatLogic.recentHistory(c.messages, budgetTokens: settings.contextTokens)
        trimmed[id] = dropped
        // Les photos des derniers messages partent avec eux (dans un budget limité).
        let files = imageFiles
        let history = ChatImages.attach(plain, from: c.messages, dropped: dropped, load: { files.llmImage($0) })
        let system = ChatLogic.systemPrompt(
            agent: agent, personal: settings.personalSystem(), customInstructions: settings.customInstructions,
            level: level,
            context: ChatLibrary.context(context, skills: ChatLibrary.skillsPrompt(skills: agents.skills, loaded: c.skills, round: round))
        )
        let answer = ChatMessage(role: .assistant, content: "", model: ref.key, by: by, skills: loaded)
        let answerId = answer.id
        mutate(id) { $0.messages.append(answer) }
        running.insert(id)
        // L'app reste en vie le temps de finir la réponse, même cachée.
        BackgroundWork.shared.jobs.hold("chat:\(id)", title: "Réponse en cours", text: c.title)
        let runId = UUID()
        runIds[id] = runId
        let price = Catalog.price(provider: provider.id, model: ref.model)
        let options = LLMOptions(temperature: settings.temperature, maxTokens: level.maxTokens, level: level)
        let speech = self.speech
        speech?.rate = settings.voiceRate
        let llm = self.llm
        let usage = self.usage
        let onHeaders = usage?.headersHandler(providerId: provider.id)

        tasks[id] = Task { @MainActor [weak self] in
            var text = ""
            var thinking = ""
            var tokens = TokenUsage.zero
            var inputChars = 0
            var failed: Error?
            var lastFlush = ContinuousClock.now
            var spoken = 0

            @MainActor func flush(final: Bool = false) {
                guard let self else { return }
                let tin = tokens.input > 0 ? tokens.input : (inputChars + 3) / 4
                let tout = tokens.output > 0 && final ? tokens.output : (text.count + thinking.count + 3) / 4
                self.mutate(id, now: final) { c in
                    guard let i = c.messages.firstIndex(where: { $0.id == answerId }) else { return }
                    c.messages[i].content = text
                    c.messages[i].thinking = thinking
                    c.messages[i].tokensIn = tin
                    c.messages[i].tokensOut = tout
                    c.messages[i].estimated = !(final && tokens.total > 0)
                    c.messages[i].cost = price?.cost(tin, tout)
                    c.updated = Date()
                }
                // La lecture à voix haute avance phrase par phrase pendant la réponse ;
                // une demande de skill n'est pas lue : on attend la vraie réponse.
                if speak, failed == nil, let speech, !ChatLibrary.hasSkillRequest(text) {
                    spoken = speech.speakNew(text, from: spoken, all: final)
                }
            }

            // Une partie de la réponse. Si le modèle est coupé par sa limite de
            // longueur, on lui demande la suite, ajoutée au même message.
            var part = 0
            // Le modèle a refusé les images : la suite part sans elles.
            var imagesRefused = false
            while part <= ChatLogic.maxContinuations {
                let continuing = part > 0
                var messages = imagesRefused ? ChatImages.withoutImages(history) : history
                if continuing {
                    messages += [LLMMessage("assistant", text), LLMMessage("user", ChatLogic.continuePrompt(text))]
                }
                // Une image compte pour ~1 500 tokens dans l'estimation.
                inputChars += system.count + messages.reduce(0) { $0 + $1.content.count + $1.images.count * 6000 }
                var opts = options
                if continuing { opts.level = .faible }
                var stop: String?
                var head = ""
                var stitching = continuing
                do {
                    for try await d in llm.stream(provider: provider, apiKey: apiKey, model: ref.model, messages: messages, system: system, options: opts, onHeaders: onHeaders) {
                        if let s = d.stop { stop = s }
                        if let n = d.notice {
                            imagesRefused = true
                            self?.notices[id] = n
                        }
                        if stitching {
                            head += d.text
                            if head.count >= 200 {
                                stitching = false
                                text += ChatLogic.stitch(text, head)
                            }
                        } else {
                            text += d.text
                        }
                        thinking += d.thinking
                        if let u = d.usage { tokens = tokens + u }
                        if ContinuousClock.now - lastFlush > .milliseconds(60) {
                            lastFlush = .now
                            flush()
                        }
                    }
                } catch {
                    if !(error is CancellationError) { failed = error }
                }
                if stitching { text += ChatLogic.stitch(text, head) }
                if Task.isCancelled || failed != nil { break }
                if isCutStop(stop) && !text.isEmpty && part < ChatLogic.maxContinuations {
                    part += 1
                    flush()
                    continue
                }
                break
            }
            guard let self else { return }
            let stopped = Task.isCancelled || self.runIds[id] != runId
            if let failed {
                usage?.recordError(provider.id, failed)
                let msg = failed.localizedDescription
                text = text.isEmpty ? msg : text + "\n\n⚠️ " + msg
            }
            flush(final: true)
            if failed != nil {
                // Une réponse interrompue n'affiche pas de faux compteur.
                self.mutate(id, now: true) { c in
                    if let i = c.messages.firstIndex(where: { $0.id == answerId }) {
                        c.messages[i].error = true
                        c.messages[i].tokensIn = 0
                        c.messages[i].tokensOut = 0
                        c.messages[i].cost = nil
                    }
                }
            }
            // Une réponse complète est comptée chez le fournisseur qui l'a donnée.
            if failed == nil && !Task.isCancelled && !text.isEmpty, let usage {
                usage.recordUsage(
                    provider.id, model: ref.model, usage: tokens.total > 0 ? tokens : nil,
                    inputChars: inputChars, outputChars: text.count + thinking.count
                )
                // Le solde chez le fournisseur est relu : il bouge avec chaque réponse.
                usage.refreshSoon(provider, key: apiKey)
            }
            // L'assistant demande une skill : on la charge et il répond avec.
            if failed == nil && !Task.isCancelled && round < 2 && self.runIds[id] == runId {
                let wanted = ChatLibrary.requestedSkills(text, library: self.agents.library, already: self.open[id]?.skills ?? [])
                if !wanted.isEmpty {
                    self.mutate(id) { c in
                        c.messages.removeAll { $0.id == answerId }
                        c.skills += wanted
                    }
                    self.respond(id, agent: agent, by: by, context: context, loaded: loaded + wanted, round: round + 1, speak: speak)
                    return
                }
            }
            if stopped {
                // Arrêtée en route avant tout texte : la bulle vide disparaît.
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && thinking.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    self.mutate(id, now: true) { c in c.messages.removeAll { $0.id == answerId } }
                }
            } else if failed == nil && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // Finie sans rien : le modèle est sans doute indisponible.
                self.mutate(id, now: true) { c in
                    if let i = c.messages.firstIndex(where: { $0.id == answerId }) {
                        c.messages[i].error = true
                        c.messages[i].content = ChatLogic.emptyAnswer(model: ref.model, provider: provider.name)
                        c.messages[i].tokensIn = 0
                        c.messages[i].tokensOut = 0
                        c.messages[i].cost = nil
                    }
                }
            } else if speak && failed == nil, let speech {
                // Tout est lu : la conversation vocale peut écouter de nouveau.
                speech.enqueue("") { [weak self] in
                    guard let self else { return }
                    self.spokenTurn = (id, (self.spokenTurn?.count ?? 0) + 1)
                }
            }
            // Une nouvelle réponse a pu démarrer entre-temps : on ne touche qu'à la sienne.
            if self.runIds[id] == runId {
                self.runIds[id] = nil
                self.running.remove(id)
                self.tasks[id] = nil
                BackgroundWork.shared.jobs.release("chat:\(id)")
            }
        }
    }
}

// MARK: - Images

extension ChatStore {
    /// Enregistre des photos sur l'appareil ; rend leurs noms (à passer à `send`).
    func saveImages(_ data: [Data]) -> [String] {
        data.compactMap { try? imageFiles.save($0) }
    }

    /// L'avis de la conversation a été montré.
    func dismissNotice(_ id: String) { notices[id] = nil }

    /// La clé OpenAI enregistrée (pour créer des images avec OpenAI).
    var openAIImageKey: String? {
        let k = settings.key("openai")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return k.isEmpty ? nil : k
    }

    /// Le moteur qui créera les images, d'après les réglages et la clé OpenAI.
    var imageEngine: ImageGenEngine {
        ImageGenEngine.named(settings.imageEngine).resolved(hasOpenAIKey: openAIImageKey != nil)
    }

    /// `/image [nombre] description` : crée 1 à 4 images dans la conversation.
    func createImages(_ id: String, prompt: String, count: Int) {
        guard open[id] != nil, !isRunning(id) else { return }
        let p = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !p.isEmpty else { return }
        let n = min(max(count, 1), ImageGenCommand.maxCount)
        mutate(id) { c in
            c.messages.append(ChatMessage(role: .user, content: p, command: n > 1 ? "/image \(n)" : "/image"))
            if c.messages.filter({ $0.role == .user }).count == 1 { c.title = ChatLogic.quickTitle("🎨 " + p) }
            c.updated = Date()
        }
        speech?.stopSpeaking()
        generateImages(id, prompt: p, count: n)
    }

    /// « Refaire » : de nouvelles images pour la même description. La dernière
    /// réponse est remplacée ; une plus ancienne est refaite à la suite.
    func redoImages(_ id: String, messageId: UUID) {
        guard let c = open[id], !isRunning(id),
              let i = c.messages.firstIndex(where: { $0.id == messageId }),
              let prompt = c.messages[i].imagePrompt else { return }
        let count = max(c.messages[i].imageCount, c.messages[i].images.count, 1)
        if i == c.messages.count - 1 {
            let old = c.messages[i].images
            mutate(id) { $0.messages.removeAll { $0.id == messageId } }
            imageFiles.delete(old)
            generateImages(id, prompt: prompt, count: count)
        } else {
            createImages(id, prompt: prompt, count: count)
        }
    }

    private func generateImages(_ id: String, prompt: String, count: Int) {
        let engine = ImageGenEngine.named(settings.imageEngine)
        let shape = ImageGenShape.named(settings.imageShape)
        let key = openAIImageKey
        let base = settings.provider("openai")?.baseUrl ?? ImageGenClient.openAIBase
        let resolved = engine.resolved(hasOpenAIKey: key != nil)
        let modelKey = resolved == .openai
            ? "openai::\(ImageGenClient.openAIModel)" : "pollinations::\(ImageGenClient.pollinationsModel)"
        let answer = ChatMessage(role: .assistant, content: "", model: modelKey, imagePrompt: prompt, imageCount: count)
        let answerId = answer.id
        mutate(id) { $0.messages.append(answer) }
        running.insert(id)
        BackgroundWork.shared.jobs.hold("chat:\(id)", title: count > 1 ? "Création des images" : "Création de l'image", text: prompt)
        let runId = UUID()
        runIds[id] = runId
        let client = imageGen
        let files = imageFiles
        let usage = self.usage

        tasks[id] = Task { @MainActor [weak self] in
            var result: ImageGenResult?
            var failed: Error?
            do {
                result = try await client.generate(
                    prompt: prompt, count: count, shape: shape, engine: engine, openAIKey: key, openAIBase: base
                )
            } catch {
                if !(error is CancellationError) { failed = error }
            }
            // Les images sont écrites sur l'appareil hors du fil principal.
            var names: [String] = []
            if let made = result, !Task.isCancelled {
                names = await Task.detached { made.images.compactMap { try? files.save($0.data) } }.value
            }
            guard let self else {
                files.delete(names)
                return
            }
            let stopped = Task.isCancelled || self.runIds[id] != runId
            if stopped {
                // Arrêtée en route : la réponse vide disparaît.
                files.delete(names)
                self.mutate(id, now: true) { c in c.messages.removeAll { $0.id == answerId } }
            } else if let made = result, !names.isEmpty {
                var text = ImageGenCommand.caption(prompt: prompt, made: names.count, requested: count)
                if let note = made.note { text += "\n\n" + note }
                self.mutate(id, now: true) { c in
                    guard let i = c.messages.firstIndex(where: { $0.id == answerId }) else { return }
                    c.messages[i].content = text
                    c.messages[i].images = names
                    c.messages[i].model = made.modelKey
                    c.messages[i].cost = made.cost
                    c.updated = Date()
                }
            } else {
                let error = failed ?? LLMError("Aucune image n'a pu être enregistrée sur l'appareil.")
                if resolved == .openai { usage?.recordError("openai", error) }
                self.mutate(id, now: true) { c in
                    guard let i = c.messages.firstIndex(where: { $0.id == answerId }) else { return }
                    c.messages[i].error = true
                    c.messages[i].content = error.localizedDescription
                }
            }
            if self.runIds[id] == runId {
                self.runIds[id] = nil
                self.running.remove(id)
                self.tasks[id] = nil
                BackgroundWork.shared.jobs.release("chat:\(id)")
            }
        }
    }
}
