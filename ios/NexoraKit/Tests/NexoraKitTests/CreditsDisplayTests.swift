import Foundation
import Testing
@testable import NexoraKit

@Suite("Écran Crédits")
struct CreditsDisplayTests {
    @Test func fournisseursTiresDuCatalogue() {
        let names = Catalog.providers.map(\.name)
        let detail = CreditsDisplay.providersDetail(names)
        #expect(!detail.contains("("))
        let brands = CreditsDisplay.brands(names)
        #expect(Set(brands).count == brands.count && brands.contains("Ollama Cloud"))
        #expect(CreditsDisplay.brands(["Ollama (local)", "Ollama", "LM Studio (local)"]) == ["Ollama", "LM Studio"])
        #expect(CreditsDisplay.providersTitle(["A (x)", "a", "B"]) == "Fournisseurs d'IA · 2")
        for p in Catalog.providers { #expect(detail.contains(CreditsDisplay.brand(p.name))) }
    }

    @Test func listesEnFrancais() {
        #expect(CreditsDisplay.list([]) == "")
        #expect(CreditsDisplay.list(["A"]) == "A")
        #expect(CreditsDisplay.list(["A", "B", "C"]) == "A, B et C")
        #expect(CreditsDisplay.cloudAgentsDetail(["Claude Code", "Aider (modèles gratuits)"])
            == "Claude Code et Aider, sur GitHub Actions")
    }

    @Test func versionEtVoiceOver() {
        #expect(CreditsDisplay.versionText("3.0.51") == "NEXORA iOS 3.0.51")
        #expect(CreditsDisplay.versionCopied("3.0.51") == "Version 3.0.51 copiée")
        #expect(CreditsDisplay.rowAccessibility("Security", "Clés") == "Security. Clés")
    }
}
