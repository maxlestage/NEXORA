import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Les prix publics des modèles, en dollars par million de tokens, pour estimer ce
/// que coûte une conversation et suivre le crédit mensuel d'une offre.
/// (Porté de `data/model_prices.dart`.)
///
/// Ollama Cloud : https://ollama.com/pricing, relevé le 8 novembre 2026 (tarif de
/// journée ; hors heures de pointe, 12 h–18 h UTC en semaine, certains modèles
/// coûtent moitié moins).
///
/// Anthropic : tarifs publics de l'API Claude (cache 0,20 $ pour Opus/Sonnet 5.5).
public enum ModelPrices {
    public static let pricesDate = "8 novembre 2026"

    /// Les prix relevés à la main (prioritaires sur ceux du catalogue).
    public static let fixed: [String: [String: ModelPrice]] = [
        "anthropic": [
            "claude-fable-5-1": ModelPrice(input: 10, output: 50, cachedInput: 0.25),
            "claude-fable-5": ModelPrice(input: 10, output: 50),
            "claude-opus-5-5": ModelPrice(input: 4, output: 20, cachedInput: 0.20),
            "claude-opus-5": ModelPrice(input: 5, output: 25),
            "claude-opus-4-8": ModelPrice(input: 5, output: 25),
            "claude-opus-4-7": ModelPrice(input: 5, output: 25),
            "claude-opus-4-6": ModelPrice(input: 5, output: 25),
            "claude-sonnet-5-5": ModelPrice(input: 2, output: 10, cachedInput: 0.20),
            "claude-sonnet-5": ModelPrice(input: 2, output: 10),
            "claude-sonnet-4-6": ModelPrice(input: 3, output: 15),
            "claude-haiku-5-5": ModelPrice(input: 0.10, output: 0.50),
            "claude-haiku-4-5": ModelPrice(input: 1, output: 5),
        ],
        "ollama-cloud": [
            "beam": ModelPrice(input: 0.125, output: 0.40, cachedInput: 0.015),
            "clef": ModelPrice(input: 0.24, output: 0),
            "deepseek-v4.1-flash": ModelPrice(input: 0.30, output: 1.20, cachedInput: 0.006),
            "deepseek-v4-pro": ModelPrice(input: 1.32, output: 3.96, cachedInput: 0.044),
            "gemma4": ModelPrice(input: 0.14, output: 0.40, cachedInput: 0.05),
            "glm-5.3": ModelPrice(input: 1.40, output: 4.40, cachedInput: 0.26),
            "glm-5.3-flash": ModelPrice(input: 0.15, output: 0.50, cachedInput: 0.03),
            "glm-5.2": ModelPrice(input: 1.40, output: 4.40, cachedInput: 0.26),
            "gpt-oss:120b": ModelPrice(input: 0.15, output: 0.60, cachedInput: 0.014),
            "gpt-oss:20b": ModelPrice(input: 0.07, output: 0.30, cachedInput: 0.035),
            "kimi-k3.1-pro": ModelPrice(input: 2.00, output: 10.00, cachedInput: 0.20),
            "kimi-k3": ModelPrice(input: 3.00, output: 15.00, cachedInput: 0.30),
            "kimi-k2.7-code": ModelPrice(input: 0.95, output: 4.00, cachedInput: 0.19),
            "kimi-k2.6": ModelPrice(input: 0.95, output: 4.00, cachedInput: 0.16),
            "mimo-v2.6-flash": ModelPrice(input: 0.14, output: 0.28, cachedInput: 0.0028),
            "mimo-v2.6-pro": ModelPrice(input: 0.435, output: 0.87, cachedInput: 0.0036),
            "minimax-m3.1-flash": ModelPrice(input: 0.15, output: 0.60, cachedInput: 0.015),
            "minimax-m3": ModelPrice(input: 0.60, output: 2.40, cachedInput: 0.12),
            "minimax-m2.7": ModelPrice(input: 0.30, output: 1.20, cachedInput: 0.06),
            "mistral-large-4": ModelPrice(input: 0.70, output: 2.10, cachedInput: 0.07),
            "mistral-large-3": ModelPrice(input: 0.50, output: 1.50),
            "muse-spark-open": ModelPrice(input: 1.25, output: 4.25, cachedInput: 0.15),
            "nemotron-3-nano": ModelPrice(input: 0.06, output: 0.24),
            "nemotron-3-super": ModelPrice(input: 0.015, output: 0.60, cachedInput: 0.015),
            "nemotron-3-ultra": ModelPrice(input: 0.10, output: 3.00, cachedInput: 0.10),
        ],
    ]

