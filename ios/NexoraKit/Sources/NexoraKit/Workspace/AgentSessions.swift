import Foundation
import Observation

// # Les sessions de l'agent autonome (port de `app/lib/state/session_state.dart`)
//
// Comme dans Claude Code : chaque session a sa mission, un ou plusieurs dépôts,
// son historique et ses brouillons. Elles continuent de travailler quand vous
// quittez l'écran, restent enregistrées, et peuvent être reprises avec une
// nouvelle instruction. L'app branche ses réglages, son compte GitHub, ses agents
// et son suivi d'usage par `SessionHost`.

/// Ce que les sessions demandent à l'app : compte GitHub, fournisseurs et clés,
/// agents et skills, réglages par défaut, suivi d'usage.
@MainActor
public protocol SessionHost: AnyObject, Sendable {
    /// Le compte GitHub connecté (à jour).
    var github: GitHubAPI { get }
    var signedIn: Bool { get }
    func provider(_ id: String) -> ProviderDef?
    func key(_ providerId: String) -> String?
    /// Le modèle à utiliser : celui demandé s'il existe, sinon celui par défaut.
    func resolve(_ wanted: String?) -> ModelRef
    func agent(_ id: String?) -> Agent?
    /// Les skills et les sous-agents installés.
    var skills: [Skill] { get }
    var subagents: [Agent] { get }
    func readSkillFile(_ skill: Skill, _ file: String) async throws -> String
    /// Un autre modèle pour continuer quand celui de la session ne répond plus.
    func fallback(_ error: Error, _ tried: Set<String>) async -> (ProviderDef, String?, String)?
    var defaultLevel: ThinkLevel { get }
    var agentAutoCi: Bool { get }
    var agentAutoMerge: Bool { get }
    /// Le témoin de crédit, au nom du fournisseur qui a vraiment répondu.
    func recordHeaders(_ provider: ProviderDef, _ headers: [String: String])
    func recordUsage(_ provider: ProviderDef, _ model: String, _ usage: TokenUsage)
    func recordError(_ provider: ProviderDef, _ error: Error)
    /// Le fournisseur a déjà atteint sa limite ou épuisé son crédit (témoin de
    /// crédit) : la session commence directement avec un autre modèle.
    func blocked(_ providerId: String) -> Bool
}

public extension SessionHost {
    func blocked(_ providerId: String) -> Bool { false }
}

/// Le choix d'un modèle de repli (`SessionState._fallback`).
public enum SessionFallback {
    /// Les candidats, dans l'ordre : le modèle par défaut, puis chaque fournisseur
    /// qui a une clé (ses deux premiers modèles), puis les modèles gratuits sans clé.
    public static func candidates(
        defaultModel: ModelRef, providers: [ProviderDef], key: (String) -> String?,
        models: (ProviderDef) -> [ModelInfo]
    ) -> [ModelRef] {
        var out = [defaultModel]
        for p in providers where !p.local && (!p.needsKey || !(key(p.id) ?? "").isEmpty) {
            for m in models(p).prefix(2) { out.append(ModelRef(p.id, m.id)) }
        }
        out.append(ModelRef("pollinations", "openai"))
        out.append(ModelRef("pollinations", "openai-fast"))
        return out
    }

    /// Le premier candidat pas encore essayé, dont le fournisseur existe et a sa
    /// clé si elle est nécessaire.
    public static func pick(
        _ candidates: [ModelRef], tried: Set<String>, provider: (String) -> ProviderDef?,
        key: (String) -> String?
    ) -> (ProviderDef, String?, String)? {
        for c in candidates {
            if tried.contains(c.key) || tried.contains("\(c.providerId)::*") { continue }
            guard let p = provider(c.providerId) else { continue }
            let k = key(p.id)
            if p.needsKey && (k ?? "").isEmpty { continue }
            return (p, k, c.model)
        }
        return nil
    }
}

/// Les sessions de l'agent, enregistrées sur l'appareil.
@MainActor
@Observable
public final class AgentSessions {
    /// Les sessions gardées au plus (les plus anciennes, terminées, partent).
    public nonisolated static let keep = 80

