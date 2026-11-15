import Foundation
import Testing
@testable import NexoraKit

@Suite("Actions et commits")
struct ActionsDisplayTests {
    private func run(_ status: String?, _ conclusion: String? = nil, name: String? = "CI", title: String? = "Corriger le menu",
                     branch: String? = "main", event: String? = "push", created: String? = nil) throws -> WorkflowRun {
        var j: [String: Any] = ["id": 1]
        if let status { j["status"] = status }
        if let conclusion { j["conclusion"] = conclusion }
        if let name { j["name"] = name }
        if let title { j["display_title"] = title }
        if let branch { j["head_branch"] = branch }
        if let event { j["event"] = event }
        if let created { j["created_at"] = created }
        return try JSONDecoder().decode(WorkflowRun.self, from: JSONSerialization.data(withJSONObject: j))
    }

    private func commit(_ message: String, author: String?, date: String?) throws -> Commit {
        var a: [String: Any] = [:]
        if let author { a["name"] = author }
        if let date { a["date"] = date }
        let j: [String: Any] = ["sha": "a1b2c3d4e5f6", "commit": ["message": message, "author": a]]
        return try JSONDecoder().decode(Commit.self, from: JSONSerialization.data(withJSONObject: j))
    }

    @Test func etatsEtRelance() throws {
        #expect(ActionsDisplay.state(try run("completed", "success")) == .success)
        #expect(ActionsDisplay.state(try run("completed", "timed_out")) == .failure)
        #expect(ActionsDisplay.state(try run("completed", "neutral")) == .skipped)
        #expect(ActionsDisplay.state(try run("in_progress")) == .running)
        #expect(ActionsDisplay.state(try run(nil)) == .running)
        #expect(ActionsDisplay.needsRerun(try run("completed", "failure")))
        #expect(ActionsDisplay.needsRerun(try run("completed", "cancelled")))
        #expect(!ActionsDisplay.needsRerun(try run("completed", "success")))
        #expect(!ActionsDisplay.needsRerun(try run("queued")))
        #expect(ActionsDisplay.RunState.failure.label == "Échouée")
    }

    @Test func ligneEtVoiceOver() throws {
        let now = ReposDisplay.parseDate("2026-11-14T12:00:00Z")!
        let r = try run("completed", "failure", created: "2026-11-14T10:00:00Z")
        #expect(ActionsDisplay.detail(r, now: now) == "CI · main · envoi · il y a 2 h")
        #expect(ActionsDisplay.accessibility(r) == "Échouée, Corriger le menu, CI, branche main")
        let seul = try run("queued", name: nil, title: "Nuit", branch: nil, event: "schedule")
        #expect(ActionsDisplay.detail(seul) == "planifié")
        #expect(ActionsDisplay.accessibility(seul) == "En cours, Nuit")
        #expect(ActionsDisplay.event("workflow_dispatch") == "manuel")
        #expect(ActionsDisplay.event("merge_group") == "merge group")
        #expect(ActionsDisplay.event("") == nil)
    }

    @Test func enTeteEtQuestions() throws {
        let ok = try run("completed", "success")
        let ko = try run("completed", "failure")
        #expect(ActionsDisplay.runsHeader([ok]) == "1 exécution")
        #expect(ActionsDisplay.runsHeader([ok, ok]) == "2 exécutions")
        #expect(ActionsDisplay.runsHeader([ok, ko]) == "1 échouée")
        #expect(ActionsDisplay.runsHeader([ko, ko, ok]) == "2 échouées")
        let w = try JSONDecoder().decode(Workflow.self, from: Data(#"{"id":3,"name":"TestFlight","path":".github/workflows/t.yml","state":"active"}"#.utf8))
        #expect(ActionsDisplay.dispatchQuestion(w, branch: "main") == "Lancer « TestFlight » sur main ?")
        #expect(ActionsDisplay.dispatched(w, branch: "main").hasPrefix("« TestFlight » lancé sur main."))
    }

    @Test func commits() throws {
        let now = ReposDisplay.parseDate("2026-11-14T12:00:00Z")!
        let c = try commit("Corriger le menu\n\nDétails", author: "Max", date: "2026-11-12T12:00:00Z")
        #expect(ActionsDisplay.commitDetail(c, now: now) == "a1b2c3d · Max · il y a 2 j")
        #expect(ActionsDisplay.commitAccessibility(c, now: now) == "Corriger le menu, par Max, il y a 2 j")
        let anonyme = try commit("Init", author: nil, date: nil)
        #expect(ActionsDisplay.commitDetail(anonyme) == "a1b2c3d")
        #expect(ActionsDisplay.commitAccessibility(anonyme) == "Init")
    }
}
