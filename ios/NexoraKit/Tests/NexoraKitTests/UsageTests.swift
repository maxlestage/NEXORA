import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import NexoraKit

/// Une date locale (comme `DateTime(2026, 11, 8, 12)` en Dart).
private func day(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0) -> Date {
    Calendar.current.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
}

private func provider(_ id: String) -> ProviderDef { Catalog.providers.first { $0.id == id }! }

@Suite("Usage : limites de débit")
struct RateWindowTests {
    @Test("en-têtes OpenAI / Groq")
    func openAI() {
        let w = RateWindow.fromHeaders([
            "x-ratelimit-limit-requests": "30",
            "x-ratelimit-remaining-requests": "3",
            "x-ratelimit-reset-requests": "1m2s",
            "x-ratelimit-limit-tokens": "6000",
            "x-ratelimit-remaining-tokens": "5800",
            "content-type": "text/event-stream",
        ])
        #expect(w.count == 2)
        // La plus contraignante d'abord.
        #expect(w[0].kind == "requêtes")
        #expect(w[0].remaining == 3)
        #expect(abs((w[0].ratio ?? 0) - 0.1) < 0.001)
        #expect(w[0].reset == "1m2s")
        #expect(w[0].label == "3 / 30 req")
        #expect(w[1].label == "5,8k / 6,0k tokens")
    }

    @Test("en-têtes Anthropic et Cerebras (par jour)")
    func anthropicAndCerebras() {
        let a = RateWindow.fromHeaders([
            "anthropic-ratelimit-requests-limit": "50",
            "anthropic-ratelimit-requests-remaining": "49",
            "anthropic-ratelimit-tokens-limit": "40000",
            "anthropic-ratelimit-tokens-remaining": "39000",
        ])
        #expect(a.count == 2)
        let c = RateWindow.fromHeaders([
            "x-ratelimit-limit-requests-day": "14400",
            "x-ratelimit-remaining-requests-day": "14000",
        ])
        #expect(c.count == 1)
        #expect(c[0].window == "jour")
        #expect(c[0].label == "14k / 14k req/jour")
    }

    @Test("sans limite : rien")
    func none() {
        #expect(RateWindow.fromHeaders(["content-type": "application/json", "x-ratelimit-reset": "3s"]).isEmpty)
        #expect(RateWindow(kind: "tokens", window: "min", remaining: 1200).label == "1,2k tokens/min restants")
    }

    @Test("nombres lisibles")
    func formats() {
        #expect(UsageFormat.compact(999) == "999")
        #expect(UsageFormat.compact(1500) == "1,5k")
        #expect(UsageFormat.compact(12345) == "12k")
        #expect(UsageFormat.compact(2_500_000) == "2,5M")
        #expect(UsageFormat.dollars(3.2) == "3,20 $")
        #expect(UsageFormat.dollars(12.34) == "12,3 $")
        #expect(UsageFormat.costLabel(0) == "0 $")
        #expect(UsageFormat.costLabel(0.00001) == "< 0,0001 $")
        #expect(UsageFormat.costLabel(0.00042) == "0,0004 $")
        #expect(UsageFormat.costLabel(0.0123) == "0,012 $")
        #expect(UsageFormat.costLabel(1.5) == "1,50 $")
        #expect(Balance(currency: "EUR").money(3) == "3,00€")
        #expect(Balance(currency: "GBP").money(30) == "30,0 GBP")
    }
}

@Suite("Usage : crédit")
struct QuotaTests {
    @Test("OpenRouter : crédit acheté")
    func openRouterCredits() {
        let b = QuotaService.parseOpenRouter(
            ["data": ["usage": 1.5, "limit": NSNull(), "is_free_tier": false]],
            ["data": ["total_credits": 10, "total_usage": 2.5]]
        )
        #expect(b.remaining == 7.5)
        #expect(b.ratio == 0.75)
        #expect(b.label == "7,50 $ restants")
        #expect(b.freeTier == false)
    }

