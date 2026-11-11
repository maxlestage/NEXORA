import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import NexoraKit

// Les tests de l'atelier : sessions, routines, brouillons, arrière-plan (ports de
// `sessions_test.dart`, `routines_test.dart`, `drafts_test.dart`,
// `background_test.dart` et de la logique de `draft_review_widget_test.dart`).

/// Une date locale (comme `DateTime(2026, 11, 10, 11)` en Dart).
private func local(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0, _ s: Int = 0) -> Date {
    Calendar.current.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min, second: s))!
}

private func routine(
    every: Int = 60, start: Int = 11 * 60, end: Int? = nil, runner: RoutineRunner = .app
) -> Routine {
    Routine(
        id: "r1", name: "Optimiser", task: "Optimise l'app et corrige les bugs", repos: ["max/site@main"],
        everyMinutes: every, startMinute: start, endMinute: end, runner: runner,
        createdAt: local(2026, 11, 10, 8)
    )
}

/// Une horloge réglable.
@MainActor
private final class TestClock {
    var now: Date

    init(_ now: Date) {
        self.now = now
    }
}

/// Des préférences vides, propres au test.
private func freshDefaults() -> UserDefaults {
    let name = "nexora-tests-\(UUID().uuidString)"
    let d = UserDefaults(suiteName: name)!
    d.removePersistentDomain(forName: name)
    return d
}

/// Une barrière : les requêtes attendent qu'elle s'ouvre.
private actor Gate {
    private var open = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if open { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        open = true
        for w in waiters { w.resume() }
        waiters = []
    }
}

/// Attend qu'une condition soit vraie (au plus 5 s).
@MainActor
private func until(_ cond: @MainActor () -> Bool) async {
    for _ in 0..<500 where !cond() {
        try? await Task.sleep(for: .milliseconds(10))
    }
}

/// L'app vue par les sessions : réglages, compte GitHub, agents, usage.
@MainActor
final class FakeHost: SessionHost {
    var github: GitHubAPI
    var signedIn = true
    var keys: [String: String] = ["groq": "k"]
    var defaultModel = ModelRef("groq", "m")
    var defaultLevel: ThinkLevel = .moyen
    var agentAutoCi = true
    var agentAutoMerge = true
    var skills: [Skill] = []
    var subagents: [Agent] = []
    var headers: [String] = []
    var usage: [String] = []
    var errors: [String] = []

    init(hub: HTTPTransport = repoHub(["README.md": "# Site\n"])) {
        var gh = GitHubAPI(token: "t", transport: hub)
        gh.retryPause = .zero
        github = gh
    }

    func provider(_ id: String) -> ProviderDef? { Catalog.providers.first { $0.id == id } }
    func key(_ providerId: String) -> String? { keys[providerId] }

    func resolve(_ wanted: String?) -> ModelRef {
        for c in [wanted, defaultModel.key] {
            if let r = ModelRef.parse(c), provider(r.providerId) != nil { return r }
        }
        return .fallback
    }

    func agent(_ id: String?) -> Agent? { Catalog.builtinAgents.first { $0.id == id } }
    func readSkillFile(_ skill: Skill, _ file: String) async throws -> String { "" }

    func fallback(_ error: Error, _ tried: Set<String>) async -> (ProviderDef, String?, String)? {
        SessionFallback.pick(
            SessionFallback.candidates(
                defaultModel: defaultModel, providers: Catalog.providers, key: key,
                models: { p in p.defaultModels.map { ModelInfo($0) } }
            ),
            tried: tried, provider: provider, key: key
        )
    }

    func recordHeaders(_ provider: ProviderDef, _ headers: [String: String]) { self.headers.append(provider.id) }
    func recordUsage(_ provider: ProviderDef, _ model: String, _ usage: TokenUsage) { self.usage.append("\(provider.id)::\(model)") }
    func recordError(_ provider: ProviderDef, _ error: Error) { errors.append(provider.id) }
}

/// Les sessions de test : faux modèle, sans attente, sans tests obligatoires.
@MainActor
private func makeSessions(
    _ llm: ScriptLLM, host: FakeHost = FakeHost(), files: any SessionFiles = MemorySessionFiles(),
    background: BackgroundJobs? = nil
) -> AgentSessions {
    let s = AgentSessions(
        host: host, llm: LLMClient(transport: llm, retryDelay: { _, _ in .zero }), files: files,
        background: background
    ) { run in
        run.checks = false
        run.compile = false
        run.retryPause = .zero
    }
    s.saveDelay = .milliseconds(20)
    s.ciEvery = .zero
    s.ciNoneAfter = .zero
    return s
}

private let finish = "```json\n{\"tool\":\"finish\",\"args\":{\"summary\":\"ok\"}}\n```"

// MARK: - Routines

@Suite("Routines : planning et workflow")
struct RoutineScheduleTests {
    @Test("planning : toutes les 30 min à partir de 11 h, jour et nuit")
    func everyHalfHour() {
        let r = routine(every: 30)
        #expect(r.times.count == 48)
        #expect(r.nextAfter(local(2026, 11, 10, 10, 50)) == local(2026, 11, 10, 11))
        #expect(r.nextAfter(local(2026, 11, 10, 23, 45)) == local(2026, 11, 11))
        #expect(r.scheduleLabel == "Toutes les 30 min, à partir de 11:00, 24 h/24")
    }

