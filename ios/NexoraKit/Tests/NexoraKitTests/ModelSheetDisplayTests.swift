@testable import NexoraKit
import Testing

@Suite struct ModelSheetDisplayTests {
    @Test func ajouterDesModelesSeulementAvecPeuDeFournisseurs() {
        #expect(ModelSheetDisplay.showsAddModels(remoteReady: 0))
        #expect(ModelSheetDisplay.showsAddModels(remoteReady: 2))
        #expect(!ModelSheetDisplay.showsAddModels(remoteReady: 3))
    }

    @Test func noteDeLEffort() {
        let moyen = ModelSheetDisplay.effortFooter(.moyen, nativeEffort: true, model: "x")
        #expect(moyen.hasPrefix("Recommandé · "))
        #expect(moyen.contains(ThinkLevel.moyen.summary))
        #expect(ModelSheetDisplay.effortFooter(.faible, nativeEffort: true, model: "x") == ThinkLevel.faible.summary)
        #expect(ModelSheetDisplay.effortFooter(.max, nativeEffort: true, model: nil).hasPrefix("Utilisation 3,5× ou plus · "))
        let sans = ModelSheetDisplay.effortFooter(.eleve, nativeEffort: false, model: "llama-3")
        #expect(sans.contains("« llama-3 » n'a pas de réglage natif"))
    }

    @Test func textesCourts() {
        #expect(ModelSheetDisplay.moreModelsSubtitle(providerName: "Anthropic") == "Anthropic et tous les autres")
        let note = ModelList.nonNativeNote("llama-3")
        #expect(note.count <= 70)
        #expect(ModelSheetDisplay.effortFooter(.eleve, nativeEffort: false, model: "llama-3").hasSuffix(note))
        #expect(ModelList.addModelsHint(providerId: "pollinations").count <= 130)
        #expect(ModelList.addModelsHint(providerId: "groq").count <= 80)
    }

    @Test func libelleVoiceOverSansEmoji() {
        #expect(ModelSheetDisplay.accessibility(title: "🧠 Opus 5.5", subtitle: "Anthropic", checked: false) == "Opus 5.5, Anthropic")
        #expect(ModelSheetDisplay.accessibility(title: "GPT-5", subtitle: "Rapide", checked: true) == "GPT-5, Rapide, modèle actuel")
        #expect(ModelSheetDisplay.accessibility(title: "☁️ Llama 3.3", subtitle: "Groq", checked: false) == "Llama 3.3, Groq")
        #expect(ModelSheetDisplay.accessibility(title: "Mistral", subtitle: "", checked: false) == "Mistral")
    }
}
