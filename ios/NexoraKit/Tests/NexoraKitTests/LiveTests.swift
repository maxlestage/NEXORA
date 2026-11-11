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

    @Test("Pollinations crée une image, sans clé")
    func pollinationsImage() async throws {
        let r = try await ImageGenClient(timeout: 240).generate(prompt: "a red apple on a wooden table", count: 2, shape: .square, engine: .pollinations, openAIKey: nil)
        print("Pollinations : \(r.images.count) image(s) sur 2, \(r.images.map(\.data.count)) octets, \(r.images.map(\.mimeType))")
        #expect(r.images.count >= 1)
        #expect(r.images.allSatisfy { ChatImageStore.looksLikeImage($0.data) && $0.data.count > 10_000 })
    }

    @Test("GitHub : lecture publique d'un fichier")
    func github() async throws {
        let f = try await GitHubAPI(token: nil).readFile("maxlestage", "NEXORA", path: "README.md", ref: "master")
        #expect(f.text.contains("NEXORA"))
    }
}
