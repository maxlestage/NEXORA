import Testing
@testable import NexoraKit

@Suite("Écran Nouvelle session")
struct NewSessionDisplayTests {
    @Test func detailMarqueLePrincipal() {
        #expect(NewSessionDisplay.repoDetail(index: 0, branch: "main") == "Principal · branche main")
        #expect(NewSessionDisplay.repoDetail(index: 1, branch: "dev") == "Branche dev")
    }

    @Test func aidesCourtes() {
        #expect(NewSessionDisplay.reposFooter(connected: false, count: 0) != nil)
        #expect(NewSessionDisplay.reposFooter(connected: true, count: 1) == nil)
        #expect(NewSessionDisplay.reposFooter(connected: true, count: 2) != nil)
        #expect(NewSessionDisplay.agentFooter(autoCi: true) != NewSessionDisplay.agentFooter(autoCi: false))
        // Textes courts : moins de 140 caractères chacun.
        for t in [NewSessionDisplay.agentFooter(autoCi: true), NewSessionDisplay.agentFooter(autoCi: false),
                  NewSessionDisplay.autoCiCaption, NewSessionDisplay.autoMergeCaption] {
            #expect(t.count < 140, "\(t)")
        }
    }

    @Test func raisonDeNePasLancer() {
        #expect(NewSessionDisplay.startProblem(mission: "  \n", repoCount: 1) == "Décrivez la mission.")
        #expect(NewSessionDisplay.startProblem(mission: "Corrige", repoCount: 0) == "Ajoutez au moins un dépôt.")
        #expect(NewSessionDisplay.startProblem(mission: "Corrige", repoCount: 1) == nil)
    }
}
