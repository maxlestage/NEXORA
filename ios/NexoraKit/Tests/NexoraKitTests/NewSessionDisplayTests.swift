import Foundation
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

    @Test func brouillonDeMission() {
        #expect(NewSessionDisplay.draftToSave("  \n") == nil)
        #expect(NewSessionDisplay.draftToSave("Corrige le bug") == "Corrige le bug")
        let now = Date(timeIntervalSince1970: 1_000_000)
        let hier = now.addingTimeInterval(-24 * 3600)
        // Repris dans un champ vide s'il est récent.
        #expect(NewSessionDisplay.draftToRestore(saved: "Corrige", savedAt: hier, current: "", now: now) == "Corrige")
        // Jamais par-dessus une mission déjà tapée.
        #expect(NewSessionDisplay.draftToRestore(saved: "Corrige", savedAt: hier, current: "Autre", now: now) == nil)
        // Trop ancien, vide ou sans date : rien.
        let vieux = now.addingTimeInterval(-NewSessionDisplay.draftMaxAge - 1)
        #expect(NewSessionDisplay.draftToRestore(saved: "Corrige", savedAt: vieux, current: "", now: now) == nil)
        #expect(NewSessionDisplay.draftToRestore(saved: " ", savedAt: hier, current: "", now: now) == nil)
        #expect(NewSessionDisplay.draftToRestore(saved: "Corrige", savedAt: nil, current: "", now: now) == nil)
        #expect(NewSessionDisplay.draftToRestore(saved: nil, savedAt: hier, current: "", now: now) == nil)
    }
}

