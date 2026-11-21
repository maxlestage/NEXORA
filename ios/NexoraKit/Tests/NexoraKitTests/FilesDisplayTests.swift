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

    @Test func rechercheDansUnDossier() throws {
        let items = [try item("src", dir: true), try item("main.swift"), try item("Modèles.swift")]
        // Sans recherche : le résumé habituel du dossier.
        #expect(FilesDisplay.footer(shown: items, total: 3, query: " ") == "1 dossier · 2 fichiers")
        // Pendant une recherche : ce qu'elle garde, sur le total.
        let gardés = FilesDisplay.filter(items, query: "swift")
        #expect(FilesDisplay.footer(shown: gardés, total: 3, query: "swift") == "2 résultats sur 3")
        #expect(FilesDisplay.footer(shown: FilesDisplay.filter(items, query: "modele"), total: 3, query: "modele")
            == "1 résultat sur 3")
        // Aucun résultat : l'état vide le dit déjà, la ligne reste vide.
        #expect(FilesDisplay.footer(shown: [], total: 3, query: "zzz") == "")
        #expect(FilesDisplay.searchPrompt == "Chercher dans ce dossier")
    }

    @Test func avisApresCreationDUnFichier() {
        // Dans le dossier affiché : le nom suffit (la liste rechargée le montre).
        #expect(FilesDisplay.createdToast(path: "src/a.swift", folder: "src", branch: "main") == "« a.swift » créé sur main")
        #expect(FilesDisplay.createdToast(path: "LISEZMOI.md", folder: "", branch: "dev") == "« LISEZMOI.md » créé sur dev")
        // Créé ailleurs (chemin modifié à la main) : le chemin entier, pour le retrouver.
        #expect(FilesDisplay.createdToast(path: "src/vues/b.swift", folder: "src", branch: "main") == "« src/vues/b.swift » créé sur main")
        #expect(FilesDisplay.createdToast(path: "c.txt", folder: "src", branch: "main") == "« c.txt » créé sur main")
        #expect(FilesDisplay.isDirectChild("src/a.swift", of: "src/"))
        #expect(!FilesDisplay.isDirectChild("src/vues/b.swift", of: "src"))
        #expect(!FilesDisplay.isDirectChild("a.swift", of: "src"))
        #expect(!FilesDisplay.isDirectChild("", of: ""))
    }
}
