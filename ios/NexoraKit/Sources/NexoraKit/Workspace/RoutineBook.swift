import Foundation
import Observation

// # Les routines (port de `app/lib/state/routine_state.dart`)
//
// Des missions relancées toutes seules à intervalle régulier, à activer,
// désactiver et configurer depuis l'app. Sur le téléphone, elles lancent une
// session de l'agent ; sur GitHub, un workflow planifié.

@MainActor
@Observable
public final class RoutineBook {
    /// La clé des préférences (texte JSON, comme l'app Flutter).
    public nonisolated static let storageKey = "routines"

    @ObservationIgnored let defaults: UserDefaults
    @ObservationIgnored public let sessions: AgentSessions
    @ObservationIgnored public var clock: @MainActor () -> Date
    @ObservationIgnored public var calendar: Calendar
    @ObservationIgnored private var ticker: Task<Void, Never>?

    public private(set) var routines: [Routine] = []

    /// La dernière erreur de synchronisation avec GitHub, par routine.
    public private(set) var errors: [String: String] = [:]

    public init(
        defaults: UserDefaults = .standard, sessions: AgentSessions,
        clock: @escaping @MainActor () -> Date = { Date() }, calendar: Calendar = .current
    ) {
        self.defaults = defaults
        self.sessions = sessions
        self.clock = clock
        self.calendar = calendar
        load()
    }

    var host: any SessionHost { sessions.host }

    public func byId(_ id: String) -> Routine? { routines.first { $0.id == id } }

    public var activeCount: Int { routines.filter(\.enabled).count }

    private func load() {
        // Les routines de l'app Flutter (même identifiant d'app sur iOS) sont reprises.
        let raw = defaults.string(forKey: Self.storageKey)
            ?? defaults.string(forKey: FlutterMigration.prefix + Self.storageKey)
        routines = Routine.decodeList(raw)
    }

    private func persist() {
        defaults.set(Routine.encodeList(routines), forKey: Self.storageKey)
    }

    private func put(_ r: Routine) {
        if let i = routines.firstIndex(where: { $0.id == r.id }) {
            routines[i] = r
        } else {
            routines.append(r)
        }
    }

    /// Le décalage du téléphone avec UTC, en minutes.
    var utcOffset: Int { calendar.timeZone.secondsFromGMT(for: clock()) / 60 }

    /// Lance la vérification toutes les 30 s ; au démarrage, les passages manqués
    /// sont rattrapés (une fois), après 5 s.
    public func startTicking(every: Duration = .seconds(30)) {
        ticker?.cancel()
        ticker = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            while !Task.isCancelled {
                await self?.check()
                try? await Task.sleep(for: every)
            }
        }
    }

    public func stopTicking() {
        ticker?.cancel()
        ticker = nil
    }

    /// Ajoute ou met à jour une routine (et son workflow si elle tourne sur
    /// GitHub). Rend une erreur de GitHub, s'il y en a une.
    @discardableResult
    public func save(_ r: Routine) async -> String? {
        put(r)
        persist()
        return await syncGitHub(r)
    }

    /// Active ou désactive une routine.
    @discardableResult
    public func setEnabled(_ id: String, _ on: Bool) async -> String? {
        guard var r = byId(id) else { return nil }
        r.enabled = on
        // Réactivée : pas de rattrapage de tout ce qui a été sauté entre-temps.
        if on { r.lastRun = clock() }
        put(r)
        persist()
        return await syncGitHub(r)
    }

    public func delete(_ id: String) async {
        guard let r = byId(id) else { return }
        routines.removeAll { $0.id == id }
        errors[id] = nil
        persist()
        if r.runner == .github {
            for t in r.targets {
                try? await host.github.setWorkflowEnabled(t.owner, t.name, workflowFile: r.workflowFile, enabled: false)
            }
        }
    }

    /// Sur GitHub : écrit le workflow planifié dans chaque dépôt, puis l'active ou
    /// le désactive comme la routine.
    @discardableResult
    public func syncGitHub(_ r: Routine) async -> String? {
        if r.runner != .github { return nil }
        if !host.signedIn { return "Connectez GitHub pour une routine sur GitHub." }
        let api = host.github
        let yaml = r.workflowYaml(utcOffset: utcOffset)
        do {
            for t in r.targets {
                let path = ".github/workflows/\(r.workflowFile)"
                var sha: String?
                do {
                    sha = try await api.readFile(t.owner, t.name, path: path, ref: t.branch).sha
                } catch let e as GitHubError {
                    if e.status != 404 { throw e }
                }
                _ = try await api.writeFile(
                    t.owner, t.name, path: path, content: yaml,
                    message: "NEXORA : routine « \(r.name) »", sha: sha, branch: t.branch
                )
                do {
                    try await api.setWorkflowEnabled(t.owner, t.name, workflowFile: r.workflowFile, enabled: r.enabled)
                } catch let e as GitHubError {
                    // Tout juste créé, GitHub peut ne pas encore le connaître : il est
                    // actif par défaut, ce qui convient pour une routine active.
                    if !(e.status == 404 && r.enabled) { throw e }
                }
            }
            errors[r.id] = nil
            return nil
        } catch {
            errors[r.id] = "\(error)"
            return "\(error)"
        }
    }

    /// Lance les routines du téléphone dont c'est l'heure.
    public func check() async {
        let now = clock()
        for r in routines where r.runner == .app && r.isDue(now, calendar: calendar) {
            await runNow(r.id, at: now)
        }
    }

    /// Lance une routine tout de suite (sur le téléphone : une session ; sur
    /// GitHub : son workflow). Rend la session lancée, s'il y en a une.
    @discardableResult
    public func runNow(_ id: String, at: Date? = nil) async -> AgentRun? {
        guard var r = byId(id) else { return nil }
        r.lastRun = at ?? clock()
        put(r)
        if r.runner == .github {
            persist()
            for t in r.targets {
                do {
                    try await host.github.dispatch(
                        t.owner, t.name, workflowFile: r.workflowFile, ref: t.branch, inputs: ["instruction": r.task]
                    )
                } catch {
                    errors[r.id] = "\(error)"
                }
            }
            return nil
        }
        // Le passage précédent travaille encore : on ne l'empile pas.
        if let last = r.lastSession, let previous = sessions.byId(last), previous.running || previous.shipping {
            persist()
            return nil
        }
        let targets = r.targets
        if targets.isEmpty || r.task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            persist()
            return nil
        }
        let run = await sessions.start(
            task: r.task, repos: targets, model: host.resolve(r.model), level: ThinkLevel.named(r.level),
            autoCi: r.autoCi, autoMerge: r.autoMerge
        )
        if let run, var now = byId(id) {
            now.lastSession = run.id
            put(now)
        }
        persist()
        return run
    }
}