    @Test("planning : toutes les heures de 11 h à 23 h, puis le lendemain")
    func window() {
        let r = routine(end: 23 * 60)
        #expect(r.times.first == 11 * 60)
        #expect(r.times.last == 23 * 60)
        #expect(r.times.count == 13)
        #expect(r.nextAfter(local(2026, 11, 10, 23, 30)) == local(2026, 11, 11, 11))
        #expect(r.scheduleLabel == "Toutes les heures, de 11:00 à 23:00")
        // Une plage qui passe minuit.
        let night = routine(start: 22 * 60, end: 2 * 60)
        #expect(night.times == [0, 60, 120, 22 * 60, 23 * 60])
    }

    @Test("libellés : tous les jours, toutes les 2 h")
    func labels() {
        #expect(routine(every: 1440, start: 9 * 60 + 5).scheduleLabel == "Tous les jours à 09:05")
        #expect(routine(every: 120).scheduleLabel == "Toutes les 2 h, à partir de 11:00, 24 h/24")
        #expect(WorkspaceText.interval(30) == "30 min")
        #expect(WorkspaceText.interval(180) == "3 h")
        #expect(WorkspaceText.interval(1440) == "1 jour")
    }

    @Test("planning GitHub (cron en UTC, Paris = UTC+1 en hiver)")
    func cron() {
        #expect(routine().cron(utcOffset: 60) == "0 * * * *")
        #expect(routine(every: 1440, start: 9 * 60 + 15).cron(utcOffset: 60) == "15 8 * * *")
        #expect(routine(end: 13 * 60).cron(utcOffset: 60) == "0 10,11,12 * * *")
    }

    @Test("cron : des minutes différentes ne se mélangent pas")
    func cronMinutes() {
        // 11:30, 12:00, 12:30 … 23:00 : un seul cron ajouterait 11:00 et 23:30.
        let r = routine(every: 30, start: 11 * 60 + 30, end: 23 * 60)
        let lines = r.crons(utcOffset: 0)
        #expect(lines == [
            "0 12,13,14,15,16,17,18,19,20,21,22,23 * * *",
            "30 11,12,13,14,15,16,17,18,19,20,21,22 * * *",
        ])
        // Chaque heure prévue est couverte par une ligne, et rien de plus.
        var fired = Set<Int>()
        for l in lines {
            let f = l.split(separator: " ")
            for m in f[0].split(separator: ",") {
                for h in f[1].split(separator: ",") { fired.insert(Int(h)! * 60 + Int(m)!) }
            }
        }
        #expect(fired.sorted() == r.times)
        let y = routine(every: 30, start: 11 * 60 + 30, end: 23 * 60, runner: .github).workflowYaml(utcOffset: 0)
        #expect(y.components(separatedBy: "- cron:").count - 1 == 2)
    }

    @Test("workflow GitHub : planifié, avec la mission par défaut")
    func workflow() {
        let y = routine(runner: .github).workflowYaml(utcOffset: 60)
        #expect(y.contains("schedule:\n    - cron: '0 * * * *'"))
        #expect(y.contains("workflow_dispatch:"))
        #expect(y.contains("NEXORA_TASK: \"Optimise l'app et corrige les bugs\""))
        #expect(y.contains("github.event.inputs.instruction || env.NEXORA_TASK"))
        #expect(!y.contains("required: true"))
        // L'entrée « instruction » reste déclarée (facultative).
        #expect(y.contains("instruction:\n        description: \"Ce que l'agent doit faire\"\n        required: false"))
        #expect(y.contains("name: \"NEXORA · Routine · Optimiser\""))
        #expect(y.hasPrefix("# Routine NEXORA « Optimiser » : toutes les heures, à partir de 11:00, 24 h/24 (heure du téléphone).\n"))
        #expect(y.contains("env:\n  NEXORA_TASK:"))
        // Pas d'expression GitHub injectée par la mission.
        var evil = routine()
        evil.task = "${{ secrets.X }}"
        #expect(!evil.workflowYaml(utcOffset: 0).contains("${{ secrets.X }}"))
        #expect(routine().workflowFile == "nexora-routine-r1.yml")
        #expect(Routine.slug("Mon Agent_2!") == "mon-agent-2-")
    }

    @Test("enregistrement : même JSON que l'app Flutter")
    func json() {
        var r = routine(end: 23 * 60, runner: .github)
        r.model = "groq::m"
        r.lastRun = local(2026, 11, 10, 9)
        let back = Routine.decodeList(Routine.encodeList([r]))
        #expect(back == [r])
        // Un enregistrement de l'app Flutter (heure locale sans fuseau).
        let dart = #"[{"id":"7","name":"Nuit","task":"t","repos":["a/b@dev"],"model":null,"level":"eleve","enabled":false,"every":30,"start":1320,"end":120,"runner":"github","cloudAgent":"codex","autoCi":true,"autoMerge":false,"lastRun":"2026-11-10T09:00:00.000","lastSession":null,"createdAt":"2026-11-01T08:00:00.000"}]"#
        let f = Routine.decodeList(dart).first!
        #expect(f.enabled == false && f.everyMinutes == 30 && f.endMinute == 120 && f.runner == .github)
        #expect(f.cloudAgent == "codex" && f.autoMerge == false && f.level == "eleve")
        #expect(f.lastRun == local(2026, 11, 10, 9))
        #expect(f.targets == [RepoTarget("a", "b", "dev")])
        #expect(Routine.decodeList("pas du json").isEmpty)
        #expect(routine().targets == [RepoTarget("max", "site", "main")])
    }

    @Test("« aujourd'hui à », « demain à », « le j/m à »")
    func when() {
        let now = local(2026, 11, 10, 10)
        #expect(WorkspaceText.when(local(2026, 11, 10, 11), now: now) == "aujourd'hui à 11:00")
        #expect(WorkspaceText.when(local(2026, 11, 11, 9, 30), now: now) == "demain à 09:30")
        #expect(WorkspaceText.when(local(2026, 11, 14, 8), now: now) == "le 14/11 à 08:00")
    }
}

