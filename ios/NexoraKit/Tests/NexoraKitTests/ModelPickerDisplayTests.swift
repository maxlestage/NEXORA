import Testing
@testable import NexoraKit

@Suite struct ModelPickerDisplayTests {
    @Test func rechercheTolerante() {
        #expect(ModelPickerDisplay.matches("llama 3", model: "llama-3.1-8b-instant"))
        #expect(ModelPickerDisplay.matches("GPT4o", model: "gpt-4o-mini"))
        #expect(ModelPickerDisplay.matches("groq llama", model: "llama-3.3-70b", provider: "Groq"))
        #expect(ModelPickerDisplay.matches("rapide", model: "x", detail: "Très rapide"))
        #expect(ModelPickerDisplay.matches("  ", model: "x"))
        #expect(!ModelPickerDisplay.matches("qwen", model: "llama-3"))
        #expect(!ModelPickerDisplay.matches("llama 4", model: "llama-3.1"))
    }

    @Test func etatsVides() {
        #expect(ModelPickerDisplay.empty(found: 3, query: "x", onlyFree: true) == nil)
        #expect(ModelPickerDisplay.empty(found: 0, query: "", onlyFree: false) == nil)
        #expect(ModelPickerDisplay.empty(found: 0, query: "qwen ", onlyFree: false)?.title == "Aucun modèle pour « qwen »")
        #expect(ModelPickerDisplay.empty(found: 0, query: "", onlyFree: true)?.action == "Voir aussi les payants")
        #expect(ModelPickerDisplay.emptySection(onlyFree: false, hasLiveList: false) == "Aucun modèle : touchez « Charger la liste ».")
        #expect(ModelPickerDisplay.emptySection(onlyFree: true, hasLiveList: false) == "Aucun modèle gratuit chez ce fournisseur.")
    }

    @Test func voiceOver() {
        #expect(ModelPickerDisplay.accessibility(model: "gpt-4o", provider: "OpenAI", free: false, local: false, selected: true)
            == "gpt-4o, OpenAI, modèle actuel")
        #expect(ModelPickerDisplay.accessibility(model: "m", provider: "Groq", free: true, local: true, selected: false)
            == "m, Groq, gratuit, local")
    }
}
