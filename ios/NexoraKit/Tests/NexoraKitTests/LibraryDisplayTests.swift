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

    @Test func depotVideExplique() {
        let e = LibraryDisplay.emptyRepo(RepoScan(owner: "o", repo: "r", ref: "main", items: [], plugins: []))
        #expect(e.title == "Rien à installer ici")
        #expect(e.detail.hasPrefix("o/r ne contient"))
        #expect(!e.detail.contains("SKILL.md"))
        #expect(e.detail.count < 120)
    }

    @Test func selectionSansLesInstalles() {
        let a = item(.agent, "agents/a.md"), b = item(.agent, "agents/b.md"), c = item(.skill, "skills/c/SKILL.md")
        let installed: Set<String> = [a.key]
        let target = LibraryDisplay.selectable([a, b, c]) { installed.contains($0.key) }
        #expect(target.map(\.key) == [b.key, c.key])
        // Tout installé : tout reste cochable (mise à jour).
        #expect(LibraryDisplay.selectable([a]) { installed.contains($0.key) }.count == 1)
        #expect(LibraryDisplay.selectAllLabel(target: 2, shown: 3, allSelected: false) == "Sélectionner les 2 nouveaux")
        #expect(LibraryDisplay.selectAllLabel(target: 1, shown: 3, allSelected: false) == "Sélectionner le nouveau")
        #expect(LibraryDisplay.selectAllLabel(target: 3, shown: 3, allSelected: false) == "Tout sélectionner")
        #expect(LibraryDisplay.selectAllLabel(target: 2, shown: 3, allSelected: true) == "Tout décocher")
        #expect(LibraryDisplay.itemsHeader(12, installed: 3) == "12 éléments · 3 installés")
        #expect(LibraryDisplay.itemsHeader(1, installed: 0) == "1 élément")
        #expect(LibraryDisplay.installLabel(2, updates: 2) == "Mettre à jour 2 éléments")
        #expect(LibraryDisplay.installLabel(2, updates: 1) == "Installer 2 éléments")
    }

    @Test func detailEnTresGrandTexte() {
        let skill = item(.skill, "skills/pdf/SKILL.md", files: ["a", "b"])
        // Taille normale : la pastille « installé » reste à droite, le détail ne change pas.
        #expect(LibraryDisplay.itemDetail(skill, installed: true, bigText: false) == "Skill · 2 fichiers")
        #expect(LibraryDisplay.itemDetail(skill, installed: false, bigText: true) == "Skill · 2 fichiers")
        // Très grand texte : plus de pastille, l'état est écrit dans le détail.
        #expect(LibraryDisplay.itemDetail(skill, installed: true, bigText: true) == "Installé · Skill · 2 fichiers")
    }
}
