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
}