    /// Les offres mensuelles connues, pour régler le crédit en un geste.
    public static let monthlyPlans: [String: [(name: String, amount: Double)]] = [
        "ollama-cloud": [("Pro", 60), ("Max", 300), ("Team", 1000)],
        "openrouter": [],
    ]

    // MARK: - Prix en direct

    /// Le catalogue des derniers modèles, relu sur le site toutes les 6 heures
    /// (même fichier que `models.json`, livré avec l'app).
    public static let catalogURL = URL(string: "https://maxlestage.github.io/NEXORA/models.json")!

    /// Combien de temps une lecture du catalogue reste fraîche.
    public static let catalogMaxAge: TimeInterval = 6 * 3600

    private static let liveStore = Locked<[String: [String: ModelPrice]]>(Catalog.prices)

    /// Les prix du catalogue des derniers modèles (internet) : ceux livrés avec
    /// l'app, remplacés par la dernière version lue sur le site.
    public static var live: [String: [String: ModelPrice]] { liveStore.get() }

    public static func setLive(_ prices: [String: [String: ModelPrice]]) { liveStore.set(prices) }

    /// La date (`updated`) du catalogue livré avec l'app.
    public static let bundledUpdated: String = {
        guard let url = Bundle.module.url(forResource: "models", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return "" }
        return parseCatalog(data)?.updated ?? ""
    }()

    /// Le prix d'un modèle : nom exact (`gpt-oss:120b`), sinon sans l'étiquette
    /// (`deepseek-v4-pro:0813` → `deepseek-v4-pro`) ; les prix relevés à la main
    /// d'abord, puis ceux du catalogue.
    public static func price(provider: String, model: String) -> ModelPrice? {
        var m = model.lowercased()
        if m.hasSuffix("-cloud") { m = String(m.dropLast(6)) }
        let bare = String(m.split(separator: ":", omittingEmptySubsequences: false).first ?? "")
        for table in [fixed[provider], live[provider]] {
            guard let table else { continue }
            if let p = table[m] ?? table[bare] { return p }
        }
        return nil
    }

    /// Lit un catalogue `models.json` : sa date et les prix de chaque modèle.
    public static func parseCatalog(_ data: Data) -> (updated: String, prices: [String: [String: ModelPrice]])? {
        guard let j = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        let providers = j["providers"] as? [String: Any] ?? [:]
        var out: [String: [String: ModelPrice]] = [:]
        for (provider, list) in providers {
            guard let list = list as? [Any] else { return nil }
            var table: [String: ModelPrice] = [:]
            for case let m as [String: Any] in list {
                guard let id = m["id"] as? String,
                      let input = JSONValue.double(m["in"]),
                      let output = JSONValue.double(m["out"]) else { continue }
                table[id.lowercased()] = ModelPrice(input: input, output: output)
            }
            out[provider] = table
        }
        return (j["updated"] as? String ?? "", out)
    }

    /// Adopte un catalogue enregistré s'il est au moins aussi récent que celui
    /// livré avec l'app. Rend vrai s'il a été adopté.
    @discardableResult
    public static func adoptCached(_ data: Data?) -> Bool {
        guard let data, let c = parseCatalog(data), !c.prices.isEmpty,
              c.updated.compare(bundledUpdated) != .orderedAscending else { return false }
        setLive(c.prices)
        return true
    }

    /// Relit le catalogue sur le site. Rend le fichier brut (à enregistrer) s'il est
    /// valide, et adopte ses prix.
    public static func fetchCatalog(transport: HTTPTransport = URLSessionTransport()) async -> Data? {
        var r = URLRequest(url: catalogURL)
        r.timeoutInterval = 20
        guard let res = try? await transport.data(r), res.0.status == 200,
              let c = parseCatalog(res.1), !c.prices.isEmpty else { return nil }
        setLive(c.prices)
        return res.1
    }
}
