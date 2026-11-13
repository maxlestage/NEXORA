import Foundation
import Testing
@testable import NexoraKit

@Suite("Écran Bibliothèque")
struct LibraryDisplayTests {
    private func item(_ kind: LibraryItemKind, _ path: String, plugin: String? = nil, files: [String] = []) -> LibraryItem {
        LibraryItem(kind: kind, owner: "o", repo: "r", ref: "main", path: path, plugin: plugin, files: files)
    }

    @Test func lienDeFichierOuDepot() {
        #expect(LibraryDisplay.isFileLink(" https://github.com/o/r/blob/main/agents/revue.MD "))
        #expect(!LibraryDisplay.isFileLink("o/r/agents"))
        #expect(!LibraryDisplay.isFileLink("https://github.com/o/r"))
        #expect(!LibraryDisplay.isFileLink("o/r/agents/revue.md"))
    }

    @Test func filtreSansAccentNiCasse() {
        let scan = RepoScan(owner: "o", repo: "r", ref: "main", items: [
            item(.agent, "agents/securite.md"),
            item(.skill, "skills/pdf/SKILL.md", plugin: "Documents"),
            item(.command, "commands/deploy.md"),
        ], plugins: [PluginRef(name: "Outils", description: "Sécurité du code", spec: "o/r/p")])
        #expect(LibraryDisplay.items(scan, kind: nil, query: "").count == 3)
        #expect(LibraryDisplay.items(scan, kind: .skill, query: "").map(\.name) == ["pdf"])
        #expect(LibraryDisplay.items(scan, kind: nil, query: "SÉCURITÉ").map(\.name) == ["securite"])
        #expect(LibraryDisplay.items(scan, kind: nil, query: "documents").map(\.name) == ["pdf"])
        #expect(LibraryDisplay.items(scan, kind: .command, query: "pdf").isEmpty)
        #expect(LibraryDisplay.plugins(scan, query: "securite").count == 1)
        #expect(LibraryDisplay.plugins(scan, query: "python").isEmpty)
    }

    @Test func vraisPluriels() {
        #expect(LibraryDisplay.itemDetail(item(.skill, "skills/pdf/SKILL.md", plugin: "doc", files: ["a.py"])) == "Skill · plugin doc · 1 fichier")
        #expect(LibraryDisplay.itemDetail(item(.skill, "skills/pdf/SKILL.md", files: ["a", "b"])) == "Skill · 2 fichiers")
        #expect(LibraryDisplay.itemDetail(item(.agent, "agents/x.md")) == "Sous-agent")
        #expect(LibraryDisplay.itemsCount(1) == "1 élément")
        #expect(LibraryDisplay.installLabel(3) == "Installer 3 éléments")
        #expect(LibraryDisplay.installed(1, of: 1) == "1 élément installé")
        #expect(LibraryDisplay.installed(4, of: 4) == "4 éléments installés")
        #expect(LibraryDisplay.installed(2, of: 3) == "2 sur 3 installés (les autres sont illisibles)")
        #expect(LibraryDisplay.intro.count < 120)
    }
}
