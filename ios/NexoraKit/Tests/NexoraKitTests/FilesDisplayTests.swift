import Foundation
import Testing
@testable import NexoraKit

@Suite("Fichiers d'un dépôt")
struct FilesDisplayTests {
    private func item(_ name: String, dir: Bool = false) throws -> ContentItem {
        let j: [String: Any] = ["name": name, "path": "src/\(name)", "type": dir ? "dir" : "file", "sha": "x"]
        return try JSONDecoder().decode(ContentItem.self, from: JSONSerialization.data(withJSONObject: j))
    }

    @Test func dossiersDAbordPuisOrdreNaturel() throws {
        let items = [
            try item("b10.swift"), try item("Zeta", dir: true), try item("a.md"),
            try item("b2.swift"), try item("alpha", dir: true), try item("README.md"),
        ]
        #expect(FilesDisplay.sorted(items).map(\.name)
            == ["alpha", "Zeta", "a.md", "b2.swift", "b10.swift", "README.md"])
        #expect(FilesDisplay.sorted([]).isEmpty)
    }

    @Test func resume() throws {
        #expect(FilesDisplay.summary([]) == "")
        #expect(FilesDisplay.summary([try item("a")]) == "1 fichier")
        #expect(FilesDisplay.summary([try item("d", dir: true), try item("e", dir: true), try item("a")])
            == "2 dossiers · 1 fichier")
        #expect(FilesDisplay.summary([try item("d", dir: true), try item("a"), try item("b")])
            == "1 dossier · 2 fichiers")
    }
}
