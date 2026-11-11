import Foundation

/// Les catalogues livrés avec l'app : fournisseurs, agents intégrés et prix des
/// modèles. Les fichiers JSON sont générés depuis l'app Flutter (mêmes données).
public enum Catalog {
    /// Tous les fournisseurs connus de NEXORA.
    public static let providers: [ProviderDef] = load("providers", as: [ProviderDef].self) ?? []

    /// Les agents fournis avec NEXORA.
    public static let builtinAgents: [Agent] = (load("agents", as: [Agent].self) ?? []).map {
        var a = $0
        a.builtin = true
        a.source = "builtin"
        return a
    }

    /// Les prix connus des modèles, par fournisseur (dollars par million de tokens).
    public static let prices: [String: [String: ModelPrice]] = {
        guard let file = load("models", as: ModelsFile.self) else { return [:] }
        var out: [String: [String: ModelPrice]] = [:]
        for (provider, models) in file.providers {
            var table: [String: ModelPrice] = [:]
            for m in models {
                guard let input = m.in, let output = m.out else { continue }
                table[m.id.lowercased()] = ModelPrice(input: input, output: output)
            }
            out[provider] = table
        }
        return out
    }()

    /// Les fiches des modèles (nom, contexte, raisonnement), pour l'affichage.
    public static let models: [String: [ModelCard]] = load("models", as: ModelsFile.self)?.providers ?? [:]

    /// Le prix d'un modèle s'il est connu.
    public static func price(provider: String, model: String) -> ModelPrice? {
        var m = model.lowercased()
        if m.hasSuffix("-cloud") { m = String(m.dropLast(6)) }
        guard let table = prices[provider] else { return nil }
        return table[m] ?? table[String(m.split(separator: ":").first ?? "")]
    }

    static func load<T: Decodable>(_ name: String, as: T.Type) -> T? {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    struct ModelsFile: Decodable {
        let providers: [String: [ModelCard]]
    }
}

/// Une fiche de modèle du catalogue (`models.json`).
public struct ModelCard: Decodable, Sendable, Hashable {
    public let id: String
    public let name: String?
    public let context: Int?
    public let `in`: Double?
    public let out: Double?
    public let reasoning: Bool?
    public let tools: Bool?
}

/// Le prix d'un modèle, en dollars par million de tokens.
public struct ModelPrice: Sendable, Hashable {
    public let input: Double
    public let output: Double

    public init(input: Double, output: Double) {
        self.input = input
        self.output = output
    }

    public func cost(_ inputTokens: Int, _ outputTokens: Int) -> Double {
        (Double(inputTokens) * input + Double(outputTokens) * output) / 1e6
    }

    public var label: String { "\(Self.dollars(input)) → \(Self.dollars(output)) / M tokens" }

    static func dollars(_ v: Double) -> String {
        let s = String(format: v < 0.1 ? "%.3f" : "%.2f", v)
        return s.replacingOccurrences(of: ".", with: ",") + " $"
    }
}