    @Test("OpenRouter : offre gratuite sans plafond")
    func openRouterFree() {
        let b = QuotaService.parseOpenRouter(["data": ["usage": 0, "limit": NSNull(), "is_free_tier": true]], nil)
        #expect(b.remaining == nil)
        #expect(b.freeTier == true)
        #expect(b.note?.hasPrefix("Offre gratuite") == true)
        #expect(UsageText.summary(provider("openrouter"), {
            var u = ProviderUsage("openrouter")
            u.balance = b
            return u
        }()) == "Offre gratuite")
    }

    @Test("OpenRouter : plafond de la clé")
    func openRouterLimit() {
        let b = QuotaService.parseOpenRouter(["data": ["usage": 2, "limit": 5, "is_free_tier": false]], nil)
        #expect(b.remaining == 3)
        #expect(b.total == 5)
        #expect(b.used == 2)
    }

    @Test("DeepSeek : solde")
    func deepSeek() throws {
        let b = try #require(QuotaService.parseDeepSeek([
            "is_available": true,
            "balance_infos": [
                ["currency": "CNY", "total_balance": "30.00"],
                ["currency": "USD", "total_balance": "4.20"],
            ],
        ]))
        #expect(b.remaining == 4.2)
        #expect(b.currency == "USD")
        #expect(b.note == nil)
        #expect(QuotaService.parseDeepSeek(["balance_infos": [Any]()]) == nil)
    }

    @Test("lecture en direct : OpenRouter (clé puis crédit)")
    func fetchOpenRouter() async throws {
        let t = FakeTransport([
            .init(headers: [:], body: #"{"data":{"usage":1.5,"limit":null,"is_free_tier":false}}"#),
            .init(headers: [:], body: #"{"data":{"total_credits":10,"total_usage":2.5}}"#),
        ])
        let b = try await QuotaService(transport: t).fetchBalance(provider("openrouter"), key: "k")
        #expect(b?.remaining == 7.5)
        #expect(t.requests.map { $0.url?.absoluteString } == ["https://openrouter.ai/api/v1/key", "https://openrouter.ai/api/v1/credits"])
        #expect(t.requests[0].value(forHTTPHeaderField: "authorization") == "Bearer k")
    }

    @Test("lecture en direct : clé refusée, fournisseur sans solde, sans clé")
    func fetchErrors() async throws {
        let t = FakeTransport([.init(status: 401, headers: [:], body: "{}")])
        await #expect(throws: QuotaError.self) {
            _ = try await QuotaService(transport: t).fetchBalance(provider("deepseek"), key: "k")
        }
        let none = FakeTransport([])
        #expect(try await QuotaService(transport: none).fetchBalance(provider("groq"), key: "k") == nil)
        #expect(try await QuotaService(transport: none).fetchBalance(provider("openrouter"), key: "") == nil)
        #expect(none.count == 0)
    }

    @Test("le solde lu, ou l'erreur de clé, va dans le carnet")
    func applyRefresh() {
        var book = UsageBook()
        let now = day(2026, 11, 8, 12)
        book.applyRefresh("openrouter", .success(Balance(remaining: 3.21, total: 10)), now: now)
        #expect(book.of("openrouter", now: now).balance?.remaining == 3.21)
        #expect(book.of("openrouter", now: now).balanceAt == now)
        // Réseau indisponible : on garde la dernière valeur.
        book.applyRefresh("openrouter", .failure(URLError(.notConnectedToInternet)), now: now)
        #expect(book.of("openrouter", now: now).balance?.remaining == 3.21)
        book.applyRefresh("openrouter", .failure(QuotaError("Clé refusée (401)")), now: now)
        #expect(book.of("openrouter", now: now).lastErrorStatus == 401)
        #expect(book.of("openrouter", now: now).level(now) == .blocked)
    }
}

