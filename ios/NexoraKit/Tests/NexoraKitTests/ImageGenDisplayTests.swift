import Testing
@testable import NexoraKit

@Suite("Créer une image : affichage")
struct ImageGenDisplayTests {
    @Test("pluriels et libellés")
    func labels() {
        #expect(ImageGenDisplay.images(1) == "1 image")
        #expect(ImageGenDisplay.images(3) == "3 images")
        #expect(ImageGenDisplay.progress(1) == "Création de l'image…")
        #expect(ImageGenDisplay.progress(4) == "Création de 4 images…")
        #expect(ImageGenDisplay.createLabel(1) == "Créer")
        #expect(ImageGenDisplay.createLabel(2) == "Créer 2 images")
    }

    @Test("OpenAI choisi sans clé : « Créer » bloqué, Automatique et Pollinations restent possibles")
    func missingKey() {
        #expect(!ImageGenDisplay.canCreate(prompt: "un chat", engine: .openai, hasOpenAIKey: false))
        #expect(ImageGenDisplay.canCreate(prompt: "un chat", engine: .openai, hasOpenAIKey: true))
        #expect(ImageGenDisplay.canCreate(prompt: "un chat", engine: .auto, hasOpenAIKey: false))
        #expect(ImageGenDisplay.canCreate(prompt: "un chat", engine: .pollinations, hasOpenAIKey: false))
        #expect(!ImageGenDisplay.canCreate(prompt: "  \n", engine: .pollinations, hasOpenAIKey: false))
        let note = ImageGenDisplay.costNote(engine: .openai, hasOpenAIKey: false, shape: .square, quality: .medium, count: 1)
        #expect(note.contains("Modèles → OpenAI"))
    }

    @Test("coût annoncé selon le moteur, la qualité, le format et le nombre")
    func cost() {
        #expect(ImageGenDisplay.costNote(engine: .auto, hasOpenAIKey: false, shape: .square, quality: .high, count: 4)
            == "Gratuit avec Pollinations, sans clé.")
        #expect(ImageGenDisplay.costNote(engine: .auto, hasOpenAIKey: true, shape: .square, quality: .medium, count: 2)
            == "≈ 0,084 $ pour 2 images avec votre clé OpenAI (qualité moyenne).")
        let auto = ImageGenDisplay.costNote(engine: .openai, hasOpenAIKey: true, shape: .portrait, quality: .auto, count: 1)
        #expect(auto == "Jusqu'à ≈ 0,250 $ pour 1 image avec votre clé OpenAI (OpenAI choisit la qualité).")
    }

    @Test("note des réglages et coût sous les images")
    func notes() {
        #expect(ImageGenDisplay.keyNote(engine: .openai, hasOpenAIKey: false).contains("Modèles → OpenAI"))
        #expect(ImageGenDisplay.keyNote(engine: .openai, hasOpenAIKey: true).isEmpty)
        #expect(ImageGenDisplay.keyNote(engine: .pollinations, hasOpenAIKey: false).isEmpty)
        #expect(ImageGenDisplay.costLabel(model: "pollinations::flux", cost: nil) == "gratuit")
        #expect(ImageGenDisplay.costLabel(model: "openai::gpt-image-1", cost: 0.042) == "≈ 0,042 $")
        #expect(ImageGenDisplay.costLabel(model: nil, cost: nil).isEmpty)
    }
}
