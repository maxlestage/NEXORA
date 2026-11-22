import Foundation
import Testing
@testable import NexoraKit

@Suite("Liste des dépôts")
struct ReposDisplayTests {
    private func repo(_ name: String, description: String? = nil, language: String? = nil,
                      stars: Int? = nil, pushedAt: String? = nil) throws -> Repo {
        var j: [String: Any] = [
            "id": abs(name.hashValue % 100_000), "full_name": "max/\(name)", "name": name,
            "owner": ["login": "max"], "private": false, "html_url": "https://github.com/max/\(name)",
        ]
        if let description { j["description"] = description }
        if let language { j["language"] = language }
        if let stars { j["stargazers_count"] = stars }
        if let pushedAt { j["pushed_at"] = pushedAt }
        return try JSONDecoder().decode(Repo.self, from: JSONSerialization.data(withJSONObject: j))
    }

    @Test func rechercheNomDescriptionLangage() throws {
        let repos = [
            try repo("nexora", description: "Assistant de développement", language: "Swift"),
            try repo("site", description: "Page d'accueil", language: "HTML"),
        ]
        #expect(ReposDisplay.filter(repos, query: "").count == 2)
        #expect(ReposDisplay.filter(repos, query: " NEXORA ").map(\.name) == ["nexora"])
        #expect(ReposDisplay.filter(repos, query: "developpement").map(\.name) == ["nexora"])
        #expect(ReposDisplay.filter(repos, query: "html").map(\.name) == ["site"])
        #expect(ReposDisplay.filter(repos, query: "python").isEmpty)
    }

    @Test func detailsSansCaseVide() throws {
        let now = try #require(ReposDisplay.parseDate("2026-11-12T12:00:00Z"))
        #expect(ReposDisplay.meta(try repo("a", language: "Swift", stars: 12, pushedAt: "2026-11-09T12:00:00Z"), now: now)
            == "Swift · ★ 12 · il y a 3 j")
        #expect(ReposDisplay.meta(try repo("b", stars: 0, pushedAt: "2026-11-12T11:30:00.000Z"), now: now)
            == "il y a 30 min")
        #expect(ReposDisplay.meta(try repo("c"), now: now) == "")
    }

    @Test func nomCourtPourSesDepots() throws {
        let r = try repo("nexora")
        #expect(ReposDisplay.title(r, login: "max") == "nexora")
        #expect(ReposDisplay.title(r, login: "MAX") == "nexora")
        #expect(ReposDisplay.title(r, login: "autre") == "max/nexora")
        #expect(ReposDisplay.title(r, login: nil) == "max/nexora")
    }

    @Test func lancerAgentDepuisLaListe() throws {
        let r = try repo("nexora")
        #expect(ReposDisplay.agentAction == "Agent")
        #expect(ReposDisplay.agentLabel(r, login: "max") == "Lancer l'agent sur nexora")
        #expect(ReposDisplay.agentLabel(r, login: "autre") == "Lancer l'agent sur max/nexora")
    }

    @Test func avisApresCopieEtCreation() throws {
        let r = try repo("nexora")
        #expect(ReposDisplay.linkCopied == "Lien copié")
        #expect(ReposDisplay.createdToast(r, login: "max") == "Dépôt nexora créé")
        #expect(ReposDisplay.createdToast(r, login: "autre") == "Dépôt max/nexora créé")
        #expect(ReposDisplay.createdAction == "Lancer l'agent")
    }

    @Test func enTeteAvecCompte() {
        #expect(ReposDisplay.header(shown: 12, total: 12) == "12 dépôts")
        #expect(ReposDisplay.header(shown: 1, total: 1) == "1 dépôt")
        #expect(ReposDisplay.header(shown: 0, total: 0) == "0 dépôts")
        #expect(ReposDisplay.header(shown: 3, total: 12) == "3 sur 12")
    }

    @Test func lectureVoiceOver() throws {
        let now = try #require(ReposDisplay.parseDate("2026-11-12T12:00:00Z"))
        let r = try repo("nexora", description: "Assistant", language: "Swift", stars: 2, pushedAt: "2026-11-09T12:00:00Z")
        #expect(ReposDisplay.accessibility(r, login: "max", now: now) == "nexora, Assistant, Swift, étoiles 2, il y a 3 j")
        let j: [String: Any] = ["id": 1, "full_name": "o/p", "name": "p", "owner": ["login": "o"],
                                "private": true, "html_url": "https://github.com/o/p"]
        let p = try JSONDecoder().decode(Repo.self, from: JSONSerialization.data(withJSONObject: j))
        #expect(ReposDisplay.accessibility(p, login: "max", now: now) == "o/p, privé")
    }

    @Test func feuilleDepotJamaisBlanche() {
        func note(_ shown: Int, _ total: Int, loading: Bool = false, error: String? = nil,
                  query: String = "") -> ReposDisplay.PickerNote? {
            ReposDisplay.pickerNote(shown: shown, total: total, loading: loading, error: error, query: query)
        }
        #expect(note(3, 12) == nil)
        // Une liste déjà chargée reste affichée pendant un rechargement ou après une erreur.
        #expect(note(3, 12, loading: true, error: "Hors ligne") == nil)
        #expect(note(0, 12, query: " zzz ") == .noMatch("Aucun dépôt pour « zzz »"))
        #expect(note(0, 0, loading: true, error: "Hors ligne") == .loading)
        #expect(note(0, 0, error: "Hors ligne") == .failed("Hors ligne"))
        #expect(note(0, 0, error: "") == .empty)
        #expect(note(0, 0) == .empty)
    }

    @Test func depotDejaAjouteCocheDansLaFeuille() throws {
        let r = try repo("Nexora", description: "Assistant")
        #expect(ReposDisplay.isChosen(r, among: ["max/nexora"]))
        // Les cibles d'une routine portent la branche.
        #expect(ReposDisplay.isChosen(r, among: ["autre/site@main", "MAX/Nexora@main"]))
        #expect(!ReposDisplay.isChosen(r, among: []))
        #expect(!ReposDisplay.isChosen(r, among: ["max/nexora-site", "autre/nexora"]))
        #expect(ReposDisplay.pickerAccessibility(r, login: "max", chosen: false)
            == ReposDisplay.accessibility(r, login: "max"))
        #expect(ReposDisplay.pickerAccessibility(r, login: "max", chosen: true) == "Nexora, déjà ajouté, Assistant")
        #expect(ReposDisplay.pickerAccessibility(r, login: "autre", chosen: true) == "max/Nexora, déjà ajouté, Assistant")
        #expect(ReposDisplay.pickerChosenText == "Déjà ajouté")
    }
}
