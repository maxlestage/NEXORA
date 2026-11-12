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
}