@Suite("Usage : témoin")
struct UsageLevelTests {
    @Test("niveaux, et relus depuis le JSON")
    func levels() throws {
        let now = day(2026, 11, 8, 12)
        var u = ProviderUsage("groq")
        #expect(u.level(now) == .unknown)
        u.windows = [RateWindow(kind: "requêtes", window: "min", limit: 30, remaining: 20)]
        u.windowsAt = now
        #expect(u.level(now) == .ok)
        u.windows = [RateWindow(kind: "requêtes", window: "min", limit: 30, remaining: 2)]
        #expect(u.level(now) == .low)
        u.lastErrorStatus = 402
        u.lastErrorAt = now
        #expect(u.level(now) == .blocked)
        let data = try JSONSerialization.data(withJSONObject: u.toJSON())
        let j = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let again = ProviderUsage.fromJSON("groq", j)
        #expect(again.level(now) == .blocked)
        #expect(again.windows == u.windows)
        // Une erreur de plus de 30 minutes ne bloque plus.
        #expect(u.level(now.addingTimeInterval(31 * 60)) != .blocked)
    }

    @Test("compteurs remis à zéro chaque jour")
    func rollDay() {
        var u = ProviderUsage("x")
        u.rollDay(day(2026, 1, 1))
        u.requestsToday = 5
        u.rollDay(day(2026, 1, 1, 23))
        #expect(u.requestsToday == 5)
        u.rollDay(day(2026, 1, 2))
        #expect(u.requestsToday == 0)
        #expect(u.day == "2026-01-02")
        #expect(u.month == "2026-01")
    }

    @Test("le JSON de l'app Flutter se relit (heures locales sans fuseau)")
    func flutterJSON() {
        let raw = #"{"groq":{"windows":[{"kind":"tokens","window":"min","limit":6000,"remaining":5800,"reset":"2s"}],"windowsAt":"2026-11-08T12:00:00.000","balance":null,"day":"2026-11-08","requestsToday":3,"requestsTotal":10,"tokensTotal":4200,"estimated":true,"costToday":0,"month":"2026-11","costMonth":1.25,"monthlyBudget":60,"prepaidSpent":0,"lastErrorStatus":429,"lastErrorMessage":"Rate limit","lastErrorAt":"2026-11-08T12:00:00.000"}}"#
        let book = UsageBook.fromJSON(Data(raw.utf8))
        let u = book.of("groq", now: day(2026, 11, 8, 12))
        #expect(u.requestsToday == 3)
        #expect(u.requestsTotal == 10)
        #expect(u.costMonth == 1.25)
        #expect(u.monthlyBudget == 60)
        #expect(u.windows.first?.remaining == 5800)
        #expect(u.windowsAt == day(2026, 11, 8, 12))
        #expect(u.lastErrorStatus == 429)
        #expect(u.estimated)
        // Et ce que l'app Swift écrit se relit à l'identique.
        let again = UsageBook.fromJSON(book.toJSON())
        #expect(again.of("groq", now: day(2026, 11, 8, 12)) == u)
    }

