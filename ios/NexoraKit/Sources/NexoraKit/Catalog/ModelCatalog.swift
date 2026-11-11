import Foundation

/// Un modèle du catalogue des derniers modèles (`models.json`).
public struct CatalogModel: Sendable, Hashable {
    public let id: String
    public let name: String
    /// Date de sortie, `2026-09-01`.
    public let release: String
    /// Prix en dollars par million de tokens.
    public let input: Double?
    public let output: Double?
    public let context: Int?
    public let reasoning: Bool

    public init(id: String, name: String? = nil, release: String = "", input: Double? = nil, output: Double? = nil, context: Int? = nil, reasoning: Bool = false) {
        self.id = id
        self.name = name ?? id
        self.release = release
        self.input = input
        self.output = output
        self.context = context
        self.reasoning = reasoning
    }

    public var free: Bool { input == 0 && output == 0 }

    /// Sorti il y a moins de 45 jours.
    public func isNew(_ now: Date = Date()) -> Bool {
        guard let d = ModelCatalog.day(release) else { return false }
        return Int(now.timeIntervalSince(d) / 86400) <= 45
    }

    init?(json j: [String: Any]) {
        guard let id = j["id"] as? String else { return nil }
        self.init(
            id: id,
            name: j["name"] as? String,
            release: j["release"] as? String ?? "",
            input: (j["in"] as? NSNumber)?.doubleValue,
            output: (j["out"] as? NSNumber)?.doubleValue,
            context: (j["context"] as? NSNumber)?.intValue,
            reasoning: j["reasoning"] as? Bool == true
        )
    }
}

/// Le catalogue des derniers modèles, tiré d'internet toutes les 6 heures (models.dev
/// et la liste en direct d'OpenRouter). Livré avec l'app et relu sur le site toutes
/// les 6 heures (`data/model_catalog.dart`).
public struct ModelCatalog: Sendable, Hashable {
    /// L'adresse du catalogue à jour, sur le site de NEXORA.
    public static let url = URL(string: "https://maxlestage.github.io/NEXORA/models.json")!

    /// Le catalogue est relu au plus une fois toutes les 6 heures.
    public static let refreshInterval: TimeInterval = 6 * 3600

    public let updated: String
    public let providers: [String: [CatalogModel]]

    public init(updated: String, providers: [String: [CatalogModel]]) {
        self.updated = updated
        self.providers = providers
    }

    public static let empty = ModelCatalog(updated: "", providers: [:])

    public var isEmpty: Bool { providers.isEmpty }

    /// Le catalogue livré avec l'app.
    public static let bundled: ModelCatalog = {
        guard let url = Bundle.module.url(forResource: "models", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return .empty }
        return (try? parse(data)) ?? .empty
    }()

    public static func parse(_ raw: String) throws -> ModelCatalog { try parse(Data(raw.utf8)) }

    public static func parse(_ data: Data) throws -> ModelCatalog {
        guard let j = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LLMError("Catalogue illisible")
        }
        var out: [String: [CatalogModel]] = [:]
        for (k, v) in j["providers"] as? [String: Any] ?? [:] {
            out[k] = (v as? [[String: Any]] ?? []).compactMap(CatalogModel.init(json:))
        }
        return ModelCatalog(updated: j["updated"] as? String ?? "", providers: out)
    }

    public func find(_ providerId: String, _ model: String) -> CatalogModel? {
        providers[providerId]?.first { $0.id == model }
    }

    /// Les prix du catalogue, par fournisseur (identifiants en minuscules).
    public var prices: [String: [String: ModelPrice]] {
        providers.mapValues { list in
            var table: [String: ModelPrice] = [:]
            for m in list {
                if let i = m.input, let o = m.output { table[m.id.lowercased()] = ModelPrice(input: i, output: o) }
            }
            return table
        }
    }

    /// Le plus récent des deux : celui livré avec l'app ou celui gardé en cache.
    public static func newest(_ a: ModelCatalog, _ cached: ModelCatalog?) -> ModelCatalog {
        guard let cached else { return a }
        return cached.updated.compare(a.updated) != .orderedAscending ? cached : a
    }

    /// Faut-il relire le catalogue sur le site ?
    public static func isStale(lastFetch: Date?, now: Date = Date()) -> Bool {
        guard let lastFetch else { return true }
        return now.timeIntervalSince(lastFetch) >= refreshInterval
    }

    static func day(_ s: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: String(s.prefix(10)))
    }
}

