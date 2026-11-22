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

    @Test func fermerUneFicheModifieeDemandeAvant() {
        let a = Agent(id: "x", name: "Relecteur", systemPrompt: "Relis le code.", tools: ["read_file", "github"])
        // Rien de changé : la fiche se ferme d'un geste.
        #expect(!AgentEditorDisplay.losesChanges(original: a, edited: a))
        var b = a
        b.systemPrompt = "Relis le code. \n"
        b.tools = ["github", "read_file"]
        #expect(!AgentEditorDisplay.losesChanges(original: a, edited: b))
        // Une consigne, un outil ou un modèle changé : on demande.
        b.systemPrompt = "Relis le code et les tests."
        #expect(AgentEditorDisplay.losesChanges(original: a, edited: b))
        var c = a
        c.tools = ["read_file"]
        #expect(AgentEditorDisplay.losesChanges(original: a, edited: c))
        var d = a
        d.model = "anthropic::claude"
        #expect(AgentEditorDisplay.losesChanges(original: a, edited: d))
        // Un nouvel agent encore vide ne pose pas de question ; commencé, si.
        let vide = Agent(id: "n", name: "", systemPrompt: "")
        var commence = vide
        commence.name = "  "
        #expect(!AgentEditorDisplay.losesChanges(original: vide, edited: commence))
        commence.name = "Testeur"
        #expect(AgentEditorDisplay.losesChanges(original: vide, edited: commence))
        #expect(AgentEditorDisplay.leaveTitle(isNew: true) == "Abandonner ce nouvel agent ?")
        #expect(AgentEditorDisplay.leaveTitle(isNew: false) == "Abandonner les modifications ?")
        #expect(AgentEditorDisplay.leaveMessage(isNew: false, missing: nil) == "L'agent restera comme avant.")
        #expect(AgentEditorDisplay.leaveMessage(isNew: true, missing: "Donnez un nom pour enregistrer.")
            == "L'agent ne sera pas créé. Donnez un nom pour enregistrer.")
    }
}
