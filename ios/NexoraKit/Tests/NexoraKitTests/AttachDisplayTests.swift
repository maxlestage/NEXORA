import Foundation
import Testing
@testable import NexoraKit

@Suite("Joindre un fichier")
struct AttachDisplayTests {
    private func item(_ name: String, size: Int? = nil, dir: Bool = false) throws -> ContentItem {
        var j: [String: Any] = ["name": name, "path": "src/\(name)", "type": dir ? "dir" : "file", "sha": "x"]
        if let size { j["size"] = size }
        return try JSONDecoder().decode(ContentItem.self, from: JSONSerialization.data(withJSONObject: j))
    }

    @Test func tailleLisible() {
        #expect(FilesDisplay.size(0) == "0 o")
        #expect(FilesDisplay.size(840) == "840 o")
        #expect(FilesDisplay.size(1_200) == "1,2 Ko")
        #expect(FilesDisplay.size(12_000) == "12 Ko")
        #expect(FilesDisplay.size(3_400_000) == "3,4 Mo")
        // Le résumé de l'éditeur garde le même format.
        #expect(FileEditorDisplay.summary("a\nb\n") == "2 lignes · 4 o")
    }

    @Test func rechercheDansUnDossier() throws {
        let items = [try item("Modèles", dir: true), try item("README.md"), try item("main.swift")]
        #expect(FilesDisplay.filter(items, query: "").count == 3)
        #expect(FilesDisplay.filter(items, query: " modele ").map(\.name) == ["Modèles"])
        #expect(FilesDisplay.filter(items, query: "M").map(\.name) == ["Modèles", "README.md", "main.swift"])
        #expect(FilesDisplay.filter(items, query: "zzz").isEmpty)
    }

    @Test func coutAnnonceAvantDeJoindre() throws {
        #expect(AttachDisplay.detail(try item("a.swift", size: 12_000)) == "12 Ko · ≈ 3,0k tokens")
        #expect(AttachDisplay.detail(try item("a.swift", size: 400)) == "400 o · ≈ 100 tokens")
        #expect(AttachDisplay.detail(try item("a.swift", size: 2)) == "2 o · ≈ 1 token")
        #expect(AttachDisplay.detail(try item("a.swift", size: 0)) == "Fichier vide")
        #expect(AttachDisplay.detail(try item("a.swift")) == "")
    }

    @Test func grosFichierPrevenu() throws {
        let gros = try item("gros.json", size: 240_000)
        #expect(AttachDisplay.isCut(gros))
        #expect(AttachDisplay.detail(gros) == "240 Ko · seul le début sera joint (≈ 15k tokens)")
        #expect(!AttachDisplay.isCut(try item("a.swift", size: ChatAttachment.maxChars)))
        #expect(!AttachDisplay.isCut(try item("a.swift")))
    }

    @Test func fichiersNonTexteEcartes() throws {
        #expect(!AttachDisplay.canAttach(try item("logo.PNG", size: 9_000)))
        #expect(!AttachDisplay.canAttach(try item("archive.tar.gz")))
        #expect(!AttachDisplay.canAttach(try item("src", dir: true)))
        #expect(AttachDisplay.canAttach(try item("main.swift")))
        #expect(AttachDisplay.canAttach(try item("Makefile")))
        #expect(AttachDisplay.canAttach(try item(".gitignore")))
        #expect(AttachDisplay.canAttach(try item("a.b.md")))
        #expect(AttachDisplay.detail(try item("logo.png", size: 9_000)) == "Ne peut pas être joint (pas du texte)")
    }

    @Test func voiceOverEtEtatVide() throws {
        #expect(AttachDisplay.accessibility(try item("a.swift", size: 12_000)) == "a.swift, 12 Ko, environ 3,0k tokens")
        #expect(AttachDisplay.accessibility(try item("a.swift")) == "a.swift")
        #expect(AttachDisplay.emptyTitle(query: "  ") == "Dossier vide")
        #expect(AttachDisplay.emptyTitle(query: " abc ") == "Aucun résultat pour « abc »")
    }
}