    @Test("résumés du témoin")
    func summaries() {
        let now = day(2026, 11, 8, 12)
        let groq = provider("groq")
        var u = ProviderUsage("groq")
        u.rollDay(now)
        #expect(UsageText.summary(groq, u, now: now) == "Pas encore utilisé")
        #expect(UsageText.summary(provider("pollinations"), u, now: now) == "Gratuit")
        #expect(UsageText.summary(provider("ollama"), u, now: now) == "Local · illimité")
        u.requestsToday = 2
        u.tokensInToday = 1000
        u.tokensOutToday = 500
        #expect(UsageText.summary(groq, u, now: now) == "2 req · 1,5k tokens auj.")
        u.windows = [RateWindow(kind: "requêtes", window: "min", limit: 30, remaining: 28)]
        #expect(UsageText.summary(groq, u, now: now) == "28 / 30 req/min")
        u.prepaid = 10
        u.prepaidSpent = 1.5
        #expect(UsageText.summary(groq, u, now: now) == "≈ 8,50 $ restants")
        u.lastErrorStatus = 429
        u.lastErrorAt = now
        #expect(UsageText.summary(groq, u, now: now) == "Limite atteinte")
        #expect(UsageText.ago(now.addingTimeInterval(-90 * 60), now: now) == "il y a 1 h")
        #expect(UsageText.ago(now.addingTimeInterval(-5 * 60), now: now) == "il y a 5 min")
        #expect(UsageText.windowTitle(RateWindow(kind: "tokens", window: "jour")) == "Tokens par jour")
        #expect(UsageText.conversation(tokens: 0, cost: 0) == "Aucune dépense")
        #expect(UsageText.conversation(tokens: 3400, cost: 0.0123) == "≈ 0,012 $ · 3,4k tokens")
        #expect(UsageText.parseAmount(" 18,40 $") == 18.4)
        #expect(UsageText.parseAmount("abc") == 0)
    }
}

@Suite("Usage : prix et dépenses", .serialized)
struct UsagePriceTests {
    @Test("Ollama Cloud : chaque modèle par défaut a son prix")
    func ollamaCloudDefaults() {
        let cloud = provider("ollama-cloud")
        #expect(cloud.baseUrl == "https://ollama.com")
        #expect(!cloud.local)
        #expect(!cloud.free)
        for m in cloud.defaultModels {
            #expect(ModelPrices.price(provider: "ollama-cloud", model: m) != nil, "\(m)")
        }
    }

    @Test("prix : nom exact, puis sans étiquette")
    func priceLookup() {
        #expect(ModelPrices.price(provider: "ollama-cloud", model: "gpt-oss:120b")?.output == 0.60)
        #expect(ModelPrices.price(provider: "ollama-cloud", model: "gpt-oss:20b")?.output == 0.30)
        #expect(ModelPrices.price(provider: "ollama-cloud", model: "deepseek-v4-pro:0813")?.input == 1.32)
        #expect(ModelPrices.price(provider: "ollama-cloud", model: "clef:27b")?.input == 0.24)
        #expect(ModelPrices.price(provider: "ollama-cloud", model: "kimi-k3-cloud")?.input == 3)
        #expect(ModelPrices.price(provider: "ollama-cloud", model: "inconnu") == nil)
        #expect(ModelPrices.price(provider: "groq", model: "llama") == nil)
        // 1 M tokens envoyés + 1 M reçus avec kimi-k3 : 3 $ + 15 $.
        #expect(ModelPrices.price(provider: "ollama-cloud", model: "kimi-k3")?.cost(1_000_000, 1_000_000) == 18)
        #expect(ModelPrices.price(provider: "anthropic", model: "claude-opus-5-5")?.output == 20)
        #expect(ModelPrices.price(provider: "anthropic", model: "claude-opus-5-5")?.cachedInput == 0.20)
        // Catalog.price passe par la même table.
        #expect(Catalog.price(provider: "ollama-cloud", model: "clef") != nil)
        #expect(ModelPrices.monthlyPlans["ollama-cloud"]?.map(\.amount) == [60, 300, 1000])
    }

    @Test("dépense du mois et crédit de l'offre")
    func monthlyBudget() {
        let now = day(2026, 11, 8)
        var u = ProviderUsage("ollama-cloud")
        u.rollDay(now)
        u.monthlyBudget = 60
        u.costMonth = 15
        #expect(u.budgetRatio == 0.75)
        #expect(u.level(now) == .ok)
        u.costMonth = 55
        #expect(u.level(now) == .low)
        u.costMonth = 61
        #expect(u.level(now) == .blocked)
        // Nouveau mois : la dépense repart de zéro.
        u.rollDay(day(2026, 12, 1))
        #expect(u.costMonth == 0)
    }

