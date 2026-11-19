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

    @Test func stylesDesMessages() {
        #expect(PersonalizeDisplay.bubbleStyles.map(\.value) == ["gradient", "filled", "minimal"])
        #expect(PersonalizeDisplay.bubbleStyleLabel("filled") == "Style Plein")
        #expect(PersonalizeDisplay.bubbleStyleLabel("inconnu") == "Style Contour")
    }

    @Test func effortLuParVoiceOver() {
        #expect(PersonalizeDisplay.effortAccessibility(label: "Équilibré", summary: "Bon pour tout")
                == "Effort par défaut : Équilibré, Bon pour tout")
        #expect(PersonalizeDisplay.effortAccessibility(label: "Rapide", summary: "  ") == "Effort par défaut : Rapide")
        // Avec un vrai niveau : ni émoji, ni virgule en trop.
        for level in ThinkLevel.allCases {
            let lu = PersonalizeDisplay.effortAccessibility(label: level.label, summary: level.summary)
            #expect(lu.hasPrefix("Effort par défaut : \(level.label)"))
            #expect(!lu.contains(level.emoji))
        }
    }
}
