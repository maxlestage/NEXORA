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
