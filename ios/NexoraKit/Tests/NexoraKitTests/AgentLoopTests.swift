import Foundation
import Testing
@testable import NexoraKit

func thoughtAct(_ tool: String, _ args: [String: Any], _ content: String? = nil) -> String {
    act(["thought": "…", "tool": tool, "args": args]) + (content.map { "\n```\n\($0)\n```" } ?? "")
}

/// La boucle de travail : boucles et recherches en rond, demandes suivies,
/// instructions en cours de route, dépôts illisibles, contenus attendus.
@Suite("Agent : boucle de travail")
@MainActor
struct AgentLoopTests {
    nonisolated static let same = "```json\n{\"tool\": \"search_code\", \"args\": {\"query\": \"compare_versions\", \"path\": \"src\"}}\n```"
    nonisolated static let other = "```json\n{\"tool\": \"search_code\", \"args\": {\"query\": \"fn compare\"}}\n```"
    nonisolated static let done = "```json\n{\"tool\": \"finish\", \"args\": {\"summary\": \"Fait autrement\"}}\n```"
    let empty = Routes { _ in (200, #"{"tree":[]}"#) }

    func looping(alternate: Bool = false) -> (AgentRun, ScriptLLM) {
        let llm = ScriptLLM()
        let n = Locked(0)
        llm.byModel = { _, model, _ in
            // Le second modèle, lui, change d'approche.
            if model == "m2" { return .text(Self.done) }
            let k = n.update { v -> Int in
                v += 1
                return v - 1
            }
            return .text(alternate && k % 2 == 1 ? Self.other : Self.same)
        }
        let run = makeRun(llm, hub: empty, task: "Ajoute un test pour la fonction qui compare les versions", checks: false)
        return (run, llm)
    }

    func prompts(_ llm: ScriptLLM) -> [String] { (0..<llm.count).map { llm.last($0) } }

    @Test("même action répétée : relance douce, puis ferme, puis arrêt clair")
    func sameAction() async {
        let (run, llm) = looping()
        await run.run()
        #expect(!run.running)
        #expect(run.steps.last?.text.contains("en boucle") == true)
        let p = prompts(llm)
        #expect(p.contains { $0.contains("inutile de la répéter") })
        #expect(p.contains { $0.contains("N'EXISTE PAS") })
        #expect(p.contains { $0.contains("Choisis une AUTRE action") })
    }

    @Test("même action répétée : un autre modèle prend la suite et termine")
    func sameActionFallback() async {
        let (run, _) = looping()
        run.fallback = { _, tried in tried.contains("groq::m2") ? nil : (groq, "k", "m2") }
        await run.run()
        #expect(run.model == "m2")
        #expect(run.summary == "Fait autrement")
        #expect(run.steps.contains { $0.text.contains("Je continue avec") })
        #expect(!run.steps.contains { $0.text.contains("en boucle : arrêté") })
    }

    @Test("recherches refaites en alternance : repérées, puis arrêt expliqué")
    func alternate() async {
        let (run, llm) = looping(alternate: true)
        await run.run()
        #expect(!run.running)
        let p = prompts(llm)
        #expect(!p.contains { $0.contains("inutile de la répéter") })
        #expect(p.contains { $0.contains("tu tournes en rond") })
        #expect(run.steps.last?.text.contains("tourne en rond") == true)
        #expect(p.count < 15)

        let (run2, _) = looping(alternate: true)
        run2.fallback = { _, tried in tried.contains("groq::m2") ? nil : (groq, "k", "m2") }
        await run2.run()
        #expect(run2.model == "m2")
        #expect(run2.summary == "Fait autrement")
    }

    @Test("une nouvelle recherche après une modification n'est pas une boucle")
    func searchAfterEdit() async {
        let edit = "```json\n{\"tool\": \"write_file\", \"args\": {\"path\": \"a.rs\", \"content\": \"fn a() {}\"}}\n```"
        let llm = ScriptLLM([Self.same, edit, Self.same, Self.other, Self.same, Self.done])
        let run = makeRun(llm, hub: empty, task: "Ajoute la fonction a", checks: false)
        await run.run()
        #expect(run.summary == "Fait autrement")
        #expect(!prompts(llm).contains { $0.contains("tu tournes en rond") })
    }

    // MARK: - Les demandes suivies

    func redTitle(_ replies: [String]) -> (AgentRun, ScriptLLM) {
        let llm = ScriptLLM(replies)
        return (makeRun(llm, hub: empty, task: "Mets le titre en rouge", checks: false), llm)
    }

    @Test("les demandes sont redonnées à chaque étape, la dernière prime")
    func requestsEachStep() async {
        let (run, llm) = redTitle([
            thoughtAct("write_file", ["path": "a.css"], "h1{color:red}"),
            thoughtAct("finish", ["summary": "Titre rouge"]),
            thoughtAct("write_file", ["path": "a.css"], "h1{color:blue}"),
            thoughtAct("finish", ["summary": "Titre bleu"]),
        ])
        await run.run()
        await run.run(followUp: "Finalement en bleu, pas en rouge")
        #expect(run.draft("a.css")?.contains("color:blue") == true)
        let last = llm.prompt(llm.count - 1)
        #expect(last.contains("DEMANDES DE L'"))
        #expect(last.contains("Mets le titre en rouge"))
        #expect(last.contains("Finalement en bleu, pas en rouge"))
        #expect(last.contains("la plus r"))
        #expect(last.contains("ORDRE"))
        #expect(run.requests == ["Mets le titre en rouge", "Finalement en bleu, pas en rouge"])
    }

    @Test("terminer sans rien faire pour la nouvelle demande est refusé une fois")
    func nudgeFollowUp() async {
        let (run, llm) = redTitle([
            thoughtAct("write_file", ["path": "a.css"], "h1{color:red}"),
            thoughtAct("finish", ["summary": "Titre rouge"]),
            thoughtAct("finish", ["summary": "Déjà fait"]),
            thoughtAct("write_file", ["path": "b.css"], "p{margin:0}"),
            thoughtAct("finish", ["summary": "Marges retirées"]),
        ])
        await run.run()
        await run.run(followUp: "Retire les marges des paragraphes")
        #expect(run.draft("b.css")?.contains("margin:0") == true)
        #expect(run.summary == "Marges retirées")
        #expect(llm.prompt(3).contains("sans avoir rien fait"))

        let (q, ql) = redTitle([thoughtAct("finish", ["summary": "Rien à faire"]), thoughtAct("finish", ["summary": "Le titre est déjà rouge"])])
        await q.run()
        #expect(q.summary == "Le titre est déjà rouge")
        #expect(ql.count == 2)
    }

    @Test("à chaque étape, l'agent se répète la demande ; anciens rappels retirés par paquets")
    func reminder() async throws {
        let first = "```json\n" + LooseJSON.string([
            "demande": "Mettre le titre en rouge", "thought": "Je lis le style",
            "actions": [["tool": "read_file", "args": ["path": "a.css"]]],
        ]) + "\n```"
        let (run, llm) = redTitle([first, thoughtAct("write_file", ["path": "a.css"], "h1{color:red}"), thoughtAct("finish", ["summary": "ok"])])
        await run.run()
        #expect(llm.prompt(1).contains("RAPPEL DE LA DEMANDE"))
        #expect(llm.prompt(2).contains("RAPPEL DE LA DEMANDE"))
        let kept = run.history.filter { $0.content.contains("RAPPEL DE LA DEMANDE") }.count
        #expect(kept >= 1 && kept <= AgentRun.reminderBatch)
        #expect(run.history.last { $0.role == "user" }?.content.contains("RAPPEL DE LA DEMANDE") == true)
        #expect(run.history.last { $0.role == "user" }?.content.contains("« Mets le titre en rouge »") == true)
        #expect(run.steps.first?.kind == .goal)
        #expect(run.steps.first?.text == "Mettre le titre en rouge")
        let sys = llm.prompt(0)
        #expect(sys.indexOf("DEMANDES DE L'") < sys.indexOf("Outils"))
        #expect(llm.prompt(1).contains("au tout début : « Mets le titre en rouge »"))
        #expect(parseToolCalls(#"{"demande":"x","tool":"finish","args":{}}"#).first?.goal == "x")
    }

    @Test("un résumé qui laisse du travail de côté est renvoyé le faire")
    func unfinished() async {
        let (run, llm) = redTitle([
            thoughtAct("write_file", ["path": "a.css"], "html{overflow-x:clip}"),
            thoughtAct("finish", ["summary": "Corrigé. Je pourrais ajouter un test, ce n'était pas demandé."]),
            thoughtAct("write_file", ["path": "largeur.test.js"], "test()"),
            thoughtAct("finish", ["summary": "Corrigé et test ajouté."]),
        ])
        await run.run()
        #expect(run.summary == "Corrigé et test ajouté.")
        #expect(run.changes.keys.contains("a.css") && run.changes.keys.contains("largeur.test.js"))
        #expect(llm.prompt(2).contains("travail non fait"))
        #expect(unfinishedWorkIn("Limite : je n'ai pas pu tester") != nil)
        #expect(unfinishedWorkIn("Titre passé en bleu.") == nil)
    }

    @Test("instruction pendant le travail : lue au tour suivant")
    func steer() async {
        let llm = ScriptLLM([act(["tool": "finish", "args": ["summary": "ok"]])])
        let run = makeRun(llm, hub: empty, repo: "Paquets", branch: "master", task: "Tâche")
        run.steer("Utilise uniquement Paquets")
        await run.run()
        #expect(run.history.contains { $0.content.contains("Utilise uniquement Paquets") })
        #expect(run.steps.first?.kind == .user)
    }

    @Test("arrêt pendant une réponse : la session s'arrête tout de suite")
    func stopNow() async {
        let llm = ScriptLLM()
        llm.whenEmpty = act(["tool": "read_file", "args": ["path": "a"]])
        let run = makeRun(llm, hub: empty, task: "Tâche", checks: false)
        Task { @MainActor in
            while run.steps.isEmpty { await Task.yield() }
            run.stop()
        }
        await run.run()
        #expect(!run.running)
        #expect(run.cancelled)
        #expect(run.steps.last?.text == "Arrêté.")
    }

    // MARK: - Dépôts illisibles

    func flaky(fails: Int, broken: Set<String> = []) -> Routes {
        let left = Locked(fails)
        return Routes { c in
            if c.path.contains("/git/trees/") {
                let repo = c.path.components(separatedBy: "/")[3]
                let fail = broken.contains(repo) || (repo == "api" && left.update { v -> Bool in
                    v -= 1
                    return v >= 0
                })
                if fail { return (401, #"{"message":"Bad credentials"}"#) }
                return (200, treeJSON([repo == "api" ? "src/main.rs" : "index.html"]))
            }
            return notFound
        }
    }

    func apiRun(_ hub: Routes, _ replies: [String] = [], extra: [RepoTarget] = []) -> (AgentRun, ScriptLLM) {
        let llm = ScriptLLM(replies)
        llm.whenEmpty = "```json\n{\"tool\":\"finish\",\"args\":{\"summary\":\"fin\"}}\n```"
        let run = makeRun(llm, hub: hub, repo: "api", task: "Ajoute une route /sante", extra: extra, checks: false)
        run.specs.append("déjà compris")
        return (run, llm)
    }

    @Test("dépôt illisible : arrêt tout de suite, en disant pourquoi")
    func unreadable() async {
        let (run, llm) = apiRun(flaky(fails: 99))
        await run.run()
        #expect(llm.count == 0)
        #expect(!run.running)
        #expect(run.steps.last?.kind == .error)
        #expect(run.steps.last?.text.contains("Impossible de lire le dépôt max/api") == true)
        #expect(run.steps.last?.text.contains("Bad credentials") == true)
        #expect(run.status == .stopped)
        #expect(run.history.isEmpty)
    }

    @Test("« continue » après un échec de lecture : la session repart")
    func unreadableThenContinue() async {
        let (run, llm) = apiRun(flaky(fails: 1))
        await run.run()
        #expect(llm.count == 0)
        await run.run(followUp: "continue")
        #expect(llm.last(0).contains("src/main.rs"))
        #expect(run.steps.last?.kind == .done)
        #expect(run.requests == ["Ajoute une route /sante"])
        #expect(!llm.last(0).contains("INSTRUCTIONS AJOUTÉES"))
    }

    @Test("une lecture ratée de la liste n'est pas gardée : elle est redemandée")
    func unreadableRetried() async {
        let (run, llm) = apiRun(flaky(fails: 1), ["```json\n{\"tool\":\"list_files\",\"args\":{}}\n```"], extra: [RepoTarget("max", "site", "main")])
        await run.run()
        #expect(llm.last(0).contains("site/index.html"))
        #expect(!llm.last(0).contains("src/main.rs"))
        #expect(llm.last(1).contains("api/src/main.rs"))
        #expect(!llm.last(1).contains("illisible"))
    }

    @Test("une instruction après un arrêt au démarrage n'est plus perdue")
    func instructionAfterStop() async {
        let (run, llm) = apiRun(flaky(fails: 1))
        await run.run()
        await run.run(followUp: "Ajoute aussi une route /version")
        #expect(run.steps.filter { $0.kind == .user }.map(\.text) == ["Ajoute aussi une route /version"])
        #expect(run.requests == ["Ajoute une route /sante", "Ajoute aussi une route /version"])
        let first = llm.last(0)
        #expect(first.contains("Ajoute une route /sante"))
        #expect(first.contains("INSTRUCTIONS AJOUTÉES ENSUITE"))
        #expect(first.contains("« Ajoute aussi une route /version »"))
        #expect(first.contains("src/main.rs"))

        let (r2, l2) = apiRun(flaky(fails: 2))
        await r2.run()
        await r2.run(followUp: "En Rust uniquement")
        #expect(l2.count == 0)
        #expect(r2.steps.last?.kind == .error)
        #expect(r2.requests.last == "En Rust uniquement")
        await r2.run(followUp: "continue")
        #expect(l2.last(0).contains("« En Rust uniquement »"))
        #expect(r2.requests.count == 2)
    }

    @Test("un simple « continue » n'est pas une nouvelle demande")
    func resume() {
        for t in ["continue", "Continue.", "reprends", "vas-y !", "OK", "la suite"] { #expect(AgentRun.isResume(t), "\(t)") }
        for t in ["continue en ajoutant un test", "Ajoute une route", "ok mais en Rust"] { #expect(!AgentRun.isResume(t), "\(t)") }
    }

    @Test("un dépôt vide et un fichier absent ne sont pas des erreurs")
    func emptyRepo() async {
        let hub = Routes { c in
            if c.path.contains("/galerie/") {
                if c.method == "PUT" && c.path.contains("/contents/") { return (201, #"{"content":{"sha":"f1"}}"#) }
                return (409, #"{"message":"Git Repository is empty."}"#)
            }
            if c.path.contains("/git/trees/") { return (200, treeJSON(["site/src/server/export.rs", "site/Cargo.toml"])) }
            return notFound
        }
        let llm = ScriptLLM([
            act(["thought": "Je regarde", "actions": [
                ["tool": "list_files", "args": ["path": "Paquets/site"]],
                ["tool": "read_file", "args": ["path": "Paquets/site/src/server.rs"]],
            ]]),
            act(["tool": "finish", "args": ["summary": "ok"]]),
        ])
        let run = makeRun(llm, hub: hub, repo: "galerie", task: "Galerie", extra: [RepoTarget("max", "Paquets", "master")], checks: false)
        await run.run()
        #expect(!run.steps.contains { $0.kind == .error })
        let results = run.texts(.result)
        #expect(results.contains("Paquets/site/Cargo.toml"))
        #expect(results.contains("galerie est vide"))
        #expect(results.contains("Fichier introuvable"))
        #expect(results.contains("Paquets/site/src/server/export.rs"))
        #expect(run.summary == "ok")

        // Premier commit dans un dépôt vide : par l'API Contents.
        var gh = GitHubAPI(token: "t", transport: hub)
        gh.retryPause = .zero
        let sha = try? await gh.commitWork("max", "galerie", branch: "main", message: "Galerie", changes: [.write("index.html", "<canvas>")])
        #expect(sha == "f1")
        #expect(hub.calls.contains("PUT /repos/max/galerie/contents/index.html"))
    }

    // MARK: - Contenus attendus

    nonisolated static let test1 = "#[tokio::test]\nasync fn sante() {\n    assert_eq!(1 + 1, 2);\n}\n"
    nonisolated static let readCargo = "```json\n{\"thought\":\"je relis\",\"tool\":\"read_file\",\"args\":{\"path\":\"Cargo.toml\"}}\n```"
    nonisolated static let bareWrite = "```json\n{\"actions\":[{\"tool\":\"write_file\",\"args\":{\"path\":\"tests/sante.rs\"}},{\"tool\":\"read_file\",\"args\":{\"path\":\"Cargo.toml\"}}]}\n```"

    func cargoRun(_ replies: [String]) -> (AgentRun, ScriptLLM) {
        let llm = ScriptLLM(replies)
        llm.whenEmpty = "```json\n{\"tool\":\"finish\",\"args\":{\"summary\":\"fin\"}}\n```"
        let hub = repoHub(["src/main.rs": "fn main() {}\n", "Cargo.toml": "[package]\nname = \"a\"\n"])
        return (makeRun(llm, hub: hub, task: "Ajoute un test", checks: false), llm)
    }

    @Test("le contenu écrit avant le bloc JSON du write_file est repris (sans deviner)")
    func contentBefore() {
        #expect(parseToolCalls("Voici le test :\n```rust\n\(Self.test1)```\n\n```json\n{\"tool\":\"write_file\",\"args\":{\"path\":\"tests/sante.rs\"}}\n```").first?.args["content"] as? String == Self.test1)
        #expect(parseToolCalls("Avant :\n```rust\nfn a() {}\n```\nAprès :\n```rust\n\(Self.test1)```\n```json\n{\"tool\":\"write_file\",\"args\":{\"path\":\"tests/sante.rs\"}}\n```").first?.args["content"] == nil)
        #expect(parseToolCalls("```rust\nfn vieux() {}\n```\n```json\n{\"tool\":\"write_file\",\"args\":{\"path\":\"tests/sante.rs\"}}\n```\n```rust\n\(Self.test1)```").first?.args["content"] as? String == Self.test1)
        #expect(leadingContent("```rust\n\(Self.test1)```\n\(Self.readCargo)") == Self.test1)
        #expect(leadingContent(Self.readCargo) == nil)
        #expect(leadingContent("```rust\n\(Self.test1)```") == nil)
        #expect(leadingContent("```rust\na\n```\n```rust\nb\n```\n\(Self.readCargo)") == nil)
    }

    @Test("contenu attendu envoyé avec une autre action : écrit, puis l'action est faite")
    func pendingWithAction() async {
        let (run, _) = cargoRun([Self.bareWrite, "```rust\n\(Self.test1)```\n\n\(Self.readCargo)", "```json\n{\"tool\":\"finish\",\"args\":{\"summary\":\"Test ajouté\"}}\n```"])
        await run.run()
        #expect(run.draft("tests/sante.rs") == Self.test1)
        let tools = run.steps.filter { $0.kind == .tool }.map { "\($0.tool ?? "") \($0.text)" }
        #expect(tools == ["write_file tests/sante.rs", "read_file Cargo.toml", "write_file tests/sante.rs", "read_file Cargo.toml"])
    }

    @Test("contenu attendu jamais arrivé : l'agent apprend que le fichier n'est pas écrit")
    func pendingLost() async {
        let (run, llm) = cargoRun([Self.bareWrite, Self.readCargo, "```json\n{\"tool\":\"finish\",\"args\":{\"summary\":\"fini\"}}\n```"])
        await run.run()
        #expect(!run.changes.contains("tests/sante.rs"))
        #expect(llm.count >= 3)
        #expect(!llm.last(1).contains("n'a PAS été écrit"))
        #expect(llm.last(2).contains("tests/sante.rs n'a PAS été écrit"))

        let (ok, okl) = cargoRun([Self.bareWrite, "```rust\n\(Self.test1)```", "```json\n{\"tool\":\"finish\",\"args\":{\"summary\":\"ok\"}}\n```"])
        await ok.run()
        #expect(ok.draft("tests/sante.rs") == Self.test1)
        #expect(!(0..<okl.count).contains { okl.prompt($0).contains("n'a PAS été écrit") })
    }

    nonisolated static let bare = "```json\n{\"actions\":[{\"tool\":\"repo_browser.write_file\",\"args\":{\"path\":\"test/a_test.dart\"}}]}\n```"
    nonisolated static let file = "import 'package:flutter_test/flutter_test.dart';\n\nvoid main() {}\n"

    @Test("write_file sans contenu : le contenu suivant est écrit (bloc ou texte nu)")
    func pendingWrite() async {
        let hub = repoHub(["lib/a.dart": "int a() => 1;\n"])
        let llm = ScriptLLM([Self.bare, "```dart\n\(Self.file)```", "```json\n{\"tool\":\"finish\",\"args\":{\"summary\":\"Test ajouté\"}}\n```"])
        let run = makeRun(llm, hub: hub, repo: "app", task: "Ajoute un test", checks: false)
        await run.run()
        #expect(run.draft("test/a_test.dart") == Self.file)
        let all = run.steps.map(\.text).joined(separator: "\n")
        #expect(all.contains("EN ATTENTE du contenu de test/a_test.dart"))
        #expect(!all.contains("en boucle"))

        let run2 = makeRun(ScriptLLM([Self.bare, Self.file, "{\"tool\":\"finish\",\"args\":{\"summary\":\"ok\"}}"]), hub: hub, repo: "app", task: "Ajoute un test", checks: false)
        await run2.run()
        #expect(run2.draft("test/a_test.dart") == Self.file)

        #expect(pendingContent("```json\n{\"tool\":\"read_file\",\"args\":{\"path\":\"lib/a.dart\"}}\n```") == nil)
        #expect(pendingContent("\(Self.bare)\n```dart\n\(Self.file)```") == nil)
        #expect(pendingContent(Self.bare) == nil)
        #expect(pendingContent("```dart\n\(Self.file)```") == Self.file)
        #expect(parseToolCalls(#"{"tool":"write_file","args":{"path":"a.txt","contents":"bonjour"}}"#).first?.args["content"] as? String == "bonjour")
    }
}
