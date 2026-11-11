import Foundation
import Testing
@testable import NexoraKit

/// Un faux GitHub : la branche principale « main » peut avancer pendant le
/// travail, et la fusion peut être refusée de plusieurs façons.
final class FakeHub: @unchecked Sendable {
    private let lock = NSLock()
    /// Le contenu de chaque fichier sur main.
    var main: [String: String] = [:]
    var pushed: [String] = []
    var pulls: [String] = []
    var closed: [Int] = []
    var deleted: [String] = []
    var mergeMethods: [String] = []
    var commit = 0
    /// Réponses successives de la fusion (statut, message), puis 200.
    var mergeReplies: [(Int, String)] = []
    /// Réponse de « update-branch » : 202 (mise à jour) ou 422 (conflit).
    var updateStatus = 422
    /// Les pull requests déjà fusionnées (sur GitHub, par l'utilisateur).
    var mergedPulls: Set<Int> = []
    /// Le commit fusionné de chaque pull request.
    var mergedAt: [Int: String] = [:]
    /// Le dernier commit de chaque branche (absente : supprimée ou jamais créée).
    var tips: [String: String] = ["main": "p0"]
    /// Combien de 503 avant de répondre normalement.
    var failures = 0

    func with<T>(_ f: (FakeHub) -> T) -> T { lock.withLock { f(self) } }

    var transport: Routes {
        Routes { [self] c in lock.withLock { handle(c) } }
    }

