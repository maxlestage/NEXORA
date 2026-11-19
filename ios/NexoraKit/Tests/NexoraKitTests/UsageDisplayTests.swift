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

    @Test func cache() {
        #expect(UsageDisplay.cacheLine(cached: 0, sent: 5000) == nil)
        #expect(UsageDisplay.cacheLine(cached: 100, sent: 0) == nil)
        #expect(UsageDisplay.cacheLine(cached: 32000, sent: 50000)
            == "Relus depuis le cache : 32k tokens (64 % des envoyés)")
        #expect(UsageDisplay.cacheLine(cached: 9, sent: 5)?.contains("100 %") == true)
    }

    @Test func alerte() {
        #expect(UsageDisplay.alertLine([]) == nil)
        #expect(UsageDisplay.alertLine([("OpenAI", .ok), ("Groq", .unknown)]) == nil)
        #expect(UsageDisplay.alertLine([("OpenAI", .blocked), ("Groq", .ok)]) == "OpenAI épuisé")
        #expect(UsageDisplay.alertLine([("A", .blocked), ("B", .blocked)]) == "A, B épuisés")
        #expect(UsageDisplay.alertLine([("Mistral", .low), ("Groq", .low)]) == "À surveiller : Mistral, Groq")
        #expect(UsageDisplay.alertLine([("Groq", .low), ("OpenAI", .blocked)])
            == "OpenAI épuisé · à surveiller : Groq")
        #expect(UsageDisplay.rowsFooter.count < 110)
    }

    @Test func voiceOver() {
        #expect(UsageDisplay.rowAccessibility(name: "OpenAI", summary: "solde 4 $", month: 0)
            == "OpenAI, solde 4 $, aucune dépense ce mois")
        #expect(UsageDisplay.rowAccessibility(name: "OpenAI", summary: "ok", month: 0.5)
            == "OpenAI, ok, ≈ 0,500 $ ce mois")
    }

    @Test func depenseDuMoisEnUneLigne() {
        #expect(UsageDisplay.monthLine(0) == "aucune dépense ce mois")
        #expect(UsageDisplay.monthLine(0.5) == "≈ 0,500 $ ce mois")
    }
}

@Suite("Fiche d'un fournisseur")
struct QuotaDisplayTests {
    @Test func avisApresChangement() {
        #expect(QuotaDisplay.toast(.prepaid(18.4)) == "Solde enregistré : 18,4 $")
        #expect(QuotaDisplay.toast(.prepaid(nil)) == "Solde retiré")
        #expect(QuotaDisplay.toast(.budget(20)) == "Crédit mensuel : 20,0 $")
        #expect(QuotaDisplay.toast(.budget(nil)) == "Crédit mensuel retiré")
        #expect(QuotaDisplay.toast(.reset) == "Compteurs remis à zéro")
    }

    @Test func textesCourts() {
        let sans = QuotaDisplay.prepaidHint("Mistral", hasPrepaid: false)
        let avec = QuotaDisplay.prepaidHint("Mistral", hasPrepaid: true)
        #expect(sans.contains("Mistral") && sans.count < 110)
        #expect(avec.count < 100 && avec != sans)
        let note = QuotaDisplay.estimateNote("OpenAI", pricesDate: "1er novembre 2026")
        #expect(note.contains("OpenAI") && note.contains("1er novembre 2026") && note.count < 100)
    }

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
