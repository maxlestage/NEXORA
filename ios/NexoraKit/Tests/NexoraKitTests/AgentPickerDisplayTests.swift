@testable import NexoraKit
import Testing

@Suite struct AgentPickerDisplayTests {
    private let agents = [
        Agent(id: "mail", name: "Rédacteur d'e-mails", systemPrompt: "", description: "Écrit vos messages", category: "Écriture"),
        Agent(id: "relu", name: "Relecteur", systemPrompt: "", description: "Relit votre code", category: "Code"),
        Agent(id: "trad", name: "Traducteur", systemPrompt: "", category: "Écriture"),
    ]

    @Test func rechercheParMotsSansAccentsNiTirets() {
        #expect(AgentPickerDisplay.matches("redac mail", agents[0]))
        #expect(AgentPickerDisplay.matches("CODE", agents[1]))
        #expect(AgentPickerDisplay.matches("ecriture", agents[2]))
        #expect(!AgentPickerDisplay.matches("mail code", agents[0]))
        #expect(AgentPickerDisplay.matches("  ", agents[0]))
    }

    @Test func groupesDansLOrdreSansCategorieVide() {
        let tous = AgentPickerDisplay.groups(agents, query: "")
        #expect(tous.map(\.category) == ["Écriture", "Code"])
        #expect(tous[0].agents.map(\.id) == ["mail", "trad"])
        let code = AgentPickerDisplay.groups(agents, query: "relit")
        #expect(code.map(\.category) == ["Code"])
        #expect(AgentPickerDisplay.groups(agents, query: "zzz").isEmpty)
    }

    @Test func ligneSansAgentEtEtatVide() {
        #expect(AgentPickerDisplay.showsNone(query: ""))
        #expect(AgentPickerDisplay.showsNone(query: "assistant"))
        #expect(!AgentPickerDisplay.showsNone(query: "relecteur"))
        #expect(AgentPickerDisplay.emptyTitle(found: 0, query: " zzz ") == "Aucun agent pour « zzz »")
        #expect(AgentPickerDisplay.emptyTitle(found: 1, query: "zzz") == nil)
        #expect(AgentPickerDisplay.emptyTitle(found: 0, query: "sans") == nil)
        #expect(AgentPickerDisplay.emptyTitle(found: 0, query: "") == nil)
    }

    @Test func voiceOver() {
        #expect(AgentPickerDisplay.accessibility(name: "Relecteur", description: "Relit votre code", selected: true)
            == "Relecteur, Relit votre code, agent actuel")
        #expect(AgentPickerDisplay.accessibility(name: "Traducteur", description: " ", selected: false) == "Traducteur")
    }

    @Test func tresGrandTexte() {
        #expect(AgentPickerDisplay.descriptionLines(bigText: false) == 2)
        #expect(AgentPickerDisplay.descriptionLines(bigText: true) == 4)
        #expect(AgentPickerDisplay.title(emoji: "🔍", name: "Relecteur", bigText: false) == "Relecteur")
        #expect(AgentPickerDisplay.title(emoji: "🔍", name: "Relecteur", bigText: true) == "🔍 Relecteur")
        #expect(AgentPickerDisplay.title(emoji: " ", name: "Relecteur", bigText: true) == "Relecteur")
    }

    @Test func agentActuelEnTeteSansDoublon() {
        let actuel = AgentPickerDisplay.current(agents, selected: agents[2], query: "")
        #expect(actuel?.id == agents[2].id)
        #expect(AgentPickerDisplay.current(agents, selected: agents[2], query: "mail") == nil)
        #expect(AgentPickerDisplay.current(agents, selected: nil, query: "") == nil)
        let reste = AgentPickerDisplay.groups(agents, query: "", excluding: actuel?.id)
        #expect(!reste.flatMap(\.agents).contains { $0.id == agents[2].id })
        #expect(reste.flatMap(\.agents).count == agents.count - 1)
    }
}
