import Foundation
import Testing
@testable import NexoraKit

/// Port de Flutter 2.2.85 : relance après une réponse vide avec d'autres réglages.
@MainActor
@Suite("Relance après une réponse vide")
struct AgentEmptyRetryTests {
    @Test("réglages normaux, puis réflexion courte et autre tirage")
    func options() {
        let normal = AgentRun.askOptions(nil)
        #expect(normal.temperature == 0.2)
        #expect(normal.level == nil)
        #expect(normal.maxTokens == 16000)
        let calm = AgentRun.askOptions(.eleve, calm: true)
        #expect((calm.temperature ?? 0) > 0.2)
        #expect(calm.level == .faible)
        // La place laissée à la réponse ne diminue pas.
        #expect(calm.maxTokens == AgentRun.askOptions(.eleve).maxTokens)
    }

    @Test("pour le modèle gratuit, la relance demande une réflexion courte")
    func freeModel() {
        let p = Catalog.providers.first { $0.id == "pollinations" }!
        #expect(reasoningParams(p, model: "openai", level: .faible)["reasoning_effort"] as? String == "low")
    }

    // En essai réel (« ajoute truncateMiddle et son test »), la réflexion de GPT-OSS
    // tournait en rond jusqu'à la limite : trois réponses vides avec les mêmes
    // réglages, et la session s'arrêtait sans finir.
    @Test("une réflexion qui tourne en rond ne bloque plus la session")
    func loopingThought() async {
        let done = NexoraKitTests.act(["tool": "finish", "args": ["summary": "Fait"]])
        // Le premier finish est vérifié (« est-ce fait ? »), le second accepté.
        let llm = ScriptLLM(["", "", done, done])
        let run = makeRun(llm, hub: Routes { _ in (200, #"{"tree":[]}"#) }, task: "Dis bonjour", checks: false)
        await run.run()
        #expect(run.summary == "Fait")
        #expect(llm.count == 4)
        // La première demande garde les réglages habituels ; les relances changent.
        #expect(llm.body(0)["temperature"] as? Double == 0.2)
        #expect(llm.body(1)["temperature"] as? Double == 0.7)
        #expect(llm.body(2)["temperature"] as? Double == 0.7)
        #expect(llm.body(3)["temperature"] as? Double == 0.2)
    }
}
