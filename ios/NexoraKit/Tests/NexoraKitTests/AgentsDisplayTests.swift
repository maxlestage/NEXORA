import Foundation
import Testing
@testable import NexoraKit

@Suite("Écran Agents")
struct AgentsDisplayTests {
    @Test func confirmationDeSuppressionClaire() {
        #expect(AgentsDisplay.removalTitle("Relecteur", kind: .agent) == "Supprimer l'agent « Relecteur » ?")
        #expect(AgentsDisplay.removalTitle(" pdf ", kind: .skill) == "Supprimer la skill « pdf » ?")
        #expect(AgentsDisplay.removalTitle("/revue", kind: .command) == "Supprimer la commande « /revue » ?")
        #expect(AgentsDisplay.removalTitle("  ", kind: .agent) == "Supprimer l'agent ?")
        #expect(AgentsDisplay.removalMessage(.agent).contains("conversations restent"))
        #expect(AgentsDisplay.removalMessage(.skill) == AgentsDisplay.removalMessage(.command))
    }

    @Test func rechercheSansAccentNiCasse() {
        #expect(AgentsDisplay.matches("", "Relecteur"))
        #expect(AgentsDisplay.matches("   ", "Relecteur"))
        #expect(AgentsDisplay.matches("ecrire", "Écrire des tests"))
        #expect(AgentsDisplay.matches(" REVUE ", "Agent", "Fait une revue de code"))
        #expect(!AgentsDisplay.matches("python", "Relecteur", "Revue de code Swift"))
        // Plusieurs mots : dans n'importe quel ordre, répartis entre les textes.
        #expect(AgentsDisplay.matches("code revue", "Relecteur", "Revue de code Swift"))
        #expect(AgentsDisplay.matches("relecteur swift", "Relecteur", "Revue de code Swift"))
        #expect(AgentsDisplay.matches("revue  swift", "Relecteur", "Revue de code Swift"))
        #expect(AgentsDisplay.matches("tests écrire", "Écrire des tests"))
        #expect(AgentsDisplay.matches("revue de code", "Relecteur", "Revue de code Swift"))
        #expect(!AgentsDisplay.matches("revue python", "Relecteur", "Revue de code Swift"))
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

@Suite("Fiche d'un agent")
struct AgentEditorDisplayTests {
    @Test func outilsLisiblesEtResumes() {
        let all = AgentEditorDisplay.choosableTools(agentToolList.map(\.name))
        #expect(!all.contains("finish"))
        // Chaque outil cochable a un libellé simple, différent de son nom technique.
        for t in all { #expect(AgentEditorDisplay.toolLabel(t) != t) }
        #expect(AgentEditorDisplay.toolsValue([], total: all.count) == "Tous")
        #expect(AgentEditorDisplay.toolsValue(["finish"], total: all.count) == "Tous")
        #expect(AgentEditorDisplay.toolsValue(["read_file", "github"], total: all.count) == "2 sur \(all.count)")
        #expect(AgentEditorDisplay.toolsValue(all, total: all.count) == "Tous")
    }

    @Test func nomPourAppelerEtRaisonDuBoutonGrise() {
        #expect(AgentEditorDisplay.handle("Revue de Code") == "@revue-de-code")
        #expect(AgentEditorDisplay.handle("  Rédacteur  ") == "@rédacteur")
        #expect(AgentEditorDisplay.handle("   ") == nil)
        // Le nom affiché est bien reconnu au début d'un message.
        #expect(ChatLogic.mention(in: "@revue-de-code relis") == "revue-de-code")
        #expect(AgentEditorDisplay.missing(name: "", prompt: "") == "Donnez un nom et une consigne pour enregistrer.")
        #expect(AgentEditorDisplay.missing(name: "A", prompt: " \n") == "Écrivez une consigne pour enregistrer.")
        #expect(AgentEditorDisplay.missing(name: " ", prompt: "Rôle") == "Donnez un nom pour enregistrer.")
        #expect(AgentEditorDisplay.missing(name: "A", prompt: "Rôle") == nil)
    }
}
