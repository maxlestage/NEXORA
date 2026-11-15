import Foundation
import Testing
@testable import NexoraKit

@Suite("Issues et pull requests")
struct IssuesDisplayTests {
    private func issue(_ n: Int, _ title: String, user: String? = "max", comments: Int? = nil,
                       updatedAt: String? = nil, pull: Bool = false) throws -> NexoraKit.Issue {
        var j: [String: Any] = ["id": n, "number": n, "title": title, "state": "open"]
        if let user { j["user"] = ["login": user] }
        if let comments { j["comments"] = comments }
        if let updatedAt { j["updated_at"] = updatedAt }
        if pull { j["pull_request"] = ["url": "https://x"] }
        return try JSONDecoder().decode(NexoraKit.Issue.self, from: JSONSerialization.data(withJSONObject: j))
    }

    @Test func rechercheTitreNumeroAuteur() throws {
        let items = [try issue(12, "Corriger l'écran", user: "léa"), try issue(3, "Ajouter un menu", user: "bob")]
        #expect(IssuesDisplay.filter(items, query: " ").count == 2)
        #expect(IssuesDisplay.filter(items, query: "ECRAN").map(\.number) == [12])
        #expect(IssuesDisplay.filter(items, query: "#3").map(\.number) == [3])
        #expect(IssuesDisplay.filter(items, query: "12").map(\.number) == [12])
        #expect(IssuesDisplay.filter(items, query: "@lea").map(\.number) == [12])
        #expect(IssuesDisplay.filter(items, query: "python").isEmpty)
    }

    @Test func ligneEtVoiceOver() throws {
        let now = ReposDisplay.parseDate("2026-11-14T12:00:00Z")!
        let i = try issue(12, "Menu", comments: 3, updatedAt: "2026-11-12T12:00:00Z", pull: true)
        #expect(IssuesDisplay.detail(i, now: now) == "#12 · @max · 3 commentaires · il y a 2 j")
        #expect(IssuesDisplay.accessibility(i) == "Pull request 12, Menu, par max, 3 commentaires")
        let seul = try issue(4, "Bug", user: nil, comments: 1)
        #expect(IssuesDisplay.detail(seul) == "#4 · 1 commentaire")
        #expect(IssuesDisplay.accessibility(try issue(5, "X", comments: 0)) == "Issue 5, X, par max")
    }

    @Test func etatsVidesEtQuestions() throws {
        #expect(IssuesDisplay.emptyTitle(pulls: true, open: true) == "Aucune pull request ouverte")
        #expect(IssuesDisplay.emptyTitle(pulls: false, open: false) == "Aucune issue fermée")
        #expect(IssuesDisplay.count(1, open: true) == "1 ouverte")
        #expect(IssuesDisplay.count(12, open: false) == "12 fermées")
        #expect(IssuesDisplay.closeQuestion(try issue(7, "A", pull: true)).hasPrefix("Fermer la pull request #7"))
        #expect(IssuesDisplay.mergeQuestion(try issue(7, "A", pull: true)).contains("« A »"))
    }

    @Test func actionsEtEtatDuDetail() {
        #expect(IssuesDisplay.actions(isPull: true, open: true) == [.merge, .close])
        #expect(IssuesDisplay.actions(isPull: false, open: true) == [.close])
        #expect(IssuesDisplay.actions(isPull: true, open: false) == [.reopen])
        #expect(IssuesDisplay.actions(isPull: true, open: false, merged: true).isEmpty)
        #expect(IssuesDisplay.Action.merge.title == "Fusionner")
        #expect(IssuesDisplay.stateLabel(open: true) == "Ouverte")
        #expect(IssuesDisplay.stateLabel(open: false) == "Fermée")
        #expect(IssuesDisplay.stateLabel(open: false, merged: true) == "Fusionnée")
        #expect(IssuesDisplay.commentsHeader(0) == "Commentaires")
        #expect(IssuesDisplay.commentsHeader(2) == "2 commentaires")
    }
}
