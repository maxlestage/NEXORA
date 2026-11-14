import Testing
@testable import NexoraKit

@Suite("Crédits et consommation")
struct UsageDisplayTests {
    @Test func aujourdhui() {
        #expect(UsageDisplay.todayLine(cost: 0, requests: 0, tokens: 0) == "Aucune requête aujourd'hui")
        #expect(UsageDisplay.todayLine(cost: 0.0123, requests: 1, tokens: 1500)
            == "Aujourd'hui : ≈ 0,012 $ · 1 requête · 1,5k tokens")
        #expect(UsageDisplay.todayLine(cost: 2, requests: 12, tokens: 42000)
            == "Aujourd'hui : ≈ 2,00 $ · 12 requêtes · 42k tokens")
        #expect(!UsageDisplay.todayLine(cost: 1, requests: 3, tokens: 10).contains("(s)"))
    }

    @Test func reglages() {
        #expect(UsageDisplay.settingsDetail(month: 0, summaries: []) == "Le crédit de vos fournisseurs apparaîtra ici")
        let s = [(name: "OpenAI", summary: "solde 4 $"), (name: "Mistral", summary: "ok"), (name: "Groq", summary: "ok")]
        #expect(UsageDisplay.settingsDetail(month: 1.5, summaries: s)
            == "≈ 1,50 $ ce mois · OpenAI : solde 4 $ · Mistral : ok")
    }

    @Test func voiceOver() {
        #expect(UsageDisplay.rowAccessibility(name: "OpenAI", summary: "solde 4 $", month: 0)
            == "OpenAI, solde 4 $, aucune dépense ce mois")
        #expect(UsageDisplay.rowAccessibility(name: "OpenAI", summary: "ok", month: 0.5)
            == "OpenAI, ok, ≈ 0,500 $ ce mois")
    }
}

@Suite("Fiche d'un fournisseur")
struct QuotaDisplayTests {
    @Test func rienCompte() {
        let u = ProviderUsage("openai")
        #expect(QuotaDisplay.counted(u).isEmpty)
        #expect(QuotaDisplay.countedEmpty.contains("premier message"))
    }

    @Test func lignesCourtes() {
        var u = ProviderUsage("anthropic")
        u.requestsToday = 1
        u.tokensInToday = 10000
        u.tokensOutToday = 1500
        u.tokensCachedToday = 6300
        u.requestsTotal = 45
        u.tokensTotal = 1_200_000
        #expect(QuotaDisplay.counted(u) == [
            .init("Aujourd'hui", "1 requête · 12k tokens"),
            .init("Envoyés · reçus", "10k · 1,5k"),
            .init("Relus depuis le cache", "6,3k · 63 % des envoyés"),
            .init("Depuis le début", "45 requêtes · 1,2M tokens"),
        ])
        u.requestsToday = 0
        u.tokensInToday = 0
        u.tokensOutToday = 0
        u.tokensCachedToday = 0
        #expect(QuotaDisplay.counted(u) == [
            .init("Aujourd'hui", "Aucune requête"),
            .init("Depuis le début", "45 requêtes · 1,2M tokens"),
        ])
        #expect(!QuotaDisplay.counted(u).contains { $0.value.contains("(") })
    }

    @Test func montantSaisi() {
        #expect(QuotaDisplay.amount("  ") == .clear)
        #expect(QuotaDisplay.amount("18,40") == .value(18.4))
        #expect(QuotaDisplay.amount("18.40 $") == .value(18.4))
        #expect(QuotaDisplay.amount("abc") == .invalid)
        #expect(QuotaDisplay.amount("0") == .invalid)
        #expect(QuotaDisplay.amount("-5") == .invalid)
    }

    @Test func remiseAZero() {
        #expect(QuotaDisplay.resetMessage("Groq").contains("Groq"))
        #expect(QuotaDisplay.resetMessage("Groq").contains("clé"))
    }
}