    public let host: any SessionHost
    public let llm: LLMClient
    @ObservationIgnored let files: any SessionFiles

    /// Garde l'app en vie en arrière-plan pendant le travail.
    @ObservationIgnored public let background: BackgroundJobs?

    public private(set) var loading = true
    private var list: [AgentRun] = []

    @ObservationIgnored private var saveTimers: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var writes: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var drives: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var readyTask: Task<Void, Never>?

    /// Pendant le travail, enregistrée au plus une fois par…
    @ObservationIgnored public var saveDelay: Duration = .milliseconds(1500)
    /// Le suivi de la CI (attente entre deux lectures, abandon sans CI).
    @ObservationIgnored public var ciEvery: Duration = .seconds(15)
    @ObservationIgnored public var ciNoneAfter: Duration = .seconds(3 * 60)
    /// Appelé sur chaque session créée ou rechargée (tests : réglages de l'agent).
    @ObservationIgnored public var prepare: (@MainActor (AgentRun) -> Void)?

    public init(
        host: any SessionHost, llm: LLMClient, files: any SessionFiles, background: BackgroundJobs? = nil,
        prepare: (@MainActor (AgentRun) -> Void)? = nil
    ) {
        self.host = host
        self.llm = llm
        self.files = files
        self.background = background
        self.prepare = prepare
        readyTask = Task { [weak self] in await self?.load() }
    }

    /// Attend la lecture des sessions enregistrées.
    public func ready() async { await readyTask?.value }

    /// Les sessions, les plus récentes d'abord.
    public var sessions: [AgentRun] { list.sorted { $0.updatedAt > $1.updatedAt } }

    public func byId(_ id: String) -> AgentRun? { list.first { $0.id == id } }

    public var runningCount: Int { list.filter(\.running).count }

    /// La session fait toujours partie de la liste (pas supprimée).
    public func contains(_ run: AgentRun) -> Bool { list.contains { $0 === run } }

    private func load() async {
        for j in await files.loadObjects() {
            // Session illisible (fournisseur retiré…) : ignorée.
            guard let p = host.provider(j["provider"] as? String ?? "") else { continue }
            guard let run = AgentRun.restore(
                j, llm: llm, github: host.github, provider: p, apiKey: host.key(p.id),
                agent: host.agent(j["agent"] as? String),
                onHeaders: onHeaders, onUsage: onUsage, onError: onError
            ) else { continue }
            prepare?(run)
            equip(run)
            attach(run)
        }
        loading = false
    }

    // MARK: - Usage

    private var onHeaders: @MainActor @Sendable (ProviderDef, [String: String]) -> Void {
        { [weak self] p, h in self?.host.recordHeaders(p, h) }
    }

    private var onUsage: @MainActor @Sendable (ProviderDef, String, TokenUsage) -> Void {
        { [weak self] p, m, t in self?.host.recordUsage(p, m, t) }
    }

    private var onError: @MainActor @Sendable (ProviderDef, Error) -> Void {
        { [weak self] p, e in self?.host.recordError(p, e) }
    }

    /// Donne à l'agent les skills et les sous-agents installés (à jour), et le
    /// choix d'un modèle de repli.
    private func equip(_ run: AgentRun) {
        let host = host
        run.fallback = { e, tried in await host.fallback(e, tried) }
        run.isBlocked = { host.blocked($0) }
        run.skills = host.skills
        run.subagents = host.subagents
        run.readSkillFile = { s, f in try await host.readSkillFile(s, f) }
    }

    /// Ajoute une session telle quelle (tests, aperçus).
    public func debugAdd(_ run: AgentRun) { attach(run) }

    private func attach(_ run: AgentRun) {
        list.append(run)
        run.onChange = { [weak self, weak run] in
            guard let self, let run else { return }
            self.changed(run)
        }
    }

    private func detach(_ run: AgentRun) {
        run.onChange = nil
        saveTimers.removeValue(forKey: run.id)?.cancel()
        background?.release("session:\(run.id)")
    }

