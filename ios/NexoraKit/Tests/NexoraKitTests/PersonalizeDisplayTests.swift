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

    @Test func tresGrandTexte() {
        // Taille normale inchangée ; en très grand texte, logo plus petit et colonnes plus larges.
        #expect(PersonalizeDisplay.previewOrbSize(bigText: false) == 72)
        #expect(PersonalizeDisplay.previewOrbSize(bigText: true) == 44)
        #expect(PersonalizeDisplay.swatchWidth(bigText: false) == 72)
        #expect(PersonalizeDisplay.swatchWidth(bigText: true) >= 120)
        // Deux colonnes tiennent sur le plus petit iPhone (320 pt, marges de la liste déduites).
        #expect(PersonalizeDisplay.swatchWidth(bigText: true) * 2 + 12 <= 320 - 40)
    }

    @Test func feuilleImport() {
        // Champ vide : rien à dire, « Importer » inactif.
        let vide = PersonalizeDisplay.importStatus(text: "  \n", fromClipboard: false)
        #expect(vide == .init(message: "", isError: false, canImport: false))
        // Un export : le nombre de réglages reconnus, et d'où il vient.
        let export = #"{"theme":"dark","haptics":true,"inconnu":1}"#
        let bon = PersonalizeDisplay.importStatus(text: export, fromClipboard: false)
        #expect(bon == .init(message: "2 réglages reconnus", isError: false, canImport: true))
        let repris = PersonalizeDisplay.importStatus(text: #" {"theme":"dark"} "#, fromClipboard: true)
        #expect(repris.message == "1 réglage reconnu, repris du presse-papiers")
        #expect(repris.canImport)
        // Autre chose (texte, JSON sans réglage) : dit sur place, sans fermer la feuille.
        for mauvais in ["bonjour", #"{"autre":1}"#, "[1,2]"] {
            let s = PersonalizeDisplay.importStatus(text: mauvais, fromClipboard: false)
            #expect(s.isError && !s.canImport)
            #expect(s.message.contains("Exporter mes réglages"))
        }
        #expect(Preferences.exportCount(nil) == 0)
    }
}
