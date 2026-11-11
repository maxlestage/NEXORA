import Foundation
import Testing
@testable import NexoraKit

/// La réponse réelle de Google Gemini quand le quota est épuisé (une liste JSON).
let geminiQuota = #"""
[{
  "error": {
    "code": 429,
    "message": "You exceeded your current quota, please check your plan and billing details.",
    "status": "RESOURCE_EXHAUSTED"
  }
}]
"""#

@Suite("Stabilité : quota épuisé, erreurs lisibles, bascule de modèle")
struct StabilityTests {
    @Test("une erreur en liste JSON (Gemini) est lue, pas affichée brute")
    func arrayError() {
        #expect(errorFromBody(geminiQuota) == "You exceeded your current quota, please check your plan and billing details.")
    }

    @Test("quota épuisé : pas un simple « réessayer plus tard »")
    func quotaKinds() {
        let quota = LLMError(errorFromBody(geminiQuota), status: 429)
        #expect(quota.quotaExhausted && !quota.retryable && quota.providerWide)
        let rate = LLMError("Rate limit reached for requests per minute", status: 429)
        #expect(!rate.quotaExhausted && rate.retryable && !rate.providerWide)
        #expect(LLMError("Payment required", status: 402).quotaExhausted)
        #expect(LLMError("Invalid API Key", status: 401).providerWide)
        #expect(!LLMError("Bad gateway", status: 502).providerWide)
    }

    @Test("le client ne réessaie pas un quota épuisé")
    func noRetryOnQuota() async {
        let t = FakeTransport([
            .init(status: 429, headers: ["content-type": "application/json"], body: geminiQuota),
            .init(body: sse(["jamais lu"])),
        ])
        let gemini = Catalog.providers.first { $0.id == "gemini" }!
        do {
            _ = try await collect(LLMClient(transport: t, retryDelay: { _, _ in .zero }).stream(provider: gemini, apiKey: "k", model: "g", messages: [LLMMessage("user", "x")]))
            Issue.record("une erreur était attendue")
        } catch let e as LLMError {
            #expect(e.quotaExhausted)
            #expect(e.message.hasPrefix("You exceeded your current quota"))
        } catch {
            Issue.record("erreur inattendue : \(error)")
        }
        #expect(t.count == 1)
    }

    @Test("une simple limite par minute est encore réessayée")
    func retryOnRate() async throws {
        let t = FakeTransport([
            .init(status: 429, headers: ["retry-after": "0"], body: #"{"error":{"message":"Rate limit reached, slow down"}}"#),
            .init(body: sse(["ok"])),
        ])
        let groq = Catalog.providers.first { $0.id == "groq" }!
        let (text, _) = try await collect(LLMClient(transport: t, retryDelay: { _, _ in .zero }).stream(provider: groq, apiKey: "k", model: "m", messages: [LLMMessage("user", "x")]))
        #expect(text == "ok")
        #expect(t.count == 2)
    }

    @Test("repli : un fournisseur épuisé est sauté en entier, ses autres modèles aussi")
    func skipWholeProvider() {
        let providers = Catalog.providers
        let candidates = [ModelRef("gemini", "a"), ModelRef("gemini", "b"), ModelRef("pollinations", "openai")]
        let key: (String) -> String? = { $0 == "gemini" ? "k" : nil }
        let picked = SessionFallback.pick(candidates, tried: ["gemini::a", "gemini::*"], provider: { id in providers.first { $0.id == id } }, key: key)
        #expect(picked?.0.id == "pollinations")
        let next = SessionFallback.pick(candidates, tried: ["gemini::a"], provider: { id in providers.first { $0.id == id } }, key: key)
        #expect(next?.2 == "b")
    }

    @Test("l'agent passe tout de suite à un autre fournisseur sur un quota épuisé")
    @MainActor
    func agentSwitchesOnQuota() async {
        let llm = ScriptLLM()
        let hosts = Locked<[String]>([])
        llm.dynamic = { _, _, host in
            hosts.update { $0.append(host) }
            return host.contains("groq")
                ? .error(429, geminiQuota)
                : .text(NexoraKitTests.act(["tool": "finish", "args": ["summary": "Fini ailleurs"]]))
        }
        let run = makeRun(llm, hub: Routes { _ in (200, #"{"tree":[]}"#) }, task: "Dis bonjour", checks: false)
        let polli = Catalog.providers.first { $0.id == "pollinations" }!
        var seen: [Set<String>] = []
        run.fallback = { _, tried in
            seen.append(tried)
            return tried.contains("pollinations::openai") ? nil : (polli, nil, "openai")
        }
        await run.run()
        #expect(run.summary == "Fini ailleurs")
        // Une seule requête chez le fournisseur épuisé : ni nouvel essai, ni autre modèle de chez lui.
        #expect(hosts.get().filter { $0.contains("groq") }.count == 1)
        #expect(seen.first?.contains("groq::*") == true)
        #expect(run.steps.contains { $0.text.contains("limite ou crédit épuisé") })
        #expect(!run.steps.contains { $0.text.contains("Nouvel essai") })
        #expect(!run.steps.contains { $0.text.contains("\"error\"") })
    }

    @Test("limite déjà connue : la session commence avec un autre modèle")
    @MainActor
    func proactiveSwitch() async {
        let llm = ScriptLLM()
        let hosts = Locked<[String]>([])
        llm.dynamic = { _, _, host in
            hosts.update { $0.append(host) }
            return host.contains("groq") ? .error(500, "ne doit pas être appelé") : .text(NexoraKitTests.act(["tool": "finish", "args": ["summary": "ok"]]))
        }
        let run = makeRun(llm, hub: Routes { _ in (200, #"{"tree":[]}"#) }, task: "Dis bonjour", checks: false)
        let polli = Catalog.providers.first { $0.id == "pollinations" }!
        run.fallback = { _, tried in tried.contains("pollinations::openai") ? nil : (polli, nil, "openai") }
        run.isBlocked = { $0 == "groq" }
        await run.run()
        #expect(run.summary == "ok")
        #expect(!hosts.get().contains { $0.contains("groq") })
        #expect(run.provider.id == "pollinations")
    }

    @Test("témoin : un quota épuisé bloque le fournisseur, une limite par minute non")
    func usageLevel() {
        var book = UsageBook()
        _ = book.recordError("gemini", LLMError(errorFromBody(geminiQuota), status: 429))
        #expect(book.of("gemini").level(Date()) == .blocked)
        _ = book.recordError("groq", LLMError("Rate limit reached", status: 429))
        #expect(book.of("groq").level(Date()) == .low)
    }
}

@Suite("L'argent dépensé, visible et à jour")
struct SpendTests {
    @Test("une session compte ses tokens et ses dollars, et les garde")
    @MainActor
    func sessionSpend() async throws {
        let llm = ScriptLLM([NexoraKitTests.act(["tool": "finish", "args": ["summary": "ok"]])])
        let run = makeRun(llm, hub: Routes { _ in (200, #"{"tree":[]}"#) }, task: "Dis bonjour", checks: false)
        let anthropic = try #require(Catalog.providers.first { $0.id == "anthropic" })
        run.account(anthropic, "claude-opus-5-5", TokenUsage(1_000_000, 100_000))
        let price = try #require(Catalog.price(provider: "anthropic", model: "claude-opus-5-5"))
        #expect(abs(run.spentCost - price.cost(1_000_000, 100_000)) < 1e-9)
        #expect(run.spentIn == 1_000_000 && run.spentOut == 100_000 && !run.costPartial)
        await run.run()
        #expect(run.spentIn > 1_000_000) // la réponse du modèle est comptée aussi
        let restored = try #require(AgentRun.restore(
            run.toJSON(), llm: LLMClient(transport: llm), github: GitHubAPI(token: nil), provider: run.provider, apiKey: nil
        ))
        #expect(restored.spentIn == run.spentIn && abs(restored.spentCost - run.spentCost) < 1e-9)
    }

    @Test("le témoin montre l'argent du jour avant la fenêtre de limite")
    func badgeShowsMoney() {
        let p = Catalog.providers.first { $0.id == "anthropic" }!
        var u = ProviderUsage("anthropic")
        u.windows = [RateWindow(kind: "tokens", window: "min", limit: 12_000_000, remaining: 12_000_000)]
        let before = UsageText.summary(p, u)
        #expect(!before.contains("$"))
        u.costToday = 0.42
        u.costMonth = 3.1
        let after = UsageText.summary(p, u)
        #expect(after.contains("0,42") && after.contains("ce mois"))
    }

    @Test("texte de consommation d'une session")
    func sessionText() {
        #expect(UsageText.session(tokensIn: 1_200_000, tokensOut: 30_000, cost: 3.4, partial: false).contains("≈ 3,40 $"))
        #expect(UsageText.session(tokensIn: 10, tokensOut: 5, cost: 0, partial: false).hasSuffix("gratuit"))
        #expect(UsageText.session(tokensIn: 10, tokensOut: 5, cost: 0, partial: true).hasSuffix("prix inconnu"))
    }
}
