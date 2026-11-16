import Foundation
import Testing
@testable import NexoraKit

@Suite("Écran Agents")
struct AgentsDisplayTests {
    @Test func rechercheSansAccentNiCasse() {
        #expect(AgentsDisplay.matches("", "Relecteur"))
        #expect(AgentsDisplay.matches("   ", "Relecteur"))
        #expect(AgentsDisplay.matches("ecrire", "Écrire des tests"))
        #expect(AgentsDisplay.matches(" REVUE ", "Agent", "Fait une revue de code"))
        #expect(!AgentsDisplay.matches("python", "Relecteur", "Revue de code Swift"))
    }

    @Test func outilsEnMotsSimples() {
        #expect(AgentsDisplay.toolsSummary([]) == "")
        #expect(AgentsDisplay.toolsSummary(["Read"]) == "1 outil")
        #expect(AgentsDisplay.toolsSummary(["Read", "Write", "Bash"]) == "3 outils")
    }

    @Test func ajoutDeSkillsBienPlace() {
        #expect(AgentsDisplay.addPlace(hasItems: false, query: "") == .top)
        #expect(AgentsDisplay.addPlace(hasItems: false, query: "pdf") == .top)
        #expect(AgentsDisplay.addPlace(hasItems: true, query: "  ") == .bottom)
        #expect(AgentsDisplay.addPlace(hasItems: true, query: "pdf") == .hidden)
    }

    @Test func enTeteAvecNombre() {
        #expect(AgentsDisplay.header("Skills", count: 0) == "Skills")
        #expect(AgentsDisplay.header("Skills", count: 3) == "Skills (3)")
    }
}