    private func changed(_ run: AgentRun) {
        // Une session supprimée ne doit plus être enregistrée (elle reviendrait).
        guard contains(run) else { return }
        backgroundWork(run)
        // Enregistrée au plus toutes les 1,5 s pendant le travail, tout de suite après.
        saveTimers.removeValue(forKey: run.id)?.cancel()
        if !run.running {
            persist(run)
        } else {
            let pause = saveDelay
            saveTimers[run.id] = Task { [weak self, weak run] in
                try? await Task.sleep(for: pause)
                guard !Task.isCancelled, let self, let run else { return }
                self.saveTimers[run.id] = nil
                self.persist(run)
            }
        }
    }

    /// Enregistre une session (les écritures d'une session passent dans l'ordre).
    private func persist(_ run: AgentRun) {
        guard let data = SessionJSON.encode(run.toJSON()) else { return }
        let id = run.id
        let files = files
        let previous = writes[id]
        writes[id] = Task {
            await previous?.value
            await files.save(id, data)
        }
    }

    /// Les enregistrements en attente : faits tout de suite (l'app passe en
    /// arrière-plan ou se ferme), puis attendus.
    public func flush() async {
        for (id, t) in saveTimers {
            t.cancel()
            if let run = byId(id) { persist(run) }
        }
        saveTimers = [:]
        for t in Array(writes.values) { await t.value }
    }

    /// En arrière-plan, l'app reste en vie tant qu'une session travaille, et prévient
    /// quand elle a fini.
    private func backgroundWork(_ run: AgentRun) {
        guard let background else { return }
        let key = "session:\(run.id)"
        let task = run.task.len > 60 ? run.task.sub(0, 60) + "…" : run.task
        if run.running {
            let last = run.steps.last
            let text: String
            if let last {
                text = last.kind == .tool
                    ? "\(last.tool ?? "null") \(last.text)"
                    : (last.text.components(separatedBy: "\n").first ?? "")
            } else {
                text = "Démarrage…"
            }
            background.hold(
                key,
                title: "Session : \(task)",
                text: text.len > 120 ? text.sub(0, 120) + "…" : text,
                done: run.steps.filter { $0.kind == .tool }.count,
                total: run.maxSteps
            )
        } else {
            let title: String
            switch run.status {
            case .review: title = "Brouillons à valider"
            case .stopped: title = "Session arrêtée"
            default: title = "Session terminée"
            }
            background.release(key, doneTitle: title, doneText: task)
        }
    }

    /// Le compte GitHub a changé : les sessions utilisent le nouveau.
    public func githubChanged() {
        for s in list { s.github = host.github }
    }

    // MARK: - Travail

    /// Démarre une nouvelle session (`nil` : fournisseur inconnu ou aucun dépôt).
    @discardableResult
    public func start(
        task: String, repos: [RepoTarget], model: ModelRef, agent: Agent? = nil, level: ThinkLevel? = nil,
        autoCi: Bool? = nil, autoMerge: Bool? = nil
    ) async -> AgentRun? {
        await ready()
        guard let p = host.provider(model.providerId), let first = repos.first else { return nil }
        let l = level ?? ThinkLevel.named(agent?.level) ?? host.defaultLevel
        let run = AgentRun(
            llm: llm, github: host.github, provider: p, apiKey: host.key(p.id), model: model.model,
            owner: first.owner, repo: first.name, branch: first.branch, task: task, agent: agent,
            level: l, maxSteps: l.agentSteps, extraRepos: Array(repos.dropFirst()),
            onHeaders: onHeaders, onUsage: onUsage, onError: onError
        )
        run.autoCi = autoCi ?? host.agentAutoCi
        run.autoMerge = autoMerge ?? host.agentAutoMerge
        prepare?(run)
        equip(run)
        attach(run)
        trim()
        drive(run)
        return run
    }

