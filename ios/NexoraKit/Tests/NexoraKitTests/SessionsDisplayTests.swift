import Foundation
import Testing
@testable import NexoraKit

@Suite("Liste des sessions")
struct SessionsDisplayTests {
    @Test func sessionsARelireEnPremier() {
        let items: [(String, SessionStatus)] = [
            ("a", .done), ("b", .running), ("c", .review), ("d", .stopped), ("e", .review), ("f", .shipped),
        ]
        let sections = SessionsDisplay.sections(items) { $0.1 }
        #expect(sections.map(\.kind) == [.toReview, .running, .recent])
        #expect(sections.map { $0.items.map(\.0) } == [["c", "e"], ["b"], ["a", "d", "f"]])
        #expect(sections.map(\.title) == ["À relire (2)", "En cours (1)", "Récentes"])
    }

    @Test func listeSimpleSansEnTete() {
        let sections = SessionsDisplay.sections([("a", SessionStatus.done), ("b", .stopped)]) { $0.1 }
        #expect(sections.count == 1)
        #expect(sections[0].title == nil)
        #expect(SessionsDisplay.sections([(String, SessionStatus)]()) { $0.1 }.isEmpty)
        // Une seule section « à relire » garde son titre : c'est une action à faire.
        #expect(SessionsDisplay.sections([("a", SessionStatus.review)]) { $0.1 }[0].title == "À relire (1)")
    }

    @Test func libelleDuSelecteur() {
        #expect(SessionsDisplay.pickerLabel(total: 5, running: 0, toReview: 0) == "Sessions (5)")
        #expect(SessionsDisplay.pickerLabel(total: 5, running: 2, toReview: 0) == "Sessions · 2 en cours")
        #expect(SessionsDisplay.pickerLabel(total: 5, running: 2, toReview: 1) == "Sessions · 1 à relire")
    }

    /// Comme dans la vue : sessions réelles (sur le fil principal), recherche par
    /// mission ou dépôt, puis groupement.
    @MainActor @Test func sessionsReellesFiltreesEtGroupees() {
        let runs = ["Corriger le menu", "Écrire les tests"].enumerated().map { i, task in
            AgentRun(
                llm: LLMClient(), github: GitHubAPI(token: nil), provider: groq, apiKey: "k", model: "m",
                owner: "max", repo: "site", branch: "main", task: task, id: "s\(i)"
            )
        }
        let shown = runs.filter { AgentsDisplay.matches("ecrire", $0.task, $0.reposLabel) }
        #expect(shown.map(\.id) == ["s1"])
        #expect(runs.filter { AgentsDisplay.matches("SITE", $0.task, $0.reposLabel) }.count == 2)
        let sections = SessionsDisplay.sections(runs) { $0.status }
        #expect(sections.flatMap { $0.items.map(\.id) }.sorted() == ["s0", "s1"])
    }

    @Test func avertissementAvantSuppression() {
        #expect(SessionsDisplay.deleteWarning(drafts: 0) == nil)
        #expect(SessionsDisplay.deleteWarning(drafts: 1) == "Son brouillon non envoyé sera perdu.")
        #expect(SessionsDisplay.deleteWarning(drafts: 3) == "Ses 3 brouillons non envoyés seront perdus.")
    }

    @Test func pastilleDePullRequest() {
        #expect(SessionsDisplay.pullChip("moi/site") == "PR site")
        #expect(SessionsDisplay.pullChip("site") == "PR site")
        #expect(SessionsDisplay.pullAccessibility("moi/site") == "Ouvrir la pull request de site sur GitHub")
    }
}
