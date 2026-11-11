import Foundation
import NexoraKit
import Testing
@testable import Nexora

/// La bibliothèque de l'app : skills et commandes installées, enregistrées et
/// relues au lancement (règles testées dans NexoraKit).
@MainActor
@Suite("Bibliothèque de l'app")
struct LibraryAppTests {
    private func freshDefaults() -> UserDefaults {
        let name = "nexora-library-tests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    @Test("skills, commandes et agents installés : enregistrés et relus")
    func persistence() {
        let d = freshDefaults()
        let lib = AgentLibrary(defaults: d)
        let skill = NexoraKit.LibraryItem(kind: .skill, owner: "o", repo: "r", ref: "main", path: "skills/pdf/SKILL.md", files: ["a.py"])
        let command = NexoraKit.LibraryItem(kind: .command, owner: "o", repo: "r", ref: "main", path: "commands/review.md")
        let agent = NexoraKit.LibraryItem(kind: .agent, owner: "o", repo: "r", ref: "main", path: "agents/secu.md")
        #expect(lib.install(skill, text: "---\nname: pdf\ndescription: Crée des PDF\n---\nCorps"))
        #expect(lib.install(command, text: "Relis $ARGUMENTS"))
        #expect(lib.install(agent, text: "---\nname: Sécu Pro\n---\nTu audites."))
        lib.setSkillAlways(lib.skills[0].id, true)

        let again = AgentLibrary(defaults: d)
        #expect(again.skillNamed("PDF")?.always == true)
        #expect(again.commandNamed("review")?.expand("src") == "Relis src")
        #expect(again.named("sécu-pro")?.name == "Sécu Pro")
        #expect(again.isInstalled(skill) && again.isInstalled(command) && again.isInstalled(agent))

        again.removeSkill(again.skills[0].id)
        again.removeCommand(again.commands[0].id)
        #expect(AgentLibrary(defaults: d).skills.isEmpty)
        #expect(AgentLibrary(defaults: d).commands.isEmpty)
        #expect(AgentLibrary(defaults: d).custom.count == 1)
    }
}