/// « 1M », « 200k ».
public func contextLabel(_ tokens: Int) -> String {
    if tokens >= 1_000_000 {
        let v = Double(tokens) / 1_000_000
        return String(format: tokens % 1_000_000 == 0 ? "%.0f" : "%.1f", v) + "M"
    }
    return "\(Int((Double(tokens) / 1000).rounded()))k"
}

/// Les modèles proposés pour un fournisseur et la façon de les présenter (choix du
/// modèle, panneau « Sélectionner un modèle »), comme dans l'app Flutter.
public enum ModelList {
    /// Les modèles d'un fournisseur, les plus récents d'abord : la liste de votre
    /// compte si elle a été chargée, sinon le catalogue des derniers modèles.
    /// `p.defaultModels` contient aussi les modèles ajoutés à la main.
    public static func models(
        _ p: ProviderDef, live: [ModelInfo]?, catalog: ModelCatalog, now: Date = Date(),
        price: (String) -> ModelPrice? = { _ in nil }
    ) -> [ModelInfo] {
        let cat = catalog.providers[p.id] ?? []
        func info(_ id: String, free: Bool? = nil, detail: String? = nil) -> ModelInfo {
            let c = catalog.find(p.id, id)
            var parts: [String] = []
            if let c, c.isNew(now) { parts.append("🆕 \(c.release)") }
            if let detail, !detail.isEmpty {
                parts.append(detail)
            } else if let pr = price(id) {
                parts.append(pr.label)
            }
            if let ctx = c?.context { parts.append("\(contextLabel(ctx)) ctx") }
            return ModelInfo(id, free: free ?? (p.free || (c?.free ?? false)), detail: parts.isEmpty ? nil : parts.joined(separator: " · "))
        }
        if let live, !live.isEmpty {
            var rank: [String: Int] = [:]
            for (i, c) in cat.enumerated() where rank[c.id] == nil { rank[c.id] = i }
            let known = live.filter { rank[$0.id] != nil }.sorted { rank[$0.id]! < rank[$1.id]! }
            let unknown = live.filter { rank[$0.id] == nil }
            let extra = p.defaultModels.filter { m in !live.contains { $0.id == m } }
            return extra.map { info($0) } + (known + unknown).map { info($0.id, free: $0.free || p.free, detail: $0.detail) }
        }
        var seen = Set<String>()
        var out: [ModelInfo] = []
        for c in cat where seen.insert(c.id).inserted { out.append(info(c.id)) }
        for m in p.defaultModels where seen.insert(m).inserted { out.append(info(m)) }
        return out
    }

    /// Le nom lisible d'un modèle : « Opus 5.5 » plutôt que `claude-opus-5-5`.
    public static func displayName(_ r: ModelRef, catalog: ModelCatalog) -> String {
        var name = catalog.find(r.providerId, r.model)?.name ?? r.model
        if r.providerId == "anthropic", let range = name.range(of: "Claude ") { name.replaceSubrange(range, with: "") }
        return name
    }

    /// Ce que fait chaque famille de modèles, en une phrase (comme dans Claude).
    public static func familyBlurb(_ id: String) -> String? {
        let m = id.lowercased()
        if m.contains("fable") || m.contains("mythos") { return "Pour vos défis les plus difficiles" }
        if m.contains("opus") { return "Pour le travail complexe et les tâches quotidiennes" }
        if m.contains("sonnet") { return "Le plus efficace pour les tâches plus simples" }
        if m.contains("haiku") { return "Le plus rapide pour des réponses rapides" }
        if m.contains("mini") || m.contains("flash") || m.contains("fast") { return "Rapide et économique" }
        if m.contains("pro") || m.contains("large") || m.contains("max") { return "Le plus capable de ce fournisseur" }
        return nil
    }