    /// Continue une session avec une nouvelle instruction (ou reprend une session
    /// interrompue, avec une instruction vide).
    public func continueSession(_ id: String, _ instruction: String) {
        guard let run = byId(id) else { return }
        // Pendant le travail ou l'envoi : l'instruction est mise en file et lue au
        // tour suivant (jamais deux travaux en même temps sur une session).
        if run.running || run.shipping {
            run.steer(instruction)
            return
        }
        // Une nouvelle instruction : la boucle CI repart de zéro, et un arrêt
        // précédent est levé.
        run.ciRounds = 0
        run.ciNote = ""
        run.cancelled = false
        // La clé ou le compte ont pu changer depuis.
        run.github = host.github
        run.apiKey = host.key(run.provider.id)
        equip(run)
        drive(run, followUp: instruction)
    }

    private func alive(_ run: AgentRun) -> @MainActor () -> Bool {
        { [weak self, weak run] in
            guard let self, let run else { return false }
            return self.contains(run)
        }
    }

    private var signedIn: @MainActor () -> Bool {
        { [weak self] in self?.host.signedIn ?? false }
    }

    /// Fait travailler l'agent, puis (si la session le prévoit) envoie son travail
    /// sur une branche de travail, attend la CI GitHub et lui renvoie chaque échec,
    /// jusqu'à ce que tout soit vert.
    @discardableResult
    private func drive(_ run: AgentRun, followUp: String? = nil, fromApp: Bool = false) -> Task<Void, Never> {
        let alive = alive(run)
        let signedIn = signedIn
        let every = ciEvery
        let noneAfter = ciNoneAfter
        let t = Task {
            await run.drive(
                followUp: followUp, fromApp: fromApp, alive: alive, signedIn: signedIn,
                every: every, noneAfter: noneAfter
            )
        }
        drives[run.id] = t
        return t
    }

    /// Attend la fin du dernier travail lancé sur une session (tests).
    public func settle(_ id: String) async {
        while let t = drives[id] {
            await t.value
            if drives[id] == t { break }
        }
    }

    /// Après un envoi : suit les tests GitHub, et s'ils échouent, renvoie l'agent
    /// corriger avec la fin des journaux (ses corrections reviennent en brouillons).
    public func verify(_ run: AgentRun) async {
        if run.shipping { return }
        let report = await run.watchCi(every: ciEvery, noneAfter: ciNoneAfter)
        guard let report, contains(run), !run.running, !run.shipping, !run.cancelled else { return }
        drive(run, followUp: report, fromApp: true)
    }

    /// Récupère le travail resté sur une branche sans pull request : en ouvre une,
    /// puis (si la session le prévoit) fait passer la CI et fusionne. Rend une erreur.
    public func recover(_ run: AgentRun) async -> String? {
        await run.recover(alive: alive(run), signedIn: signedIn)
    }

    /// Reprend la boucle CI d'une session (après une limite atteinte).
    public func retryCi(_ run: AgentRun) {
        let alive = alive(run)
        let signedIn = signedIn
        drives[run.id] = Task { await run.retryCi(alive: alive, signedIn: signedIn) }
    }

    /// Change le modèle (et l'effort) d'une session : pris en compte dès sa
    /// prochaine réponse, même pendant le travail.
    public func setModel(_ run: AgentRun, _ ref: ModelRef, _ level: ThinkLevel) {
        guard let p = host.provider(ref.providerId) else { return }
        run.provider = p
        run.apiKey = host.key(p.id)
        run.model = ref.model
        run.level = level
        run.notifyChanged()
    }

    public func stop(_ id: String) { byId(id)?.stop() }

    public func delete(_ id: String) {
        guard let run = byId(id) else { return }
        list.removeAll { $0 === run }
        detach(run)
        run.stop()
        remove(id)
    }

    /// Supprime le fichier, après les enregistrements en cours (sinon la session
    /// reviendrait).
    private func remove(_ id: String) {
        let files = files
        let previous = writes[id]
        writes[id] = Task {
            await previous?.value
            await files.delete(id)
        }
    }

    private func trim() {
        guard list.count > Self.keep else { return }
        let old = sessions.reversed().filter { !$0.running && $0.changes.isEmpty }.prefix(list.count - Self.keep)
        for s in old {
            list.removeAll { $0 === s }
            detach(s)
            remove(s.id)
        }
    }
}