    @Test("le solde prépayé baisse à chaque réponse, et se relit")
    func prepaid() throws {
        var book = UsageBook()
        book.setPrepaid("anthropic", 10)
        let cost = book.recordUsage("anthropic", model: "claude-opus-5-5", usage: TokenUsage(100_000, 50_000)) // 0,40 $ + 1 $
        #expect(abs((cost ?? 0) - 1.4) < 1e-9)
        let u = book.of("anthropic")
        #expect(abs((u.prepaidLeft ?? 0) - 8.6) < 1e-9)
        #expect(u.level(Date()) == .ok)
        #expect(u.requestsTotal == 1)
        #expect(!u.estimated)
        let again = UsageBook.fromJSON(book.toJSON())
        #expect(abs((again.of("anthropic").prepaidLeft ?? 0) - 8.6) < 1e-9)
        book.setPrepaid("anthropic", nil)
        #expect(book.of("anthropic").prepaid == nil)
        #expect(book.of("anthropic").prepaidAt == nil)
    }

    @Test("le solde lu baisse tout de suite après une réponse")
    func balanceSpend() throws {
        var book = UsageBook()
        book.update("anthropic") { $0.balance = Balance(remaining: 5, total: 10, used: 5) }
        book.recordUsage("anthropic", model: "claude-sonnet-5-5", usage: TokenUsage(1_000_000, 0))
        let b = try #require(book.of("anthropic").balance)
        #expect(b.remaining! < 5)
        #expect(b.used! > 5)
    }

    @Test("sans décompte officiel : tokens estimés (4 caractères par token)")
    func estimated() {
        var book = UsageBook()
        book.recordUsage("groq", model: "llama", inputChars: 10, outputChars: 4)
        let u = book.of("groq")
        #expect(u.estimated)
        #expect(u.tokensInToday == 3)
        #expect(u.tokensOutToday == 1)
        #expect(u.costMonth == 0)
    }

    @Test("prix en direct : le catalogue relu sur le site")
    func livePrices() async throws {
        let before = ModelPrices.live
        defer { ModelPrices.setLive(before) }
        var providers: [String: Any] = [:]
        for (p, table) in before {
            providers[p] = table.map { ["id": $0.key, "name": $0.key, "in": $0.value.input, "out": $0.value.output] }
        }
        var anthropic = providers["anthropic"] as? [[String: Any]] ?? []
        anthropic.insert(["id": "claude-next", "name": "Claude Next", "in": 3, "out": 15, "release": "2026-11-10"], at: 0)
        providers["anthropic"] = anthropic
        let body = LooseJSON.string(["updated": "2099-01-01T00:00:00Z", "providers": providers])
        let t = FakeTransport([.init(headers: ["content-type": "application/json"], body: body)])
        let data = try #require(await ModelPrices.fetchCatalog(transport: t))
        #expect(t.requests.first?.url == ModelPrices.catalogURL)
        #expect(ModelPrices.price(provider: "anthropic", model: "claude-next")?.output == 15)
        // Les prix relevés à la main restent prioritaires.
        #expect(ModelPrices.price(provider: "anthropic", model: "claude-opus-5-5")?.output == 20)
        // Un catalogue enregistré plus ancien que celui livré n'est pas repris.
        ModelPrices.setLive(before)
        let old = LooseJSON.string(["updated": "2000-01-01", "providers": ["x": [["id": "y", "in": 1, "out": 1]]]])
        #expect(!ModelPrices.adoptCached(Data(old.utf8)))
        #expect(ModelPrices.adoptCached(data))
        #expect(ModelPrices.price(provider: "anthropic", model: "claude-next") != nil)
        // Une réponse invalide ne change rien.
        let bad = FakeTransport([.init(status: 500, headers: [:], body: "oups")])
        #expect(await ModelPrices.fetchCatalog(transport: bad) == nil)
        #expect(!ModelPrices.bundledUpdated.isEmpty)
    }
}