@Suite("Routines : sur le téléphone et sur GitHub")
@MainActor
struct RoutineBookTests {
    @Test("activer / désactiver un workflow sur GitHub")
    func workflowSwitch() async throws {
        let hub = Routes { _ in (204, "") }
        let api = GitHubAPI(token: "t", transport: hub)
        try await api.setWorkflowEnabled("max", "site", workflowFile: "nexora-routine-r1.yml", enabled: false)
        try await api.setWorkflowEnabled("max", "site", workflowFile: "nexora-routine-r1.yml", enabled: true)
        #expect(hub.calls == [
            "PUT /repos/max/site/actions/workflows/nexora-routine-r1.yml/disable",
            "PUT /repos/max/site/actions/workflows/nexora-routine-r1.yml/enable",
        ])
    }

    @Test("sur le téléphone : la routine lance une session à l'heure, sans s'empiler, et se désactive")
    func onPhone() async {
        let gate = Gate()
        let llm = ScriptLLM()
        llm.whenEmpty = finish
        llm.onRequest = { _ in await gate.wait() }
        let defaults = freshDefaults()
        let sessions = makeSessions(llm)
        await sessions.ready()
        let clock = TestClock(local(2026, 11, 10, 10, 30))
        let routines = RoutineBook(defaults: defaults, sessions: sessions, clock: { clock.now })
        var r = routine()
        r.lastRun = clock.now
        await routines.save(r)

        // Pas encore l'heure.
        await routines.check()
        #expect(sessions.sessions.isEmpty)

        // 11 h : une session démarre avec la mission.
        clock.now = local(2026, 11, 10, 11, 0, 5)
        await routines.check()
        #expect(sessions.sessions.count == 1)
        let run = sessions.sessions[0]
        #expect(run.task == r.task)
        #expect(run.autoCi && run.autoMerge)
        #expect(routines.byId("r1")?.lastSession == run.id)
        await until { run.running }

        // 12 h : la précédente travaille encore → pas de deuxième session.
        clock.now = local(2026, 11, 10, 12, 0, 5)
        await routines.check()
        #expect(sessions.sessions.count == 1)
        await gate.release()
        await sessions.settle(run.id)
        #expect(!run.running)

        // Désactivée : plus rien, même en retard.
        await routines.setEnabled("r1", false)
        clock.now = local(2026, 11, 10, 15)
        await routines.check()
        #expect(sessions.sessions.count == 1)

        // Gardée au prochain lancement.
        let again = RoutineBook(defaults: defaults, sessions: sessions)
        #expect(again.routines.count == 1)
        #expect(again.routines[0].enabled == false)
        #expect(again.routines[0].everyMinutes == 60)
        #expect(again.activeCount == 0)
    }

    @Test("réactivée : pas de rattrapage ; une nouvelle passe une fois les heures manquées")
    func noCatchUpStorm() async {
        let llm = ScriptLLM()
        llm.whenEmpty = finish
        let sessions = makeSessions(llm)
        let clock = TestClock(local(2026, 11, 10, 18))
        let routines = RoutineBook(defaults: freshDefaults(), sessions: sessions, clock: { clock.now })
        var r = routine()
        r.lastRun = local(2026, 11, 10, 9)
        await routines.save(r)
        // Plusieurs passages manqués : rattrapés une seule fois.
        await routines.check()
        #expect(sessions.sessions.count == 1)
        await sessions.settle(sessions.sessions[0].id)
        await routines.check()
        #expect(sessions.sessions.count == 1)
        // Désactivée puis réactivée à 20 h 30 : prochain passage à 21 h.
        await routines.setEnabled("r1", false)
        clock.now = local(2026, 11, 10, 20, 30)
        await routines.setEnabled("r1", true)
        await routines.check()
        #expect(sessions.sessions.count == 1)
        #expect(routines.byId("r1")?.nextRun() == local(2026, 11, 10, 21))
    }

    @Test("sur GitHub : workflow écrit, activé, lancé ; erreurs gardées par routine")
    func onGitHub() async {
        let hub = Routes { c in
            if c.method == "GET" && c.path.contains("/contents/") { return notFound }
            if c.method == "PUT" && c.path.contains("/contents/") { return (201, #"{"content":{"sha":"s1"}}"#) }
            if c.path.hasSuffix("/enable") || c.path.hasSuffix("/disable") { return notFound }
            if c.path.hasSuffix("/dispatches") { return (204, "") }
            return notFound
        }
        let host = FakeHost(hub: hub)
        let sessions = makeSessions(ScriptLLM(), host: host)
        let routines = RoutineBook(defaults: freshDefaults(), sessions: sessions, clock: { local(2026, 11, 10, 10) })
        let r = routine(runner: .github)
        // Tout juste créé (404 à l'activation) : accepté pour une routine active.
        #expect(await routines.save(r) == nil)
        #expect(hub.calls.contains("PUT /repos/max/site/contents/.github/workflows/nexora-routine-r1.yml"))
        // Désactivée : le 404 n'est plus acceptable.
        let err = await routines.setEnabled("r1", false)
        #expect(err?.contains("404") == true)
        #expect(routines.errors["r1"] != nil)
        #expect(await routines.runNow("r1") == nil)
        #expect(hub.calls.contains("POST /repos/max/site/actions/workflows/nexora-routine-r1.yml/dispatches"))
        // Sans GitHub : un message clair.
        host.signedIn = false
        #expect(await routines.syncGitHub(r) == "Connectez GitHub pour une routine sur GitHub.")
        host.signedIn = true
        await routines.delete("r1")
        #expect(routines.routines.isEmpty)
        #expect(routines.errors["r1"] == nil)
        #expect(hub.calls.last == "PUT /repos/max/site/actions/workflows/nexora-routine-r1.yml/disable")
    }

    @Test("reprise des routines de l'app Flutter")
    func flutterRoutines() {
        let d = freshDefaults()
        d.set(Routine.encodeList([routine()]), forKey: "flutter.routines")
        let routines = RoutineBook(defaults: d, sessions: makeSessions(ScriptLLM()))
        #expect(routines.routines.map(\.name) == ["Optimiser"])
    }
}

// MARK: - Sessions

@Suite("Sessions : enregistrement, reprise, pilotage")
@MainActor
struct SessionsTests {
    @Test("session enregistrée puis rechargée")
    func savedAndReloaded() async {
        let defaults = freshDefaults()
        let store = DefaultsSessionFiles(defaults: defaults)
        let run = AgentRun(
            llm: LLMClient(), github: GitHubAPI(token: nil), provider: groq, apiKey: nil,
            model: "llama-3.3-70b-versatile", owner: "max", repo: "galerie", branch: "main", task: "Galerie 3D",
            extraRepos: [RepoTarget("max", "paquets", "master")]
        )
        run.steps.append(AgentStep(.thought, "Je regarde"))
        run.history.append(LLMMessage("user", "Tâche"))
        run.changes.set("galerie/a.txt", "A\n")
        run.originals["galerie/a.txt"] = .some(nil)
        run.pulls["max/galerie"] = "https://github.com/max/galerie/pull/1"
        run.running = true // l'app est fermée pendant le travail
        await store.save(run.id, SessionJSON.encode(run.toJSON())!)

        let sessions = makeSessions(ScriptLLM(), files: store)
        await sessions.ready()
        #expect(!sessions.loading)
        let back = sessions.sessions[0]
        #expect(sessions.sessions.count == 1)
        #expect(back.id == run.id)
        #expect(back.targets.map(\.fullName) == ["max/galerie", "max/paquets"])
        #expect(back.changes.keys == ["galerie/a.txt"])
        #expect(back.changes.get("galerie/a.txt") == .some("A\n"))
        #expect(back.steps.map(\.text) == ["Je regarde"])
        #expect(back.history.map(\.content) == ["Tâche"])
        #expect(back.pulls.values.first?.contains("/pull/1") == true)
        #expect(back.interrupted)
        #expect(back.status == .review)

        sessions.delete(back.id)
        await sessions.flush()
        #expect(await store.loadAll().isEmpty)
        #expect(sessions.byId(run.id) == nil)
    }

    @Test("fournisseur retiré ou fichier abîmé : session ignorée")
    func unreadable() async {
        let files = MemorySessionFiles()
        await files.save("x", Data("pas du json".utf8))
        await files.save("y", json: ["id": "y", "provider": "inconnu", "repos": [["o": "a", "n": "b", "b": "main"]]])
        let sessions = makeSessions(ScriptLLM(), files: files)
        await sessions.ready()
        #expect(sessions.sessions.isEmpty)
    }

    @Test("dans un dossier : un fichier par session, relu au lancement")
    func fileStore() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("nexora-sessions-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let files = FileSessionFiles(directory: dir)
        #expect(await files.loadAll().isEmpty)
        await files.save("s1", json: ["id": "s1", "task": "a"])
        await files.save("s1", json: ["id": "s1", "task": "b"])
        await files.save("s2", json: ["id": "s2", "task": "c"])
        try Data("{abîmé".utf8).write(to: dir.appendingPathComponent("s3.json"))
        let all = await files.loadObjects().compactMap { $0["task"] as? String }.sorted()
        #expect(all == ["b", "c"])
        await files.delete("s1")
        #expect(await files.loadObjects().map { $0["id"] as? String } == ["s2"])
    }

    @Test("nouvelle session : modèle, effort, CI selon les réglages ; enregistrée à la fin")
    func start() async {
        let llm = ScriptLLM([
            act(["tool": "write_file", "args": ["path": "index.html", "content": "<canvas>"]]),
            act(["tool": "finish", "args": ["summary": "Galerie", "commit_message": "Galerie 3D"]]),
        ])
        let host = FakeHost()
        host.agentAutoCi = false
        host.defaultLevel = .eleve
        let files = MemorySessionFiles()
        let sessions = makeSessions(llm, host: host, files: files)
        let run = await sessions.start(task: "Galerie 3D", repos: [RepoTarget("max", "site", "main")], model: ModelRef("groq", "m"))!
        #expect(run.level == .eleve)
        #expect(run.maxSteps == ThinkLevel.eleve.agentSteps)
        #expect(!run.autoCi)
        #expect(run.autoMerge)
        #expect(run.apiKey == "k")
        await sessions.settle(run.id)
        #expect(run.status == .review)
        #expect(run.summary == "Galerie")
        #expect(sessions.runningCount == 0)
        await sessions.flush()
        let saved = await files.loadObjects()
        #expect(saved.count == 1)
        #expect(((saved[0]["changes"] as? [String: Any])?["index.html"] as? String)?.hasPrefix("<canvas>") == true)
        #expect(saved[0]["interrupted"] as? Bool == false)
        // L'effort de l'agent prime sur celui par défaut ; fournisseur inconnu : rien.
        #expect(await sessions.start(task: "t", repos: [RepoTarget("a", "b", "main")], model: ModelRef("inconnu", "m")) == nil)
        #expect(await sessions.start(task: "t", repos: [], model: ModelRef("groq", "m")) == nil)
    }

    @Test("continuer : instruction lue au tour suivant pendant le travail ; après, la boucle CI repart de zéro")
    func continueSession() async {
        let gate = Gate()
        let llm = ScriptLLM()
        llm.whenEmpty = finish
        llm.onRequest = { n in if n == 0 { await gate.wait() } }
        let host = FakeHost()
        host.agentAutoCi = false
        let sessions = makeSessions(llm, host: host)
        let run = await sessions.start(task: "Tâche", repos: [RepoTarget("max", "site", "main")], model: ModelRef("groq", "m"))!
        await until { run.running && llm.count == 1 }
        sessions.continueSession(run.id, "Ajoute un README")
        #expect(run.hasQueued)
        await gate.release()
        await sessions.settle(run.id)
        #expect(run.steps.contains { $0.kind == .user && $0.text == "Ajoute un README" })

        // Après un arrêt : une nouvelle instruction lève l'arrêt et remet la CI à zéro.
        run.stop()
        run.ciRounds = 7
        run.ciNote = "x"
        host.keys["groq"] = "nouvelle"
        sessions.continueSession(run.id, "Encore")
        #expect(!run.cancelled)
        #expect(run.ciRounds == 0)
        #expect(run.ciNote.isEmpty)
        #expect(run.apiKey == "nouvelle")
        await sessions.settle(run.id)
        #expect(run.steps.contains { $0.kind == .user && $0.text == "Encore" })
    }

    @Test("changer de modèle pendant la session ; supprimer ; compte GitHub changé")
    func modelAndDelete() async {
        let sessions = makeSessions(ScriptLLM())
        let run = AgentRun(
            llm: LLMClient(), github: GitHubAPI(token: nil), provider: groq, apiKey: "k", model: "m",
            owner: "o", repo: "r", branch: "main", task: "t"
        )
        sessions.debugAdd(run)
        let before = run.version
        sessions.setModel(run, ModelRef("mistral", "mistral-large-latest"), .max)
        #expect(run.provider.id == "mistral")
        #expect(run.model == "mistral-large-latest")
        #expect(run.level == .max)
        #expect(run.apiKey == nil)
        #expect(run.version > before)
        sessions.setModel(run, ModelRef("inconnu", "x"), .faible)
        #expect(run.provider.id == "mistral")
        sessions.githubChanged()
        #expect(run.github.token == "t")
        sessions.delete(run.id)
        #expect(sessions.sessions.isEmpty)
        #expect(run.cancelled)
    }

    @Test("au plus 80 sessions : les plus anciennes sans brouillon partent")
    func trim() async {
        let llm = ScriptLLM()
        llm.whenEmpty = finish
        let host = FakeHost()
        host.agentAutoCi = false
        let sessions = makeSessions(llm, host: host)
        var old: [AgentRun] = []
        for i in 0..<AgentSessions.keep {
            let r = AgentRun(
                llm: LLMClient(), github: GitHubAPI(token: nil), provider: groq, apiKey: "k", model: "m",
                owner: "o", repo: "r", branch: "main", task: "t\(i)", id: "s\(i)",
                createdAt: Date(timeIntervalSince1970: Double(1000 + i))
            )
            if i == 0 { r.changes.set("a.txt", "A") }
            sessions.debugAdd(r)
            old.append(r)
        }
        let run = await sessions.start(task: "nouvelle", repos: [RepoTarget("max", "site", "main")], model: ModelRef("groq", "m"))!
        #expect(sessions.sessions.count == AgentSessions.keep)
        // La plus ancienne a des brouillons : gardée ; la suivante part.
        #expect(sessions.byId("s0") != nil)
        #expect(sessions.byId("s1") == nil)
        #expect(sessions.byId(run.id) != nil)
        await sessions.settle(run.id)
    }

    @Test("modèle de repli : par défaut, puis fournisseurs avec clé, puis gratuits")
    func fallback() {
        let providers = Catalog.providers
        let keys = ["groq": "k", "mistral": ""]
        func key(_ id: String) -> String? { keys[id] }
        let c = SessionFallback.candidates(
            defaultModel: ModelRef("anthropic", "claude-x"), providers: providers, key: key,
            models: { p in p.defaultModels.map { ModelInfo($0) } }
        )
        #expect(c.first == ModelRef("anthropic", "claude-x"))
        #expect(c.suffix(2) == [ModelRef("pollinations", "openai"), ModelRef("pollinations", "openai-fast")])
        #expect(!c.contains { $0.providerId == "mistral" })
        #expect(!c.contains { $0.providerId == "ollama" })
        func provider(_ id: String) -> ProviderDef? { providers.first { $0.id == id } }
        #expect(c.contains { $0.providerId == "groq" })
        // Le modèle par défaut n'a pas de clé : le candidat suivant.
        let pick = SessionFallback.pick(c, tried: [], provider: provider, key: key)
        #expect(pick?.0.id == c[1].providerId)
        #expect(pick?.2 == c[1].model)
        // Tout essayé sauf Groq : Groq, avec sa clé.
        let tried = Set(c.filter { $0.providerId != "groq" }.map(\.key))
        let next = SessionFallback.pick(c, tried: tried, provider: provider, key: key)
        #expect(next?.0.id == "groq")
        #expect(next?.1 == "k")
        #expect(SessionFallback.pick(c, tried: Set(c.map(\.key)), provider: provider, key: key) == nil)
    }

    @Test("usage : au nom du fournisseur qui a répondu")
    func usage() async {
        let llm = ScriptLLM()
        llm.whenEmpty = finish
        let host = FakeHost()
        host.agentAutoCi = false
        let sessions = makeSessions(llm, host: host)
        let run = await sessions.start(task: "t", repos: [RepoTarget("max", "site", "main")], model: ModelRef("groq", "m"))!
        await sessions.settle(run.id)
        #expect(host.headers.contains("groq"))
    }
}

// MARK: - Arrière-plan

@MainActor
final class FakePlatform: BackgroundPlatform {
    var calls: [String] = []
    var isForeground = true

    func perform(_ call: BackgroundCall) { calls.append("\(call.method):\(call.title)") }
    func status() -> BackgroundStatus? { BackgroundStatus(mode: "continued") }
}

@Suite("Arrière-plan")
@MainActor
struct BackgroundTests {
    @Test("arrière-plan : démarre, suit, s'arrête et prévient")
    func lifecycle() async {
        let platform = FakePlatform()
        let bg = BackgroundJobs(platform: platform)
        bg.throttle = .milliseconds(50)
        bg.hold("session:1", title: "Session : galerie", done: 1, total: 24)
        #expect(platform.calls == ["start:Session : galerie"])

        bg.hold("chat:2", title: "Réponse en cours")
        await until { platform.calls.count > 1 }
        #expect(platform.calls.last == "update:NEXORA · 2 travaux en cours")

        // App au premier plan : pas de notification.
        bg.release("chat:2", doneTitle: "Réponse prête")
        #expect(!platform.calls.contains { $0.hasPrefix("notify") })
        #expect(bg.active)

        // App cachée : notification, puis arrêt.
        platform.isForeground = false
        bg.release("session:1", doneTitle: "Brouillons à valider")
        #expect(platform.calls.contains("notify:Brouillons à valider"))
        #expect(platform.calls.last == "stop:")
        #expect(!bg.active)
        // Déjà fini : rien.
        bg.release("session:1", doneTitle: "x")
        #expect(platform.calls.last == "stop:")
    }

    @Test("progression : compteur des mises à jour si le total est inconnu")
    func progress() async {
        final class Capture: BackgroundPlatform {
            var last: BackgroundCall?
            var isForeground = true
            func perform(_ call: BackgroundCall) { last = call }
            func status() -> BackgroundStatus? { nil }
        }
        let p = Capture()
        let bg = BackgroundJobs(platform: p)
        bg.throttle = .milliseconds(10)
        bg.hold("chat:1", title: "Réponse", text: "…")
        #expect(p.last == .start(title: "Réponse", text: "…", done: 1, total: 0))
        bg.hold("chat:1", title: "Réponse", text: "suite")
        await until { if case .update = p.last { true } else { false } }
        #expect(p.last == .update(title: "Réponse", text: "suite", done: 2, total: 0))
    }

    @Test("diagnostic affiché pendant le travail")
    func status() {
        #expect(BackgroundStatus(mode: "continued").note?.text == "Continue en arrière-plan : iOS suit la tâche.")
        #expect(BackgroundStatus(mode: "legacy", error: "refus").note?.text == "Arrière-plan court (~30 s) : refus.")
        #expect(BackgroundStatus(mode: "legacy").note?.text == "Arrière-plan court (~30 s).")
        #expect(BackgroundStatus(mode: "idle").note == nil)
    }

    @Test("une session qui travaille garde l'app en vie, et prévient à la fin")
    func sessionKeepsAlive() async {
        let platform = FakePlatform()
        platform.isForeground = false
        let bg = BackgroundJobs(platform: platform)
        let llm = ScriptLLM()
        llm.whenEmpty = finish
        let host = FakeHost()
        host.agentAutoCi = false
        let sessions = makeSessions(llm, host: host, background: bg)
        let run = await sessions.start(task: "Une galerie 3D", repos: [RepoTarget("max", "site", "main")], model: ModelRef("groq", "m"))!
        await sessions.settle(run.id)
        await until { platform.calls.last == "stop:" }
        #expect(platform.calls.first == "start:Session : Une galerie 3D")
        #expect(platform.calls.contains("notify:Session terminée"))
        #expect(platform.calls.last == "stop:")
    }
}

// MARK: - Brouillons et textes de l'atelier

@Suite("Brouillons et atelier")
@MainActor
struct DraftsTests {
    func bare() -> AgentRun {
        AgentRun(
            llm: LLMClient(), github: GitHubAPI(token: nil), provider: Catalog.providers[0], apiKey: nil,
            model: "m", owner: "o", repo: "r", branch: "main", task: "t"
        )
    }

    @Test("comparaison ligne à ligne")
    func diff() {
        let d = lineDiff("a\nb\nc\nd\n", "a\nB\nc\nd\ne\n")
        #expect(d.added == 2)
        #expect(d.removed == 1)
        let short: [String] = d.lines.map { l in
            let k: String = switch l.kind {
            case .same: "s"
            case .added: "a"
            case .removed: "r"
            }
            return k + l.text
        }
        #expect(short == ["sa", "rb", "aB", "sc", "sd", "ae"])
        #expect(lineDiff(nil, "x\ny").added == 2)
        #expect(lineDiff("x\ny\n", nil).removed == 2)
        let before = (0..<30).map { "l\($0)" }.joined(separator: "\n")
        let after = before.replacingOccurrences(of: "l15\n", with: "L15\n")
        let rows = withContext(lineDiff(before, after).lines, context: 2)
        #expect(rows.first! == nil)
        #expect(rows.last! == nil)
        #expect(rows.compactMap { $0 }.count == 6)
    }

    @Test("brouillons acceptés, refusés et modifiés")
    func accepted() {
        let run = bare()
        run.changes.set("a.dart", "A\n")
        run.changes.set("b.dart", nil)
        run.changes.set("c.md", "C\n")
        #expect(run.accepted.count == 3)
        run.setAccepted("b.dart", false)
        #expect(run.accepted.keys == ["a.dart", "c.md"])
        run.setAllAccepted(false)
        #expect(run.accepted.isEmpty)
        run.editDraft("c.md", "C2\n")
        #expect(run.accepted.keys == ["c.md"])
        #expect(run.accepted.get("c.md") == .some("C2\n"))
        run.setAllAccepted(true)
        #expect(run.accepted.count == 3)
    }

    @Test("relire, refuser puis valider : libellés et comparaison")
    func review() async throws {
        let run = bare()
        run.changes.set("lib/a.dart", "un\ndeux bis\ntrois\n")
        run.changes.set("README.md", "# Nouveau\n")
        run.originals["lib/a.dart"] = .some("un\ndeux\ntrois\n")
        run.originals["README.md"] = .some(nil)
        #expect(WorkspaceText.validateLabel(run.accepted.count) == "Valider 2 brouillons")
        run.setAccepted("README.md", false)
        #expect(WorkspaceText.validateLabel(run.accepted.count) == "Valider 1 brouillon")
        #expect(WorkspaceText.validateLabel(0) == "Aucun brouillon accepté")
        let d = lineDiff(try await run.original("lib/a.dart"), run.changes.get("lib/a.dart") ?? nil)
        #expect(d.lines.contains { $0.kind == .added && $0.text == "deux bis" })
        #expect(try await run.original("README.md") == nil)
        #expect(run.stats.added == 2 && run.stats.removed == 1)
    }

    @Test("journal : chaque action avec son résultat, rapports de CI à part")
    func rows() {
        let steps = [
            AgentStep(.goal, "OBJECTIF : x"),
            AgentStep(.tool, "a.txt", tool: "read_file"),
            AgentStep(.result, "contenu", tool: "read_file"),
            AgentStep(.tool, "b.txt", tool: "edit_file"),
            AgentStep(.error, "introuvable", tool: "edit_file"),
            AgentStep(.tool, "c.txt", tool: "write_file"),
            AgentStep(.result, "🧪 Tests GitHub échoués", tool: "ci"),
            AgentStep(.done, "Fini"),
        ]
        let rows = WorkspaceText.rows(steps)
        #expect(rows.count == 6)
        #expect(rows[1] == .tool(steps[1], result: steps[2], index: 1))
        #expect(rows[2] == .tool(steps[3], result: steps[4], index: 3))
        #expect(rows[3] == .tool(steps[5], result: nil, index: 5))
        #expect(rows[4] == .ci(steps[6], index: 6))
        #expect(rows.map(\.id) == [0, 1, 3, 5, 6, 7])
        #expect(WorkspaceText.toolVerb("read_file") == "Lit")
        #expect(WorkspaceText.toolVerb("delegate") == "Délègue à")
        #expect(WorkspaceText.toolVerb("autre") == "autre")
        #expect(WorkspaceText.toolVerb(nil) == "Action")
        #expect(WorkspaceText.stepText(steps[1]) == "read_file a.txt")
    }

    @Test("textes : Markdown retiré, langage NEXORA découpé, dates relatives")
    func texts() {
        #expect(WorkspaceText.plain("## Titre\n**gras** et `code`") == "Titre\ngras et code")
        let spec = WorkspaceText.specLines("OBJECTIF : une galerie\n\nDEMANDES :\n1. un canvas\n  2. des tableaux  \nCRITÈRES DE RÉUSSITE : tests verts")
        #expect(spec == [
            .heading("OBJECTIF"), .text("une galerie"), .heading("DEMANDES"), .text("1. un canvas"),
            .text("2. des tableaux"), .heading("CRITÈRES DE RÉUSSITE"), .text("tests verts"),
        ])
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(WorkspaceText.ago(now.addingTimeInterval(-20), now: now) == "à l'instant")
        #expect(WorkspaceText.ago(now.addingTimeInterval(-5 * 60), now: now) == "il y a 5 min")
        #expect(WorkspaceText.ago(now.addingTimeInterval(-3 * 3600), now: now) == "il y a 3 h")
        #expect(WorkspaceText.ago(now.addingTimeInterval(-25 * 3600), now: now) == "hier")
        #expect(WorkspaceText.ago(now.addingTimeInterval(-72 * 3600), now: now) == "il y a 3 j")
        #expect(SessionStatus.review.label == "En attente de votre validation")
        #expect(WorkspaceText.header(.running, actions: 4, added: 12, removed: 3) == "En cours · 4 actions · +12 −3")
        #expect(WorkspaceText.header(.done, actions: 0, added: 0, removed: 0) == "Terminé · 0 actions")
        #expect(WorkspaceText.tileSubtitle(.running, reposLabel: "site") == "site · En cours")
        #expect(WorkspaceText.tileSubtitle(.review, reposLabel: "site") == "En attente de votre validation")
        #expect(WorkspaceText.draftsSummary(files: 3, added: 1, removed: 2, rejected: 1) == "3 fichier(s) · +1 −2 · 1 refusé(s)")
        #expect(WorkspaceText.routinesBanner(active: 2, total: 3) == "2 actives sur 3")
        #expect(WorkspaceText.routinesBanner(active: 0, total: 0) == "Relancer une mission toute seule, à intervalle régulier")
    }

    @Test("envoi : libellés et messages")
    func ship() {
        #expect(WorkspaceText.shipButton(hasPull: true, repos: 2, pr: false) == "Mettre à jour la pull request")
        #expect(WorkspaceText.shipButton(hasPull: false, repos: 2, pr: true) == "Ouvrir les pull requests")
        #expect(WorkspaceText.shipButton(hasPull: false, repos: 1, pr: false) == "Commit")
        let t = RepoTarget("o", "r", "main")
        #expect(WorkspaceText.shipToast([ShipResult(t, "abcdef123")], hasPull: false) == "Commit abcdef1 envoyé ✅")
        #expect(WorkspaceText.shipToast([ShipResult(t, "https://github.com/o/r/pull/1")], hasPull: false) == "Pull request ouverte 🎉")
        #expect(WorkspaceText.shipToast([ShipResult(t, "a"), ShipResult(t, "b")], hasPull: false) == "2 commits envoyés ✅")
        #expect(WorkspaceText.prSubtitle(pr: false, multi: false, branch: "main") == "Commit direct sur main")
        #expect(WorkspaceText.newBranch(Date(timeIntervalSince1970: 1234)) == "nexora/1234")
        let report = CiReport("s", state: .failed, runs: [CheckRun(id: 1, name: "test", status: "completed", conclusion: "failure")])
        #expect(WorkspaceText.ciCard("max/site", report, several: true).hasPrefix("site · Tests GitHub échoués ❌ : test\nL'agent corrige"))
    }

    @Test("travail resté sur une branche sans pull request")
    func stranded() {
        let run = bare()
        run.heads["o/r"] = "nexora/1"
        let note = WorkspaceText.strandedNote(run)
        #expect(run.stranded.isEmpty ? note.isEmpty : note.contains("r (nexora/1)"))
    }
}
