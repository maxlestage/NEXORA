import Foundation
import Testing
@testable import NexoraKit

@Suite("Accueil du premier lancement")
struct OnboardingDisplayTests {
    @Test func pagesCourtesEtChiffresDesCatalogues() {
        let pages = OnboardingDisplay.pages(providers: Catalog.providers.count, agents: Catalog.builtinAgents.count)
        #expect(pages.count == 3)
        #expect(pages.allSatisfy { $0.text.count <= 100 && $0.points.count == 3 })
        #expect(pages.allSatisfy { $0.points.allSatisfy { $0.text.count <= 50 } })
        #expect(pages[1].points[0].text == "\(Catalog.builtinAgents.count) agents intégrés")
        #expect(OnboardingDisplay.pages(providers: 23, agents: 1)[1].points[0].text == "1 agent intégré")
        #expect(OnboardingDisplay.pages(providers: 23, agents: 1)[0].text.hasPrefix("Plus de 20 fournisseurs"))
    }

    @Test func arrondi() {
        #expect(OnboardingDisplay.about(23) == "Plus de 20")
        #expect(OnboardingDisplay.about(20) == "20")
        #expect(OnboardingDisplay.about(7) == "7")
    }

    @Test func boutonsEtProgression() {
        #expect(OnboardingDisplay.primaryLabel(0, of: 3) == "Suivant")
        #expect(OnboardingDisplay.primaryLabel(2, of: 3) == "Commencer")
        #expect(OnboardingDisplay.showsSkip(1, of: 3))
        #expect(!OnboardingDisplay.showsSkip(2, of: 3))
        #expect(OnboardingDisplay.progress(1, of: 3) == "Page 2 sur 3")
        #expect(OnboardingDisplay.progress(9, of: 3) == "Page 3 sur 3")
    }
}