@Suite("Usage : attribution et erreurs")
struct UsageAttributionTests {
    @Test("les dépenses vont au fournisseur qui a répondu, l'erreur à celui qui a échoué")
    func attribution() {
        var book = UsageBook()
        // Groq n'a plus de crédit (402) ; la suite part chez OpenRouter.
        book.recordHeaders("groq", ["x-ratelimit-remaining-requests": "0"])
        let kept = book.recordError("groq", LLMError("no credit", status: 402))
        #expect(kept)
        book.recordUsage("openrouter", model: "openai/gpt-4o-mini", usage: TokenUsage(100, 20))
        #expect(book.of("groq").requestsTotal == 0)
        #expect(book.of("groq").lastErrorStatus == 402)
        #expect(book.of("groq").level(Date()) == .blocked)
        #expect(book.of("openrouter").requestsTotal == 1)
        #expect(book.of("openrouter").lastErrorStatus == nil)
    }

    @Test("seules les erreurs de clé et de quota sont retenues")
    func errors() {
        var book = UsageBook()
        let a = book.recordError("groq", LLMError("overloaded", status: 503))
        let b = book.recordError("groq", LLMError("réseau"))
        let c = book.recordError("groq", CancellationError())
        #expect(!a && !b && !c)
        #expect(book.entries["groq"] == nil)
        let d = book.recordError("groq", LLMError("Rate limit", status: 429))
        #expect(d)
        #expect(book.of("groq").lastErrorMessage == "Rate limit")
        #expect(book.of("groq").level(Date()) == .low)
        // Des limites relues sans compteur à zéro effacent la limite atteinte.
        book.recordHeaders("groq", ["x-ratelimit-limit-requests": "30", "x-ratelimit-remaining-requests": "29"])
        #expect(book.of("groq").lastErrorStatus == nil)
        // Une réponse réussie efface une erreur 401.
        book.recordError("groq", LLMError("Invalid API Key", status: 401))
        book.recordUsage("groq", usage: TokenUsage(1, 1))
        #expect(book.of("groq").lastErrorStatus == nil)
        // Mais pas un refus d'accès au modèle (403).
        book.recordError("groq", LLMError("Forbidden", status: 403))
        book.recordUsage("groq", usage: TokenUsage(1, 1))
        #expect(book.of("groq").lastErrorStatus == 403)
        book.reset("groq")
        #expect(book.entries["groq"] == nil)
    }

    @Test("fournisseurs suivis : ceux avec un solde d'abord, puis par dépense")
    func tracked() {
        var book = UsageBook()
        book.recordUsage("groq", model: "llama", usage: TokenUsage(10, 10))
        book.update("ollama-cloud") { $0.costMonth = 3 }
        book.update("ollama-cloud") { $0.requestsTotal = 1 }
        book.setPrepaid("anthropic", 5)
        let all = Catalog.providers
        let ready: Set<String> = ["mistral"]
        let list = book.tracked(all) { ready.contains($0.id) }.map(\.id)
        #expect(list == ["anthropic", "ollama-cloud", "groq", "mistral"])
    }
}

@Suite("Usage : jauge")
struct GaugeTests {
    @Test("la jauge de crédit n'a aucune ligne de séparation")
    func noSeam() {
        // Tout le long de l'arc (135° → 405°), la couleur change en douceur.
        let samples = (2...268).map { GaugeGeometry.opacity(atDegrees: Double(135 + $0)) * 255 }
        var worst = 0.0
        for k in 1..<samples.count { worst = max(worst, abs(samples[k] - samples[k - 1])) }
        #expect(worst < 8, "saut de \(worst) entre deux degrés")
        // Et il va bien du pâle au vif.
        #expect(samples.last! - samples.first! > 60)
        // Le raccord du dégradé tombe dans le vide du bas, loin des bouts de l'arc.
        #expect(GaugeGeometry.gradientStart == 90)
        #expect(GaugeGeometry.arcStartLocation == 0.125)
        #expect(GaugeGeometry.arcEndLocation == 0.875)
    }
}
