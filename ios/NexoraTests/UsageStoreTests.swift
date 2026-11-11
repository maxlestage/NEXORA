import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import NexoraKit
import Testing
@testable import Nexora

/// Un faux serveur de crédit OpenRouter : compte les requêtes.
private final class CreditServer: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return calls
    }

    private func hit() {
        lock.lock()
        calls += 1
        lock.unlock()
    }

    func data(_ request: URLRequest) async throws -> (HTTPHead, Data) {
        hit()
        let body = request.url?.path.hasSuffix("/credits") == true
            ? #"{"data":{"total_credits":10,"total_usage":6.79}}"#
            : #"{"data":{"usage":0,"limit":null,"is_free_tier":false}}"#
        return (HTTPHead(status: 200), Data(body.utf8))
    }

    func lines(_ request: URLRequest) async throws -> (HTTPHead, AsyncThrowingStream<String, Error>) {
        throw URLError(.unsupportedURL)
    }
}

/// Le témoin de crédit de l'app (la logique est testée dans NexoraKit).
@MainActor
@Suite("Usage (app)")
struct UsageStoreTests {
    private func freshDefaults() -> UserDefaults {
        let name = "nexora-usage-tests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    @Test("le solde prépayé est enregistré, puis relu au prochain lancement")
    func persistence() {
        let d = freshDefaults()
        let s = UsageStore(defaults: d, loadCatalog: false)
        s.setPrepaid("anthropic", 10)
        s.recordUsage("anthropic", model: "claude-opus-5-5", usage: TokenUsage(100_000, 50_000)) // 0,40 $ + 1 $
        #expect(abs((s.of("anthropic").prepaidLeft ?? 0) - 8.6) < 1e-9)
        s.saveNow()
        let again = UsageStore(defaults: d, loadCatalog: false)
        #expect(abs((again.of("anthropic").prepaidLeft ?? 0) - 8.6) < 1e-9)
    }

    @Test("le solde est relu peu après une réponse ; deux réponses d'affilée = une lecture")
    func refreshSoon() async throws {
        let server = CreditServer()
        let s = UsageStore(defaults: freshDefaults(), quotas: QuotaService(transport: server), loadCatalog: false)
        let p = try #require(Catalog.providers.first { $0.id == "openrouter" })
        s.refreshSoon(p, key: "k", delay: .zero)
        s.refreshSoon(p, key: "k", delay: .zero)
        try await Task.sleep(for: .milliseconds(400))
        // Une lecture : la clé, puis le crédit du compte.
        #expect(server.count == 2)
        #expect(abs((s.of("openrouter").balance?.remaining ?? 0) - 3.21) < 1e-9)
    }

    @Test("erreurs de crédit et en-têtes de limite")
    func errorsAndHeaders() {
        let s = UsageStore(defaults: freshDefaults(), loadCatalog: false)
        s.recordError("groq", LLMError("no credit", status: 402))
        #expect(s.of("groq").level(Date()) == .blocked)
        s.recordHeaders("mistral", ["x-ratelimit-limit-requests": "30", "x-ratelimit-remaining-requests": "3"])
        #expect(s.of("mistral").windows.first?.remaining == 3)
        #expect(s.of("mistral").level(Date()) == .low)
    }
}
