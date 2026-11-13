import Testing
@testable import NexoraKit

@Suite("Écran Personnaliser")
struct PersonalizeDisplayTests {
    @Test func valeursEnMots() {
        #expect(PersonalizeDisplay.percent(1.15) == "115 %")
        #expect(PersonalizeDisplay.percent(0.85) == "85 %")
        #expect(PersonalizeDisplay.temperature(0.2) == "Précise · 0.2")
        #expect(PersonalizeDisplay.temperature(0.7) == "Équilibrée · 0.7")
        #expect(PersonalizeDisplay.temperature(1.2) == "Créative · 1.2")
        #expect(PersonalizeDisplay.voiceRate(0.3) == "Lente")
        #expect(PersonalizeDisplay.voiceRate(0.5) == "Normale")
        #expect(PersonalizeDisplay.voiceRate(0.7) == "Rapide")
    }

    @Test func assistantModifie() {
        let base = (savedName: "NEXORA", savedAbout: "dev", savedStyle: "")
        #expect(!PersonalizeDisplay.assistantChanged(name: "NEXORA", about: "dev", style: "",
                                                      savedName: base.savedName, savedAbout: base.savedAbout, savedStyle: base.savedStyle))
        // Nom vide ou avec espaces : nettoyé comme à l'enregistrement.
        #expect(!PersonalizeDisplay.assistantChanged(name: "  ", about: "dev", style: "",
                                                      savedName: base.savedName, savedAbout: base.savedAbout, savedStyle: base.savedStyle))
        #expect(PersonalizeDisplay.assistantChanged(name: "Jarvis", about: "dev", style: "",
                                                     savedName: base.savedName, savedAbout: base.savedAbout, savedStyle: base.savedStyle))
        #expect(PersonalizeDisplay.assistantChanged(name: "NEXORA", about: "dev", style: "sois bref",
                                                     savedName: base.savedName, savedAbout: base.savedAbout, savedStyle: base.savedStyle))
    }
}
