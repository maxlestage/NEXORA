import Foundation
import NexoraKit
import Observation

/// Ce que les sessions de l'agent demandent à l'app : réglages (fournisseurs,
/// clés, modèle et effort par défaut, CI), compte GitHub, agents et skills, suivi
/// d'usage (`SessionState` de l'app Flutter, côté dépendances).
@MainActor
final class AppSessionHost: SessionHost {
    let settings: SettingsStore
    let agents: AgentLibrary
    let account: GitHubSession
    let usage: UsageStore

    init(settings: SettingsStore, agents: AgentLibrary, account: GitHubSession, usage: UsageStore) {
        self.settings = settings
        self.agents = agents
        self.account = account
        self.usage = usage
    }

    var github: GitHubAPI { account.api }
    var signedIn: Bool { account.connected }

    func provider(_ id: String) -> ProviderDef? { settings.provider(id) }
    func key(_ providerId: String) -> String? { settings.key(providerId) }
    func resolve(_ wanted: String?) -> ModelRef { settings.resolve(wanted) }
    func agent(_ id: String?) -> Agent? { id.flatMap(agents.agent) }

    var skills: [Skill] { agents.skills }
    var subagents: [Agent] { agents.all }

    func readSkillFile(_ skill: Skill, _ file: String) async throws -> String {
        try await agents.readSkillFile(account.api, skill, file)
    }

    /// Un autre modèle pour continuer quand celui de la session ne répond plus :
    /// le modèle par défaut, puis chaque fournisseur qui a une clé (son meilleur
    /// modèle), puis les modèles gratuits sans clé.
    func fallback(_ error: Error, _ tried: Set<String>) async -> (ProviderDef, String?, String)? {
        let settings = settings
        let candidates = SessionFallback.candidates(
            defaultModel: settings.resolve(settings.defaultModel),
            providers: settings.providers,
            key: { settings.key($0) },
            models: { settings.models(for: $0) }
        )
        return SessionFallback.pick(candidates, tried: tried, provider: { settings.provider($0) }, key: { settings.key($0) })
    }

    var defaultLevel: ThinkLevel { settings.defaultLevel }
    var agentAutoCi: Bool { settings.agentAutoCi }
    var agentAutoMerge: Bool { settings.agentAutoMerge }

    /// Le témoin de crédit, au nom du fournisseur qui a vraiment répondu (celui
    /// de la session peut changer : bascule automatique, choix d'un autre modèle).
    func recordHeaders(_ provider: ProviderDef, _ headers: [String: String]) {
        usage.recordHeaders(provider.id, headers)
    }

    func recordUsage(_ provider: ProviderDef, _ model: String, _ usage: TokenUsage) {
        self.usage.recordUsage(provider.id, model: model, usage: usage)
        self.usage.refreshSoon(provider, key: settings.key(provider.id))
    }

    func recordError(_ provider: ProviderDef, _ error: Error) {
        usage.recordError(provider.id, error)
    }

    /// Limite atteinte ou crédit épuisé d'après le témoin : la session commence
    /// avec un autre modèle.
    func blocked(_ providerId: String) -> Bool {
        usage.of(providerId).level(Date()) == .blocked
    }
}

/// Les sessions de l'agent autonome (`state/session_state.dart`), comme dans
/// Claude Code : chacune a sa mission, un ou plusieurs dépôts, son historique et
/// ses brouillons. Elles continuent de travailler quand vous quittez l'écran,
/// restent enregistrées (Application Support/sessions, même format que l'app
/// Flutter), et peuvent être reprises avec une nouvelle instruction. Une session
/// interrompue par la fermeture de l'app revient au lancement, marquée
/// « interrompue » : elle reprend d'un toucher.
///
/// La logique est dans NexoraKit (`AgentSessions`) ; ici, le branchement aux
/// réglages, au compte GitHub, aux agents, à l'usage et à l'arrière-plan.
@MainActor
@Observable
final class SessionStore {
    let core: AgentSessions
    @ObservationIgnored let host: AppSessionHost

    init(
        settings: SettingsStore, agents: AgentLibrary, github: GitHubSession, usage: UsageStore,
        llm: LLMClient = LLMClient(),
        files: any SessionFiles = FileSessionFiles(directory: FileSessionFiles.defaultDirectory()),
        background: BackgroundJobs? = BackgroundWork.shared.jobs
    ) {
        let host = AppSessionHost(settings: settings, agents: agents, account: github, usage: usage)
        self.host = host
        core = AgentSessions(host: host, llm: llm, files: files, background: background)
    }

    /// Les sessions, les plus récentes d'abord.
    var sessions: [AgentRun] { core.sessions }
    var loading: Bool { core.loading }
    var runningCount: Int { core.runningCount }

    func byId(_ id: String) -> AgentRun? { core.byId(id) }

    func ready() async { await core.ready() }

    /// Démarre une nouvelle session (`nil` : modèle inconnu ou aucun dépôt).
    @discardableResult
    func start(
        task: String, repos: [RepoTarget], model: ModelRef, agent: Agent? = nil, level: ThinkLevel? = nil,
        autoCi: Bool? = nil, autoMerge: Bool? = nil
    ) async -> AgentRun? {
        await core.start(task: task, repos: repos, model: model, agent: agent, level: level, autoCi: autoCi, autoMerge: autoMerge)
    }

    /// Continue une session avec une nouvelle instruction (vide : reprend une
    /// session interrompue là où l'agent s'était arrêté).
    func continueSession(_ id: String, _ instruction: String) { core.continueSession(id, instruction) }

    /// Après un envoi : suit la CI et renvoie l'agent corriger si elle échoue.
    func verify(_ run: AgentRun) async { await core.verify(run) }

    /// Ouvre la pull request d'un travail resté sur une branche (rend une erreur).
    func recover(_ run: AgentRun) async -> String? { await core.recover(run) }

    func retryCi(_ run: AgentRun) { core.retryCi(run) }

    func setModel(_ run: AgentRun, _ ref: ModelRef, _ level: ThinkLevel) { core.setModel(run, ref, level) }

    func stop(_ id: String) { core.stop(id) }

    func delete(_ id: String) { core.delete(id) }

    /// Le compte GitHub a changé : les sessions utilisent le nouveau.
    func githubChanged() { core.githubChanged() }

    /// L'app passe en arrière-plan : les enregistrements en attente sont faits.
    func saveNow() {
        Task { await core.flush() }
    }
}
