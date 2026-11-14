import Foundation
import Testing
@testable import NexoraKit

/// Les corrections d'audit de l'app Flutter : arrêt immédiat, instructions du
/// dernier tour, brouillons modifiés pendant l'envoi, chemins détournés, rapports
/// de l'app, dépenses attribuées au bon modèle, historique raccourci.
@Suite("Agent : cas limites")
@MainActor
struct AgentAuditTests {
    func commitHub(_ calls: Locked<[String]>? = nil, onCommit: (@Sendable () -> Void)? = nil) -> Routes {
        Routes { c in
            calls?.update { $0.append("\(c.method) \(c.path)") }
            let p = c.path
            if p.contains("/git/trees/") && c.method == "GET" { return (200, #"{"tree":[]}"#) }
            if p.contains("/git/ref/heads/") { return (200, #"{"object":{"sha":"p0"}}"#) }
            if p.contains("/git/commits/") { return (200, #"{"tree":{"sha":"t0"}}"#) }
            if p.hasSuffix("/git/trees") { return (201, #"{"sha":"t1"}"#) }
            if p.hasSuffix("/git/commits") {
                onCommit?()
                return (201, #"{"sha":"c123456789"}"#)
            }
            if p.contains("/git/refs") { return (201, "{}") }
            if p.hasSuffix("/pulls") {
                let url = "https://github.com" + p.replacingOccurrences(of: "/repos", with: "") + "/1"
                return (201, LooseJSON.string(["id": 1, "number": 1, "title": "t", "html_url": url, "state": "open", "user": ["login": "max"]]))
            }
            return notFound
        }
    }

    @Test("Arrêter : l'agent s'arrête tout de suite, sans attendre le modèle")
    func stopNow() async {
        let llm = ScriptLLM(replies: [.hang])
        let run = makeRun(llm, hub: Routes { _ in (200, #"{"tree":[]}"#) }, repo: "a")
        let done = Task { await run.run() }
        while llm.count == 0 { try? await Task.sleep(for: .milliseconds(5)) }
        #expect(run.running)
        run.stop()
        await done.value
        #expect(!run.running)
        #expect(run.steps.last?.text == "Arrêté.")
    }

    @Test("une instruction pendant le dernier tour relance le travail")
    func steerDuringLastTurn() async {
        let llm = ScriptLLM()
        let box = Locked<AgentRun?>(nil)
        llm.onRequest = { n in
            if n == 0 { await MainActor.run { box.get()?.steer("Ajoute un README") } }
        }
        llm.byModel = { n, _, _ in .text(act(["tool": "finish", "args": ["summary": "fini \(n + 1)"]])) }
        let run = makeRun(llm, hub: Routes { _ in (200, #"{"tree":[]}"#) }, repo: "a")
        box.set(run)
        await run.run()
        // Fini sans rien faire pour l'instruction : l'agent est relancé une fois.
        #expect(llm.count == 3)
        #expect(run.summary == "fini 3")
        #expect(run.history.filter { $0.content.hasPrefix("NOUVELLE INSTRUCTION") && $0.content.contains("Ajoute un README") }.count == 1)
    }

    @Test("plusieurs dépôts : un dépôt sans pull request n'est jamais envoyé en direct")
    func noDirectPush() async throws {
        let calls = Locked<[String]>([])
        let run = makeRun(hub: commitHub(calls), repo: "a", extra: [RepoTarget("max", "b", "main")])
        run.pulls["max/a"] = "https://github.com/max/a/pull/1"
        run.heads["max/a"] = "nexora/x"
        run.changes.set("b/README.md", "B\n")
        let results = try await run.commitAll(message: "m", targetBranch: "nexora/y", openPr: true)
        #expect(results.count == 1 && results[0].isPull)
        #expect(calls.get().contains("PATCH /repos/max/b/git/refs/heads/nexora/y"))
        #expect(!calls.get().contains("PATCH /repos/max/b/git/refs/heads/main"))
        #expect(run.pulls.keys.contains("max/a") && run.pulls.keys.contains("max/b"))
        #expect(run.changes.isEmpty)
    }

    @Test("un brouillon modifié pendant l'envoi reste un brouillon")
    func editedDuringSend() async throws {
        let box = Locked<AgentRun?>(nil)
        let hub = commitHub(onCommit: {
            let semaphore = DispatchSemaphore(value: 0)
            Task { @MainActor in
                box.get()?.changes.set("a.css", "v2\n")
                semaphore.signal()
            }
            semaphore.wait()
        })
        let run = makeRun(hub: hub, task: "t")
        box.set(run)
        run.changes.set("a.css", "v1\n")
        // Le commit se fait hors du fil principal : il reste libre pour la
        // modification faite pendant l'envoi.
        try await run.commitAll(message: "m", targetBranch: "nexora/x", openPr: true)
        #expect(run.draft("a.css") == "v2\n") // pas perdu
        #expect(run.orig("a.css") == "v1\n") // ce qui est vraiment parti
    }

    @Test("ce qui a été envoyé est gardé avec la session")
    func sentKept() {
        let run = makeRun(hub: FakeHub().transport)
        run.bases.set("a.css", "base\n")
        run.setOriginal("a.css", "envoyé\n")
        #expect((run.toJSON()["originals"] as? [String: Any])?["a.css"] as? String == "envoyé\n")
    }

    @Test("outil github : pas de contournement par « .. » ni par /merges")
    func traversal() {
        let run = makeRun(hub: FakeHub().transport)
        for p in ["/repos/max/site/x/../pulls/1/merge", "/repos/max/site/x/%2e%2e/pulls/1/merge", "/repos/max/site/x/..", "/repos/max/site/x/../../autre"] {
            #expect(run.githubDenied("PUT", p) != nil, "\(p)")
            #expect(run.githubDenied("GET", p) != nil, "\(p)")
        }
        #expect(run.githubDenied("POST", "/repos/max/site/merges") != nil)
        #expect(run.githubDenied("POST", "/repos/max/site/branches/main/rename") != nil)
    }

    @Test("après une fusion, les copies du dépôt sont oubliées")
    func forgetAfterMerge() async {
        let run = makeRun(hub: FakeHub().transport)
        run.changes.set("a.css", "x\n")
        #expect(await run.shipForCi(every: .zero) == nil)
        #expect(run.merged.count == 1)
        #expect(run.bases.isEmpty)
        #expect(!run.originals.keys.contains("a.css"))
    }

    @Test("un fichier qui contient des blocs ``` reste entier dans ```` ; CRLF")
    func fences() {
        let reply = "```json\n{\"tool\":\"write_file\",\"args\":{\"path\":\"README.md\"}}\n```\n````markdown\n# Titre\n\n```sh\ncargo run\n```\n\nFin.\n````"
        #expect(parseToolCalls(reply).first?.args["content"] as? String == "# Titre\n\n```sh\ncargo run\n```\n\nFin.\n")
        let crlf = parseToolCalls("```json\r\n{\"tool\":\"write_file\",\"args\":{\"path\":\"a\"}}\r\n```\r\n```\r\nA\r\n```")
        #expect(crlf.first?.args["content"] as? String == "A\n")
    }

    @Test("un rapport de CI de l'app n'est pas une demande ; arrêté, l'app ne relance rien")
    func appReport() async {
        let llm = ScriptLLM()
        llm.whenEmpty = "```json\n{\"tool\":\"finish\",\"args\":{\"summary\":\"corrigé\"}}\n```"
        let run = makeRun(llm, hub: Routes { _ in (200, #"{"tree":[]}"#) }, task: "Titre en bleu")
        run.history.append(LLMMessage("user", "Tâche : Titre en bleu"))
        run.history.append(LLMMessage("assistant", "ok"))
        await run.run(followUp: "Les tests GitHub ont échoué…", fromApp: true)
        #expect(run.requests == ["Titre en bleu"])
        #expect(!run.steps.contains { $0.kind == .user })
        run.stop()
        let before = run.steps.count
        await run.run(followUp: "Encore un rapport", fromApp: true)
        #expect(run.steps.count == before)
        #expect(await run.watchCi() == nil)
    }

    @Test("une vérification annulée ou en attente d'action n'est pas réussie")
    func checkRuns() {
        func r(_ c: String) -> CheckRun { CheckRun(id: 1, name: "x", status: "completed", conclusion: c) }
        #expect(r("cancelled").failed)
        #expect(r("action_required").failed)
        #expect(!r("success").failed)
        #expect(!r("skipped").failed)
        #expect(!CheckRun(id: 1, name: "x", status: "in_progress").failed)
    }

    @Test("les anciens résultats d'outils sont raccourcis")
    func compact() {
        var history = [LLMMessage("user", "Tâche")]
        for _ in 0..<12 {
            history.append(LLMMessage("assistant", "{\"tool\":\"read_file\"}"))
            history.append(LLMMessage("user", "Résultat de read_file :\n" + String(repeating: "z", count: 5000)))
        }
        AgentRun.compactHistory(&history)
        let results = history.filter { $0.content.hasPrefix("Résultat de") }
        let old = 12 - AgentRun.keepFullResults
        #expect(results.prefix(old).allSatisfy { $0.content.len < 600 })
        #expect(results.dropFirst(old).allSatisfy { $0.content.len > 5000 })
    }

    @Test("un ancien résultat raccourci garde son début, coupé en fin de ligne")
    func briefHead() {
        let file = (1...80).map { "import 'package:app/module_\($0).dart';" }.joined(separator: "\n")
        var history = [LLMMessage("user", "Tâche")]
        for _ in 0..<(AgentRun.keepFullResults + 1) {
            history.append(LLMMessage("assistant", "{\"tool\":\"read_file\"}"))
            history.append(LLMMessage("user", "Résultat de read_file :\n" + file))
        }
        AgentRun.compactHistory(&history)
        let old = history[2].content
        let head = String(old[..<old.range(of: "\n… (ancien résultat raccourci")!.lowerBound])
        #expect(head.count <= AgentRun.briefKeep && head.count >= AgentRun.briefKeep / 2)
        // Des lignes entières seulement.
        #expect(head.components(separatedBy: "\n").dropFirst().allSatisfy { $0.hasSuffix(";") })
        #expect(old.contains("relis le fichier si besoin"))
        // Sans fin de ligne assez loin : coupé net.
        #expect(AgentRun.briefHead(String(repeating: "z", count: 900)).count == AgentRun.briefKeep)
        #expect(AgentRun.briefHead("court") == "court")
    }

    @Test("après la bascule, les dépenses vont au modèle qui a répondu, l'erreur à celui qui a échoué")
    func attribution() async {
        let openrouter = Catalog.providers.first { $0.id == "openrouter" }!
        func build() -> (AgentRun, Locked<[String]>, Locked<[String]>, Locked<[String]>) {
            let llm = ScriptLLM()
            llm.dynamic = { _, _, host in
                host == "api.groq.com" ? .error(402, #"{"error":{"message":"no credit"}}"#)
                    : .text("```json\n{\"tool\": \"finish\", \"args\": {\"summary\": \"Fait\"}}\n```")
            }
            let usage = Locked<[String]>([]), errors = Locked<[String]>([]), headers = Locked<[String]>([])
            let run = makeRun(llm, hub: Routes { _ in (200, #"{"tree":[]}"#) }, task: "Ajoute une page contact", checks: false)
            run.model = "llama"
            run.onUsage = { p, m, _ in usage.update { $0.append("\(p.id)::\(m)") } }
            run.onError = { p, _ in errors.update { $0.append(p.id) } }
            run.onHeaders = { p, _ in headers.update { $0.append(p.id) } }
            return (run, usage, errors, headers)
        }
        let (run, usage, errors, _) = build()
        run.fallback = { _, tried in tried.contains("openrouter::gpt") ? nil : (openrouter, "k2", "gpt") }
        await run.run()
        #expect(run.summary == "Fait")
        #expect(run.provider.id == "openrouter")
        #expect(errors.get() == ["groq"])
        #expect(!usage.get().isEmpty)
        #expect(Set(usage.get()) == ["openrouter::gpt"])

        let (r2, u2, e2, _) = build()
        r2.provider = openrouter
        r2.apiKey = "k2"
        r2.model = "gpt"
        await r2.run()
        #expect(r2.summary == "Fait")
        #expect(e2.get().isEmpty)
        #expect(Set(u2.get()) == ["openrouter::gpt"])
    }

    @Test("skills et sous-agents : chargés à la demande, délégation avec rapport")
    func skillsAndDelegates() async {
        let skill = Skill(id: "s1", name: "tests-rust", description: "Écrire des tests Rust", body: "Utilise #[test].", files: ["exemple.rs"])
        let sub = Agent(id: "a2", name: "Relecteur Code", systemPrompt: "Tu relis le code.", description: "Relit le code")
        let llm = ScriptLLM([
            act(["actions": [
                ["tool": "use_skill", "args": ["name": "tests-rust"]],
                ["tool": "read_skill_file", "args": ["skill": "tests-rust", "path": "exemple.rs"]],
                ["tool": "delegate", "args": ["agent": "relecteur-code", "task": "Relis fn a() {}"]],
            ]]),
            "Rapport : tout va bien.",
            act(["tool": "finish", "args": ["summary": "ok"]]),
        ])
        let run = makeRun(llm, hub: Routes { _ in (200, #"{"tree":[]}"#) }, checks: false)
        run.skills = [skill]
        run.subagents = [sub]
        run.readSkillFile = { s, f in "contenu de \(f) (\(s.name))" }
        await run.run()
        let sys = llm.prompt(0)
        #expect(sys.contains("- use_skill : charge une skill"))
        #expect(sys.contains("- tests-rust : Écrire des tests Rust"))
        #expect(sys.contains("- relecteur-code : Relit le code"))
        let results = llm.messages(llm.count - 1).last?["content"] ?? ""
        #expect(results.contains("# Skill « tests-rust »"))
        #expect(results.contains("contenu de exemple.rs (tests-rust)"))
        #expect(results.contains("Rapport de Relecteur Code :\nRapport : tout va bien."))
        #expect(run.summary == "ok")
    }

    @Test("un agent limité à quelques outils ne voit qu'eux (avec les alias de Claude Code)")
    func agentTools() {
        let agent = Agent(id: "x", name: "Lecteur", systemPrompt: "Tu lis.", tools: ["Read", "Grep"])
        let run = makeRun(hub: Routes { _ in notFound }, agent: agent)
        let sys = run.system
        #expect(sys.contains("- read_file :"))
        #expect(sys.contains("- find_in_file :"))
        #expect(sys.contains("- search_code :"))
        #expect(sys.contains("- finish :"))
        #expect(!sys.contains("- write_file :"))
        #expect(!sys.contains("- github :"))
        #expect(sys.contains("Tu lis."))
    }

    @Test("consigne de l'agent : courte et sans phrase en double")
    func systemNoDuplicates() {
        let run = makeRun(hub: FakeHub().transport, task: "Ajoute une page contact")
        let sys = run.system
        // 7 407 caractères avant le dédoublonnage (3.0.43), 7 061 après.
        #expect(sys.count <= 7_100, "\(sys.count)")
        let sentences = sys.components(separatedBy: CharacterSet(charactersIn: ".:\n"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.count >= 40 }
        #expect(Set(sentences).count == sentences.count)
        #expect(sys.contains("utilise edit_file plutôt que de le réécrire"))
        #expect(sys.contains("court, en français"))
    }

    @Test("rappel de la demande : court, avec la demande et finish")
    func shortReminder() {
        let run = makeRun(hub: FakeHub().transport, task: "Ajoute une page contact")
        let r = run.reminder
        // 269 caractères avant le raccourcissement (3.0.45), 210 après.
        #expect(r.count <= 215, "\(r.count)")
        #expect(r.hasPrefix(AgentRun.reminderMark))
        #expect(r.contains("« Ajoute une page contact »"))
        #expect(r.contains("\"demande\"") && r.contains("finish"))
    }
}