    /// La famille d'un modèle, pour n'en montrer qu'un par famille (le plus récent).
    public static func family(_ id: String) -> String {
        var f = id.lowercased().replacingOccurrences(of: #"[-_:.]?(latest|preview|\d{4}-?\d{2}-?\d{2}|\d+)"#, with: "", options: .regularExpression)
        f = f.replacingOccurrences(of: #"[-_.:]+$"#, with: "", options: .regularExpression)
        return f
    }

    /// Les modèles mis en avant pour un fournisseur : le plus récent de chaque
    /// famille, dans l'ordre de Claude pour Anthropic, plus le modèle courant.
    /// `models` : la liste du fournisseur (`models(_:live:catalog:)`).
    public static func featured(current: ModelRef, catalog: ModelCatalog, models: [ModelInfo]) -> [ModelRef] {
        let pid = current.providerId
        var ids: [String] = []
        var fams = Set<String>()
        // Le catalogue d'abord (les plus récents), puis la liste du compte : un
        // catalogue incomplet ne cache plus les autres modèles du fournisseur.
        var source: [String] = []
        var seen = Set<String>()
        for id in (catalog.providers[pid] ?? []).map(\.id) + models.map(\.id) where seen.insert(id).inserted {
            source.append(id)
        }
        for id in source {
            if id.contains(":free") && pid != "openrouter" { continue }
            if fams.insert(family(id)).inserted { ids.append(id) }
            if ids.count == 5 { break }
        }
        if pid == "anthropic" {
            func rank(_ id: String) -> Int { ["opus", "fable", "sonnet", "haiku"].firstIndex { id.contains($0) } ?? 9 }
            // Tri stable, comme en Dart.
            ids = ids.enumerated().sorted { a, b in
                rank(a.element) != rank(b.element) ? rank(a.element) < rank(b.element) : a.offset < b.offset
            }.map(\.element)
        }
        if !ids.contains(current.model) { ids.insert(current.model, at: 0) }
        return ids.prefix(6).map { ModelRef(pid, $0) }
    }

    /// Le modèle a-t-il un réglage d'effort natif ? (Sinon l'effort règle la consigne
    /// et la longueur maximale de la réponse.)
    public static func hasNativeEffort(_ p: ProviderDef?, model: String?) -> Bool {
        guard let p, let model else { return false }
        return !reasoningParams(p, model: model, level: .eleve).isEmpty
    }

    /// La note sous la liste des efforts, comme dans Claude.
    public static let effortNote = "Un effort plus élevé signifie des réponses plus approfondies, mais prend plus de temps et consomme vos limites plus rapidement."

    /// La note complète : avec l'avertissement pour un modèle sans réglage natif.
    public static func effortNote(_ p: ProviderDef?, model: String?) -> String {
        let native = p == nil || model == nil ? true : hasNativeEffort(p, model: model)
        return native ? effortNote : "\(effortNote)\n« \(model ?? "") » n'a pas de réglage natif : l'effort ajuste sa consigne et la longueur de ses réponses."
    }

    /// Le texte de « Ajouter des modèles » dans le panneau des modèles.
    public static func addModelsHint(providerId: String) -> String {
        providerId == "pollinations"
            ? "Sans compte, Pollinations n'a qu'un modèle et coupe chaque réponse à 1 500 tokens (NEXORA demande la suite tout seul). Une clé gratuite (Groq, Gemini, OpenRouter…) en ajoute des dizaines."
            : "Ajoutez la clé d'un fournisseur (beaucoup sont gratuits) pour choisir parmi ses modèles."
    }
}
