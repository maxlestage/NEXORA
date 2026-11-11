import Testing
@testable import NexoraKit

@Suite("Skills depuis un lien GitHub")
struct SkillImportTests {
    @Test("les formes de liens reconnues")
    func links() {
        #expect(SkillImport.spec(from: "anthropics/skills") == "anthropics/skills")
        #expect(SkillImport.spec(from: "https://github.com/anthropics/skills") == "anthropics/skills")
        #expect(SkillImport.spec(from: "https://www.github.com/anthropics/skills.git/") == "anthropics/skills")
        #expect(SkillImport.spec(from: "github.com/anthropics/skills/tree/main/skills/pdf") == "anthropics/skills/tree/main/skills/pdf")
        #expect(SkillImport.spec(from: "https://github.com/anthropics/skills/blob/main/skills/pdf/SKILL.md") == "anthropics/skills/tree/main/skills/pdf")
        #expect(SkillImport.spec(from: "https://raw.githubusercontent.com/obra/superpowers/main/skills/brainstorming/SKILL.md") == "obra/superpowers/tree/main/skills/brainstorming")
        #expect(SkillImport.spec(from: "https://github.com/o/r/tree/main?tab=readme") == "o/r/tree/main")
        #expect(SkillImport.spec(from: "pas un lien") == nil)
        #expect(SkillImport.spec(from: "") == nil)
    }

    @Test("une skill installée redevient un élément à mettre à jour")
    func updateItem() throws {
        let sk = Skill(id: "s", name: "pdf", description: "", body: "x", owner: "anthropics", repo: "skills", ref: "main", dir: "skills/pdf", files: ["a.py"])
        let item = try #require(SkillImport.item(for: sk))
        #expect(item.path == "skills/pdf/SKILL.md" && item.kind == .skill && item.files == ["a.py"])
        #expect(SkillImport.item(for: Skill(id: "t", name: "x", description: "", body: "y")) == nil)
    }

    @Test("réinstaller une skill la met à jour sans perdre « Toujours »")
    func keepAlways() throws {
        var lib = UserLibrary()
        let item = LibraryItem(kind: .skill, owner: "o", repo: "r", ref: "main", path: "skills/pdf/SKILL.md")
        let first = lib.install(item, text: "---\nname: pdf\n---\nv1")
        #expect(first)
        let id = try #require(lib.skills.first?.id)
        lib.setSkillAlways(id, true)
        let second = lib.install(item, text: "---\nname: pdf\n---\nv2")
        #expect(second)
        #expect(lib.skills.count == 1)
        #expect(lib.skills[0].body == "v2" && lib.skills[0].always)
    }

    @Test("compte rendu")
    func report() {
        #expect(SkillImport.report(installed: 3, already: 1, failed: 0) == "3 skills installées · 1 déjà là (mise à jour).")
        #expect(SkillImport.report(installed: 0, already: 0, failed: 0) == "Aucune skill installée.")
    }
}

@Suite("Agents de l'app iOS")
struct IOSAgentsTests {
    @Test("les agents propres à l'app iOS s'ajoutent à ceux de l'app Flutter")
    func iosAgents() {
        let ids = Catalog.builtinAgents.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(ids.contains("builtin:assistant"))
        #expect(ids.contains("builtin:dev-swift"))
        #expect(Catalog.builtinAgents.count >= 30)
        let known = Set(agentToolList.map(\.name))
        for a in Catalog.builtinAgents {
            #expect(!a.systemPrompt.isEmpty && !a.description.isEmpty, "\(a.id)")
            #expect(a.tools.allSatisfy { known.contains($0) }, "\(a.id) : \(a.tools)")
        }
    }

    @Test("les sources de skills sont des dépôts propriétaire/nom")
    func sources() throws {
        for s in LibraryScanner.sources {
            let (owner, repo, ref, sub) = try LibraryScanner.parseRepoSpec(s.spec)
            #expect(!owner.isEmpty && !repo.isEmpty && ref == nil && sub.isEmpty, "\(s.spec)")
        }
        #expect(Set(LibraryScanner.sources.map(\.spec)).count == LibraryScanner.sources.count)
    }
}
