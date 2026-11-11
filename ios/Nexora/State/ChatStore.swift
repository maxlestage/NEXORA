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

    @ObservationIgnored private let store: ConversationStore
    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let agents: AgentLibrary
    @ObservationIgnored private let llm: LLMClient
    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var runIds: [String: UUID] = [:]
    @ObservationIgnored private var saveTasks: [String: Task<Void, Never>] = [:]
    var speech: SpeechService?

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
        open[id] = nil
        Task {
            try? await store.delete(id)
            await reloadIndex()
        }
    }

    func deleteAll() {
        for id in running { stop(id) }
        open.removeAll()
        Task {
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
        mutate(id, now: true) { $0.messages.removeAll() }
    }

    func level(for c: Conversation, agent: Agent?) -> ThinkLevel {
        ThinkLevel.named(c.level) ?? ThinkLevel.named(agent?.level) ?? settings.defaultLevel
    }

    // MARK: - Envoi et réponse

    func send(_ id: String, text: String, context: String? = nil) {
        guard let c = open[id], !isRunning(id) else { return }
        let typed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else { return }
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
            c.messages.append(ChatMessage(role: .user, content: content, command: command))
            if c.messages.filter({ $0.role == .user }).count == 1 { c.title = ChatLogic.quickTitle(command ?? typed) }
            c.updated = Date()
        }
        speech?.stopSpeaking()
        respond(id, agent: agent, by: by, context: context)
    }

    /// Refait la dernière réponse.
    func regenerate(_ id: String) {
        guard let c = open[id], !isRunning(id) else { return }
        mutate(id) { c in
            while c.messages.last?.role == .assistant { c.messages.removeLast() }
        }
        guard open[id]?.messages.isEmpty == false else { return }
        respond(id, agent: c.agentId.flatMap { agents.agent($0) }, by: nil, context: nil)
    }

    /// Modifie un message de l'utilisateur et relance à partir de lui.
    func editAndResend(_ id: String, messageId: UUID, text: String) {
        stop(id)
        mutate(id) { c in
            if let i = c.messages.firstIndex(where: { $0.id == messageId }) {
                c.messages.removeSubrange(i...)
            }
        }
        send(id, text: text)
    }

    func stop(_ id: String) {
        runIds[id] = nil
        tasks.removeValue(forKey: id)?.cancel()
        running.remove(id)
        speech?.stopSpeaking()
    }

    /// `loaded` : les skills demandées pendant ce tour (affichées sur la réponse) ;
    /// `round` : combien de fois l'assistant a déjà demandé des skills.
    private func respond(_ id: String, agent: Agent?, by: String?, context: String?, loaded: [String] = [], round: Int = 0) {
        guard let c = open[id] else { return }
        let ref = settings.resolve(agent?.model ?? c.model)
        guard let provider = settings.provider(ref.providerId) else { return }
        let apiKey = settings.key(provider.id)
        let level = level(for: c, agent: agent)
        let (history, dropped) = ChatLogic.recentHistory(c.messages, budgetTokens: settings.contextTokens)
        trimmed[id] = dropped
        let system = ChatLogic.systemPrompt(
            agent: agent, personal: settings.personalSystem(), customInstructions: settings.customInstructions,
            level: level,
            context: ChatLibrary.context(context, skills: ChatLibrary.skillsPrompt(skills: agents.skills, loaded: c.skills, round: round))
        )
        let answer = ChatMessage(role: .assistant, content: "", model: ref.key, by: by, skills: loaded)
        let answerId = answer.id
        mutate(id) { $0.messages.append(answer) }
        running.insert(id)
        let runId = UUID()
        runIds[id] = runId
        let price = Catalog.price(provider: provider.id, model: ref.model)
        let options = LLMOptions(temperature: settings.useTemperature ? settings.temperature : nil, maxTokens: level.maxTokens, level: level)
        let speak = settings.speakReplies
        let llm = self.llm

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
                // Une demande de skill n'est pas lue : on attend la vraie réponse.
                if speak, let speech = self.speech, !ChatLibrary.hasSkillRequest(text) {
                    spoken = speech.speakNew(text, from: spoken, all: final)
                }
            }

            // Une partie de la réponse. Si le modèle est coupé par sa limite de
            // longueur, on lui demande la suite, ajoutée au même message.
            var part = 0
            while part <= ChatLogic.maxContinuations {
                let continuing = part > 0
                var messages = history
                if continuing {
                    messages += [LLMMessage("assistant", text), LLMMessage("user", ChatLogic.continuePrompt(text))]
                }
                inputChars += system.count + messages.reduce(0) { $0 + $1.content.count }
                var opts = options
                if continuing { opts.level = .faible }
                var stop: String?
                var head = ""
                var stitching = continuing
                do {
                    for try await d in llm.stream(provider: provider, apiKey: apiKey, model: ref.model, messages: messages, system: system, options: opts) {
                        if let s = d.stop { stop = s }
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
            if let failed {
                let msg = failed.localizedDescription
                text = text.isEmpty ? msg : text + "\n\n⚠️ " + msg
            }
            flush(final: true)
            if failed != nil {
                self.mutate(id, now: true) { c in
                    if let i = c.messages.firstIndex(where: { $0.id == answerId }) { c.messages[i].error = true }
                }
            }
            // L'assistant demande une skill : on la charge et il répond avec.
            if failed == nil && !Task.isCancelled && round < 2 && self.runIds[id] == runId {
                let wanted = ChatLibrary.requestedSkills(text, library: self.agents.library, already: self.open[id]?.skills ?? [])
                if !wanted.isEmpty {
                    self.mutate(id) { c in
                        c.messages.removeAll { $0.id == answerId }
                        c.skills += wanted
                    }
                    self.respond(id, agent: agent, by: by, context: context, loaded: loaded + wanted, round: round + 1)
                    return
                }
            }
            // Arrêtée en route avant tout texte : la bulle vide disparaît.
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && thinking.isEmpty {
                self.mutate(id, now: true) { c in c.messages.removeAll { $0.id == answerId } }
            }
            // Une nouvelle réponse a pu démarrer entre-temps : on ne touche qu'à la sienne.
            if self.runIds[id] == runId {
                self.runIds[id] = nil
                self.running.remove(id)
                self.tasks[id] = nil
            }
        }
    }
}