    private func handle(_ c: Routes.Call) -> (Int, String) {
        if failures > 0 {
            failures -= 1
            return (503, #"{"message":"Service Unavailable"}"#)
        }
        let p = c.path
        if p.contains("/contents/") {
            let f = p.components(separatedBy: "/contents/").last ?? ""
            guard let t = main[f] else { return notFound }
            return (200, fileJSON(t))
        }
        if p.contains("/git/ref/heads/") {
            guard let tip = tips[p.components(separatedBy: "/git/ref/heads/").last ?? ""] else { return notFound }
            return (200, LooseJSON.string(["object": ["sha": tip]]))
        }
        if p.contains("/git/commits/") && c.method == "GET" { return (200, #"{"tree":{"sha":"t0"}}"#) }
        if p.contains("/git/trees/") && c.method == "GET" { return (200, #"{"tree":[]}"#) }
        if p.hasSuffix("/git/trees") { return (201, #"{"sha":"t1"}"#) }
        if p.hasSuffix("/git/commits") {
            commit += 1
            return (201, "{\"sha\":\"c\(commit)\"}")
        }
        if p.contains("/git/refs/heads/") && c.method == "PATCH" {
            let b = p.components(separatedBy: "/git/refs/heads/").last ?? ""
            pushed.append(b)
            tips[b] = c.body["sha"] as? String
            return (200, "{}")
        }
        if p.contains("/git/refs/heads/") && c.method == "DELETE" {
            let b = p.components(separatedBy: "/git/refs/heads/").last ?? ""
            deleted.append(b)
            tips.removeValue(forKey: b)
            return (204, "")
        }
        if p.hasSuffix("/git/refs") {
            let ref = (c.body["ref"] as? String ?? "").replacingOccurrences(of: "refs/heads/", with: "")
            if tips[ref] != nil { return (422, #"{"message":"Reference already exists"}"#) }
            tips[ref] = c.body["sha"] as? String
            return (201, LooseJSON.string(["ref": c.body["ref"] ?? ""]))
        }
        if p.hasSuffix("/update-branch") {
            return (updateStatus, updateStatus == 202 ? #"{"message":"Updating pull request branch."}"# : #"{"message":"merge conflict between base and head"}"#)
        }
        if let m = DRegex(#"/pulls/(\d+)/merge$"#).firstMatch(p) {
            _ = m
            mergeMethods.append(c.body["merge_method"] as? String ?? "")
            if !mergeReplies.isEmpty {
                let (s, msg) = mergeReplies.removeFirst()
                return (s, LooseJSON.string(["message": msg]))
            }
            return (200, #"{"merged":true}"#)
        }
        if let one = DRegex(#"/pulls/(\d+)$"#).firstMatch(p) {
            let n = Int(one[1]!)!
            if c.method == "PATCH" {
                closed.append(n)
                return (200, "{}")
            }
            let merged = mergedPulls.contains(n)
            let head = merged ? (mergedAt[n] ?? (n - 1 < pulls.count ? tips[pulls[n - 1]] : nil) ?? "gone") : "updated\(commit)"
            return (200, LooseJSON.string(["head": ["sha": head], "state": merged ? "closed" : "open", "merged": merged]))
        }
        if p.hasSuffix("/pulls") && c.method == "POST" {
            pulls.append(c.body["head"] as? String ?? "")
            return (201, LooseJSON.string([
                "id": pulls.count, "number": pulls.count, "title": "t",
                "html_url": "https://github.com/max/site/pull/\(pulls.count)", "state": "open", "user": ["login": "max"],
            ]))
        }
        if p.contains("/check-runs") {
            return (200, LooseJSON.string(["check_runs": [["id": 1, "name": "tests", "status": "completed", "conclusion": "success"]]]))
        }
        return notFound
    }
}

/// L'envoi : plusieurs dépôts, sessions qui continuent, enregistrement, CI
/// jusqu'au vert, conflits, fusion, pull requests fusionnées ailleurs.
@Suite("Agent : envoi, CI et fusion")
@MainActor
struct AgentShipTests {
    func build(_ hub: FakeHub) -> AgentRun {
        makeRun(hub: hub.transport, task: "Titre en bleu")
    }

    @Test("vrai conflit avec main : le travail revient en brouillons, avec ce que main a changé")
    func conflict() async {
        let hub = FakeHub()
        let run = build(hub)
        run.setOriginal("a.css", "h1 { color: black; }\np { margin: 0; }\n")
        run.changes.set("a.css", "h1 { color: blue; }\np { margin: 0; }\n")
        run.commitMessage = "Titre en bleu"
        hub.with {
            $0.main["a.css"] = "h1 { color: red; }\np { margin: 0 auto; }\n"
            $0.mergeReplies.append((405, "Pull Request is not mergeable"))
            $0.updateStatus = 422
        }
        let report = await run.shipForCi(every: .zero)
        #expect(report?.contains("CONFLIT avec main") == true)
        #expect(report?.contains("a.css") == true)
        #expect(report?.contains("+ p { margin: 0 auto; }") == true)
        #expect(run.draft("a.css") == "h1 { color: blue; }\np { margin: 0; }\n")
        #expect(run.orig("a.css") == hub.with { $0.main["a.css"] })
        #expect(run.pulls.isEmpty)
        #expect(run.heads.isEmpty)
        #expect(run.ciNote.contains("Conflit"))

        let oldBranch = hub.with { $0.pulls.first ?? "" }
        run.changes.set("a.css", "h1 { color: blue; }\np { margin: 0 auto; }\n")
        #expect(await run.shipForCi(every: .zero) == nil)
        #expect(hub.with { $0.pulls.count } == 2)
        #expect(hub.with { $0.closed } == [1])
        #expect(hub.with { $0.deleted }.contains(oldBranch))
        #expect(run.merged == ["max/site → main"])
        #expect(run.ciNote.contains("fusionné dans main"))
    }

    @Test("branche en retard sans conflit : mise à jour, CI repassée, fusion")
    func outOfDate() async {
        let hub = FakeHub()
        let run = build(hub)
        run.changes.set("a.css", "h1 { color: blue; }\n")
        hub.with {
            $0.mergeReplies.append((405, "Base branch was modified. Review and try the merge again (out of date)"))
            $0.updateStatus = 202
        }
        #expect(await run.shipForCi(every: .zero) == nil)
        #expect(run.lastCommits.get("max/site")?.hasPrefix("updated") == true)
        #expect(run.merged == ["max/site → main"])
    }

    @Test("méthode de fusion interdite : la suivante ; règle : l'agent reçoit la cause")
    func mergeRefused() async {
        let hub = FakeHub()
        let run = build(hub)
        run.changes.set("a.css", "x\n")
        hub.with { $0.mergeReplies.append((405, "Squash merges are not allowed on this repository.")) }
        #expect(await run.shipForCi(every: .zero) == nil)
        #expect(hub.with { $0.mergeMethods } == ["squash", "merge"])
        #expect(run.merged.count == 1)

        let hub2 = FakeHub()
        let run2 = build(hub2)
        run2.changes.set("a.css", "x\n")
        hub2.with { $0.mergeReplies.append((405, "At least 1 approving review is required")) }
        let report = await run2.shipForCi(every: .zero)
        #expect(report?.contains("GitHub refuse la fusion") == true)
        #expect(report?.contains("approving review") == true)
    }

    @Test("panne passagère de GitHub : réessayée toute seule")
    func transient() async {
        let hub = FakeHub()
        hub.failures = 2
        let run = build(hub)
        run.changes.set("a.css", "x\n")
        #expect(await run.shipForCi(every: .zero) == nil)
        #expect(run.merged.count == 1)
    }

    @Test("outil github : dépôts de la mission seulement, sans réglages ni fusion")
    func denied() {
        let run = build(FakeHub())
        #expect(run.githubDenied("GET", "/repos/max/site/actions/runs") == nil)
        #expect(run.githubDenied("POST", "/repos/max/site/actions/runs/9/rerun-failed-jobs") == nil)
        #expect(run.githubDenied("PATCH", "/repos/max/site/pulls/3") == nil)
        #expect(run.githubDenied("GET", "/repos/autre/depot")?.contains("mission") == true)
        #expect(run.githubDenied("DELETE", "/repos/max/site")?.contains("réglages") == true)
        #expect(run.githubDenied("PUT", "/repos/max/site/actions/secrets/X")?.contains("interdit") == true)
        #expect(run.githubDenied("PUT", "/repos/max/site/pulls/3/merge")?.contains("CI") == true)
        #expect(run.githubDenied("PATCH", "/repos/max/site/git/refs/heads/main")?.contains("edit_file") == true)
        #expect(run.githubDenied("PUT", "/repos/max/site/contents/a.css")?.contains("edit_file") == true)
        #expect(run.githubDenied("PUT", "/repos/max/site/branches/main/protection")?.contains("interdit") == true)
        #expect(run.githubDenied("GET", "/repos/max/site/../autre")?.contains("chemin invalide") == true)
    }

    @Test("outil github : réponse lisible, journaux d'un job")
    func githubTool() async {
        let hub = Routes { c in
            if c.path.hasSuffix("/actions/jobs/3/logs") { return (200, "2026-11-10T07:00:00.000Z Erreur ici") }
            if c.path.hasSuffix("/actions/runs") { return (200, #"{"total_count":1,"workflow_runs":[{"id":3}]}"#) }
            return (200, #"{"tree":[]}"#)
        }
        let llm = ScriptLLM([
            act("github", ["path": "/repos/max/site/actions/runs"]),
            act("github", ["path": "/repos/max/site/actions/jobs/3/logs"]),
            act("github", ["method": "PUT", "path": "/repos/max/site/pulls/1/merge"]),
            act("finish", ["summary": "ok"]),
        ])
        let run = makeRun(llm, hub: hub, checks: false)
        run.specs.append("déjà compris")
        await run.run()
        #expect(llm.last(1).contains("HTTP 200"))
        #expect(llm.last(1).contains("\"total_count\": 1"))
        #expect(llm.last(2).contains("Erreur ici"))
        #expect(!llm.last(2).contains("2026-11-10T"))
        #expect(llm.last(3).contains("la fusion est faite par l'app"))
    }

    @Test("pull request fusionnée sur GitHub entre-temps : une nouvelle est ouverte")
    func mergedElsewhere() async {
        let hub = FakeHub()
        let run = build(hub)
        run.autoMerge = false
        run.changes.set("a.css", "v1\n")
        #expect(await run.shipForCi(every: .zero) == nil)
        #expect(hub.with { $0.pulls.count } == 1)
        hub.with { _ = $0.mergedPulls.insert(1) }
        run.changes.set("a.css", "v2\n")
        _ = await run.shipForCi(every: .zero)
        #expect(hub.with { $0.pulls.count } == 2)
        #expect(run.pulls["max/site"]?.hasSuffix("/pull/2") == true)
    }

    @Test("travail resté sur une branche après une fusion : repéré, puis rouvert et fusionné")
    func stranded() async {
        let hub = FakeHub()
        let run = build(hub)
        run.autoMerge = false
        run.changes.set("a.css", "v1\n")
        _ = await run.shipForCi(every: .zero)
        hub.with { h in
            h.mergedPulls.insert(1)
            h.mergedAt[1] = h.tips[h.pulls[0]]
            h.tips[h.pulls[0]] = "après-fusion"
        }
        await run.refreshPulls()
        #expect(run.pulls.isEmpty)
        #expect(run.stranded.map(\.fullName) == ["max/site"])
        #expect(await run.reopenPulls() == nil)
        #expect(hub.with { $0.pulls.count } == 2)
        #expect(run.stranded.isEmpty)
        run.autoMerge = true
        #expect(await run.shipForCi(every: .zero) == nil)
        #expect(run.merged == ["max/site → main"])
    }

    @Test("pull request fusionnée sur GitHub sans rien de plus : pas de fausse alerte, la suite repart de main")
    func mergedClean() async {
        let hub = FakeHub()
        let run = build(hub)
        run.autoMerge = false
        run.changes.set("a.css", "v1\n")
        _ = await run.shipForCi(every: .zero)
        let first = hub.with { $0.pulls[0] }
        hub.with { _ = $0.mergedPulls.insert(1) }
        await run.refreshPulls()
        #expect(run.pulls.isEmpty)
        #expect(run.heads.isEmpty)
        #expect(run.stranded.isEmpty)
        #expect(run.merged == ["max/site → main"])
        #expect(hub.with { $0.deleted } == [first])
        run.changes.set("a.css", "v2\n")
        _ = await run.shipForCi(every: .zero)
        #expect(hub.with { $0.pulls.count } == 2)
        #expect(run.pulls["max/site"]?.hasSuffix("/pull/2") == true)
    }

    @Test("pull request fusionnée découverte à l'envoi : l'ancienne branche est supprimée")
    func mergedFoundOnShip() async {
        let hub = FakeHub()
        let run = build(hub)
        run.autoMerge = false
        run.changes.set("a.css", "v1\n")
        _ = await run.shipForCi(every: .zero)
        let first = hub.with { $0.pulls[0] }
        hub.with { _ = $0.mergedPulls.insert(1) }
        run.changes.set("a.css", "v2\n")
        _ = await run.shipForCi(every: .zero)
        #expect(hub.with { $0.deleted } == [first])
        #expect(hub.with { $0.pulls.count } == 2)
        #expect(run.pulls["max/site"]?.hasSuffix("/pull/2") == true)
    }

    // MARK: - Plusieurs dépôts

    func twoRepos() -> Routes {
        Routes { c in
            if c.path.contains("/git/trees/") {
                return (200, treeJSON(c.path.contains("/paquets/") ? ["Cargo.toml", "src/lib.rs"] : ["README.md"]))
            }
            if c.path.hasSuffix("/contents/src/lib.rs") { return (200, fileJSON("pub fn island() {}", sha: "abc")) }
            return notFound
        }
    }

    @Test("plusieurs dépôts : un dossier par dépôt ; lit l'un, écrit dans l'autre")
    func multiRepo() async {
        let llm = ScriptLLM([
            thoughtAct("list_files", [:]),
            thoughtAct("read_file", ["path": "paquets/src/lib.rs"]),
            thoughtAct("write_file", ["path": "index.html"], "<p>raté</p>"),
            thoughtAct("write_file", ["path": "galerie/index.html"], "<canvas></canvas>"),
            thoughtAct("finish", ["summary": "Fait", "commit_message": "Galerie 3D"]),
        ])
        let run = makeRun(llm, hub: twoRepos(), repo: "galerie", task: "Galerie 3D avec Paquets", extra: [RepoTarget("max", "paquets", "master")], checks: false)
        #expect(run.multi)
        #expect(run.resolve("paquets/src/lib.rs")?.0.name == "paquets")
        #expect(run.resolve("paquets/src/lib.rs")?.1 == "src/lib.rs")
        #expect(run.resolve("README.md") == nil)
        await run.run()
        let results = run.steps.filter { $0.kind == .result }.map(\.text)
        #expect(results.first?.contains("paquets/Cargo.toml") == true)
        #expect(results.first?.contains("galerie/README.md") == true)
        #expect(results.count > 1 && results[1] == "pub fn island() {}")
        #expect(run.changes.keys == ["galerie/index.html"])
        #expect(run.acceptedByRepo.count == 1)
        #expect(run.acceptedByRepo.first?.0.name == "galerie")
        #expect(run.acceptedByRepo.first?.1.map(\.0) == ["index.html"])
        #expect(run.summary == "Fait")
        #expect(run.system.contains("- galerie/ → max/galerie (branche main) : dépôt principal"))
    }

    @Test("une coupure ne termine plus la mission : nouvel essai ; dépenses comptées")
    func outage() async {
        let llm = ScriptLLM(replies: [
            .error(503, #"{"error":{"message":"overloaded"}}"#), .error(503, #"{"error":{"message":"overloaded"}}"#),
            .error(503, #"{"error":{"message":"overloaded"}}"#),
            .text(thoughtAct("finish", ["summary": "Rien à faire"])), .text(thoughtAct("finish", ["summary": "OK après coupure"])),
        ])
        let run = makeRun(llm, hub: twoRepos(), repo: "galerie", task: "Galerie 3D avec Paquets", extra: [RepoTarget("max", "paquets", "master")], checks: false)
        let seen = Locked<[TokenUsage]>([])
        run.onUsage = { _, _, t in seen.update { $0.append(t) } }
        await run.run()
        #expect(run.summary == "OK après coupure")
        #expect(run.steps.contains { $0.text.contains("Nouvel essai") })
        #expect(seen.get().count == 2)
        #expect(seen.get().allSatisfy { $0.total > 0 })
    }

    // MARK: - Sessions

    final class Pushes: @unchecked Sendable {
        let lock = NSLock()
        var pulls: [String] = []
        var pushedTo: [String] = []
    }

    @Test("session : suite d'instructions et même pull request")
    func session() async throws {
        let s = Pushes()
        let hub = Routes { c in
            s.lock.withLock { () -> (Int, String) in
                let p = c.path
                if p.contains("/git/trees/") && c.method == "GET" { return (200, treeJSON(["README.md"])) }
                if p.contains("/git/ref/heads/") { return (200, #"{"object":{"sha":"p0"}}"#) }
                if p.contains("/git/commits/") && c.method == "GET" { return (200, #"{"tree":{"sha":"t0"}}"#) }
                if p.hasSuffix("/git/trees") { return (201, #"{"sha":"t1"}"#) }
                if p.hasSuffix("/git/commits") { return (201, #"{"sha":"c1234567890"}"#) }
                if p.contains("/git/refs/heads/") && c.method == "PATCH" {
                    s.pushedTo.append(p.components(separatedBy: "/git/refs/heads/").last!)
                    return (200, "{}")
                }
                if p.hasSuffix("/git/refs") { return (201, LooseJSON.string(["ref": c.body["ref"] ?? ""])) }
                if p.hasSuffix("/pulls") {
                    s.pulls.append(c.body["head"] as? String ?? "")
                    return (201, LooseJSON.string(["id": s.pulls.count, "number": s.pulls.count, "title": c.body["title"] ?? "",
                                                   "html_url": "https://github.com/max/galerie/pull/\(s.pulls.count)", "state": "open", "user": ["login": "max"]]))
                }
                return notFound
            }
        }
        let llm = ScriptLLM([
            thoughtAct("write_file", ["path": "galerie/index.html"], "<canvas>"),
            thoughtAct("finish", ["summary": "Galerie", "commit_message": "Galerie 3D"]),
            thoughtAct("write_file", ["path": "galerie/style.css"], "body{}"),
            thoughtAct("finish", ["summary": "Style"]),
        ])
        let run = makeRun(llm, hub: hub, repo: "galerie", task: "Galerie 3D", extra: [RepoTarget("max", "paquets", "master")], checks: false)
        await run.run()
        #expect(run.status == .review)
        #expect(run.reposLabel == "galerie, +1 autre")
        #expect(run.stats == (1, 0))

        let first = try await run.commitAll(message: "Galerie 3D", targetBranch: "nexora/galerie", openPr: true)
        #expect(first.first?.isPull == true)
        #expect(run.status == .shipped)
        #expect(run.heads == ["max/galerie": "nexora/galerie"])
        #expect(run.changes.isEmpty)

        await run.run(followUp: "Ajoute une feuille de style")
        #expect(run.steps.contains { $0.kind == .user })
        #expect(run.history.filter { $0.content.hasPrefix("NOUVELLE INSTRUCTION") && $0.content.contains("feuille") }.count == 1)
        #expect(run.changes.keys == ["galerie/style.css"])

        let second = try await run.commitAll(message: "Style")
        #expect(second.first?.result == first.first?.result)
        #expect(s.lock.withLock { s.pulls } == ["nexora/galerie"])
        #expect(s.lock.withLock { s.pushedTo } == ["nexora/galerie", "nexora/galerie"])
    }

    @Test("session enregistrée puis rechargée (même JSON que l'app Flutter)")
    func persist() throws {
        let run = makeRun(hub: Routes { _ in notFound }, repo: "galerie", task: "Galerie 3D", extra: [RepoTarget("max", "paquets", "master")])
        run.model = "llama-3.3-70b-versatile"
        run.level = .eleve
        run.steps.append(AgentStep(.thought, "Je regarde"))
        run.history.append(LLMMessage("user", "Tâche"))
        run.changes.set("galerie/b.txt", "B\n")
        run.changes.set("galerie/a.txt", "A\n")
        run.changes.set("galerie/gone.txt", nil)
        run.setOriginal("galerie/a.txt", nil)
        run.setOriginal("galerie/b.txt", "b\n")
        run.pulls["max/galerie"] = "https://github.com/max/galerie/pull/1"
        run.bases.set("galerie/a.txt", nil)
        run.specs = ["OBJECTIF : x"]
        run.running = true // l'app est fermée pendant le travail
        let data = try JSONSerialization.data(withJSONObject: run.toJSON())
        let j = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(j["repos"] as? [[String: String]] == [["o": "max", "n": "galerie", "b": "main"], ["o": "max", "n": "paquets", "b": "master"]])
        #expect(j["level"] as? String == "eleve")
        #expect((j["changes"] as? [String: Any])?["galerie/gone.txt"] is NSNull)

        let back = try #require(AgentRun.restore(j, llm: run.llm, github: run.github, provider: groq, apiKey: nil))
        #expect(back.id == run.id)
        #expect(back.targets.map(\.fullName) == ["max/galerie", "max/paquets"])
        #expect(back.changes.keys == ["galerie/b.txt", "galerie/a.txt", "galerie/gone.txt"])
        #expect(back.draft("galerie/a.txt") == "A\n")
        #expect(back.changes.contains("galerie/gone.txt") && back.draft("galerie/gone.txt") == nil)
        #expect(back.originals.keys.contains("galerie/a.txt") && back.orig("galerie/a.txt") == nil)
        #expect(back.orig("galerie/b.txt") == "b\n")
        #expect(back.steps.first?.text == "Je regarde")
        #expect(back.history.first?.content == "Tâche")
        #expect(back.pulls.values.first?.contains("/pull/1") == true)
        #expect(back.interrupted)
        #expect(back.status == .review)
        #expect(back.level == .eleve)
        #expect(back.model == "llama-3.3-70b-versatile")
        #expect(back.specs == ["OBJECTIF : x"])
        #expect(back.bases.contains("galerie/a.txt"))
        // Un long texte d'étape est raccourci à l'enregistrement.
        #expect(AgentStep(.result, String(repeating: "x", count: 5000)).toJSON()["t"] as? String == String(repeating: "x", count: 4000) + "…")
    }

    // MARK: - Travail, envoi et CI jusqu'au vert

    @Test("drive : travail, envoi, CI rouge renvoyée à l'agent, correction, vert et fusion")
    func drive() async {
        // La CI échoue au premier envoi, passe une fois l'agent corrigé.
        let failing = Locked(true)
        let hub = FakeHub()
        let base = hub.transport
        let routes = Routes { c in
            if c.path.contains("/check-runs") {
                let conclusion = failing.get() ? "failure" : "success"
                return (200, LooseJSON.string(["check_runs": [["id": 4, "name": "tests", "status": "completed", "conclusion": conclusion]]]))
            }
            if c.path.hasSuffix("/actions/jobs/4/logs") { return (200, "assert échoue") }
            let r = base.handler(c)
            return (r.0, r.1)
        }
        let llm = ScriptLLM()
        llm.byModel = { _, _, last in
            if last.contains("Les tests GitHub ont échoué") {
                failing.set(false)
                return .text(act("write_file", ["path": "a.css"], "h1 { color: blue; }"))
            }
            if last.contains("Résultat de write_file") { return .text(act("finish", ["summary": "Bleu ✅"])) }
            return .text(act("write_file", ["path": "a.css"], "h1 { color: navy; }"))
        }
        let run = makeRun(llm, hub: routes, task: "Titre en bleu", checks: false)
        run.specs.append("déjà compris")
        await run.drive(every: .zero, noneAfter: .zero)
        #expect(run.summary == "Bleu ✅")
        #expect(run.steps.contains { $0.kind == .result && $0.tool == "ci" && $0.text.hasPrefix("🧪 Les tests GitHub ont échoué") })
        #expect(run.merged == ["max/site → main"])
        #expect(run.ciNote.contains("fusionné dans main"))
        #expect(run.changes.isEmpty)
        #expect(run.ciRounds == 2)
        #expect(!run.shipping)
        #expect(llm.messages(llm.count - 1).contains { ($0["content"] ?? "").contains("assert échoue") })
    }

    @Test("arrêté par l'utilisateur : l'app ne relance rien d'elle-même")
    func cancelledNoShip() async {
        let llm = ScriptLLM([act("finish", ["summary": "x"])])
        let run = makeRun(llm, hub: FakeHub().transport, checks: false)
        run.cancelled = true
        await run.run(followUp: "rapport de CI", fromApp: true)
        #expect(llm.count == 0)
        #expect(run.prepareFollowUp("nouvelle demande"))
        #expect(!run.cancelled)
    }
}
