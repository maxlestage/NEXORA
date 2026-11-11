import Foundation
import Testing
@testable import NexoraKit

/// Essais contre de vrais services, seulement avec NEXORA_LIVE=1 (pas en CI).
@Suite("En vrai (NEXORA_LIVE=1)", .enabled(if: ProcessInfo.processInfo.environment["NEXORA_LIVE"] == "1"))
struct LiveTests {
    @Test("Pollinations répond, sans clé")
    func pollinations() async throws {
        let p = try #require(Catalog.providers.first { $0.id == "pollinations" })
        let (text, usage) = try await LLMClient().complete(provider: p, apiKey: nil, model: "openai", messages: [LLMMessage("user", "Réponds seulement : bonjour")])
        #expect(!text.isEmpty)
        #expect(usage.total > 0)
        let models = try await LLMClient().listModels(p, apiKey: nil)
        #expect(!models.isEmpty)
    }

    @Test("GitHub : lecture publique d'un fichier")
    func github() async throws {
        let f = try await GitHubAPI(token: nil).readFile("maxlestage", "NEXORA", path: "README.md", ref: "master")
        #expect(f.text.contains("NEXORA"))
    }
}
