import Foundation
import Testing
@testable import NexoraKit

@Suite("Valider les brouillons")
struct DraftsDisplayTests {
    @Test func boutonToutCocherOuDecocher() {
        #expect(DraftsDisplay.bulkAccepts(accepted: 1, total: 3))
        #expect(DraftsDisplay.bulkLabel(accepted: 1, total: 3) == "Tout cocher")
        #expect(DraftsDisplay.bulkLabel(accepted: 0, total: 2) == "Tout cocher")
        #expect(!DraftsDisplay.bulkAccepts(accepted: 3, total: 3))
        #expect(DraftsDisplay.bulkLabel(accepted: 3, total: 3) == "Tout décocher")
        #expect(DraftsDisplay.emptyHint(accepted: 0, total: 2) == "Cochez au moins un fichier pour valider.")
        #expect(DraftsDisplay.emptyHint(accepted: 1, total: 2) == nil)
        #expect(DraftsDisplay.emptyHint(accepted: 0, total: 0) == nil)
        #expect(DraftsDisplay.intro.count < 100)
    }

    @Test func ligneLueParVoiceOver() {
        #expect(DraftsDisplay.rowAccessibility(path: "a.swift", kind: .modified, added: 12, removed: 1, accepted: true)
            == "a.swift, Modifié, 12 lignes ajoutées, 1 retirée, coché")
        #expect(DraftsDisplay.rowAccessibility(path: "b.md", kind: .added, added: 1, removed: 0, accepted: false)
            == "b.md, Nouveau, 1 ligne ajoutée, 0 retirée, décoché")
        #expect(DraftsDisplay.rowAccessibility(path: "c", kind: .deleted, added: nil, removed: nil, accepted: true)
            == "c, Supprimé, coché")
    }
}
