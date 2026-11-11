import Foundation

/// Le protocole parlé par un fournisseur d'IA.
public enum ApiKind: String, Codable, Sendable, CaseIterable {
    /// `POST {base}/chat/completions`, flux SSE `data: {...}` (OpenAI et compatibles).
    case openai
    /// API native d'Ollama : `POST {base}/api/chat`, flux NDJSON.
    case ollama
    /// API Messages d'Anthropic : `POST {base}/messages`, flux SSE typé.
    case anthropic

    public var label: String {
        switch self {
        case .openai: "OpenAI (compatible)"
        case .ollama: "Ollama"
        case .anthropic: "Anthropic Messages"
        }
    }
}

/// Comment obtenir la liste des modèles d'un fournisseur.
public enum ModelsListing: String, Codable, Sendable, CaseIterable {
    /// `GET {base}/models` → `data[].id`.
    case openai
    /// `GET {base}/api/tags` → `models[].name`.
    case ollama
    /// `GET https://models.github.ai/catalog/models` → `[].id`.
    case githubCatalog
    /// `GET https://text.pollinations.ai/models` → `[].name`.
    case pollinations
    /// Pas de liste : seulement les modèles par défaut.
    case none
}

/// Une fiche de fournisseur : le catalogue, ou un fournisseur créé par l'utilisateur.
public struct ProviderDef: Codable, Sendable, Identifiable, Hashable {
    public var id: String
    public var name: String
    /// Adresse de base, sans `/` final (ex. `https://api.groq.com/openai/v1`).
    public var baseUrl: String
    public var kind: ApiKind
    public var listing: ModelsListing
    /// Offre gratuite (avec ou sans clé).
    public var free: Bool
    /// Une clé d'API est nécessaire.
    public var needsKey: Bool
    /// Tourne sur votre machine ou votre réseau local.
    public var local: Bool
    public var keyUrl: String?
    public var docsUrl: String?
    public var description: String
    public var defaultModels: [String]
    /// Suffixe des modèles gratuits (`:free` chez OpenRouter).
    public var freeModelSuffix: String?
    /// Chemin du chat s'il diffère du protocole (`""` : la base est l'URL du chat).
    public var chatPath: String?
    public var extraHeaders: [String: String]
    /// Couleur ARGB (`0xFF22D3EE`).
    public var color: UInt32
    public var emoji: String
    /// Créé par l'utilisateur (modifiable, supprimable).
    public var custom: Bool
    /// Utilise le jeton GitHub de la session si aucune clé n'est saisie.
    public var usesGitHubToken: Bool

    public init(
        id: String, name: String, baseUrl: String, kind: ApiKind,
        listing: ModelsListing = .openai, free: Bool = false, needsKey: Bool = true,
        local: Bool = false, keyUrl: String? = nil, docsUrl: String? = nil,
        description: String = "", defaultModels: [String] = [],
        freeModelSuffix: String? = nil, chatPath: String? = nil,
        extraHeaders: [String: String] = [:], color: UInt32 = 0xFF22_D3EE,
        emoji: String = "🤖", custom: Bool = false, usesGitHubToken: Bool = false
    ) {
        self.id = id
        self.name = name
        self.baseUrl = baseUrl
        self.kind = kind
        self.listing = listing
        self.free = free
        self.needsKey = needsKey
        self.local = local
        self.keyUrl = keyUrl
        self.docsUrl = docsUrl
        self.description = description
        self.defaultModels = defaultModels
        self.freeModelSuffix = freeModelSuffix
        self.chatPath = chatPath
        self.extraHeaders = extraHeaders
        self.color = color
        self.emoji = emoji
        self.custom = custom
        self.usesGitHubToken = usesGitHubToken
    }

    enum CodingKeys: String, CodingKey {
        case id, name, baseUrl, kind, listing, free, needsKey, local, keyUrl, docsUrl
        case description, defaultModels, freeModelSuffix, chatPath, extraHeaders
        case color, emoji, custom, usesGitHubToken
    }

    /// Lecture indulgente : les champs absents prennent leur valeur par défaut, comme
    /// dans le catalogue de l'app Flutter.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Personnalisé"
        baseUrl = try c.decodeIfPresent(String.self, forKey: .baseUrl) ?? ""
        kind = (try? c.decodeIfPresent(ApiKind.self, forKey: .kind)) ?? .openai
        listing = (try? c.decodeIfPresent(ModelsListing.self, forKey: .listing)) ?? .openai
        free = try c.decodeIfPresent(Bool.self, forKey: .free) ?? false
        needsKey = try c.decodeIfPresent(Bool.self, forKey: .needsKey) ?? true
        local = try c.decodeIfPresent(Bool.self, forKey: .local) ?? false
        keyUrl = try c.decodeIfPresent(String.self, forKey: .keyUrl)
        docsUrl = try c.decodeIfPresent(String.self, forKey: .docsUrl)
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        defaultModels = try c.decodeIfPresent([String].self, forKey: .defaultModels) ?? []
        freeModelSuffix = try c.decodeIfPresent(String.self, forKey: .freeModelSuffix)
        chatPath = try c.decodeIfPresent(String.self, forKey: .chatPath)
        extraHeaders = try c.decodeIfPresent([String: String].self, forKey: .extraHeaders) ?? [:]
        if let hex = try? c.decodeIfPresent(String.self, forKey: .color) {
            color = UInt32(hex.replacingOccurrences(of: "0x", with: ""), radix: 16) ?? 0xFF22_D3EE
        } else {
            color = (try? c.decodeIfPresent(UInt32.self, forKey: .color)) ?? 0xFF22_D3EE
        }
        emoji = try c.decodeIfPresent(String.self, forKey: .emoji) ?? "🤖"
        custom = try c.decodeIfPresent(Bool.self, forKey: .custom) ?? false
        usesGitHubToken = try c.decodeIfPresent(Bool.self, forKey: .usesGitHubToken) ?? false
    }

    /// Le gabarit d'un fournisseur personnalisé compatible OpenAI (llama.cpp, vLLM,
    /// LocalAI, Jan…).
    public static func customTemplate(id: String) -> ProviderDef {
        ProviderDef(
            id: id, name: "Mon serveur", baseUrl: "http://192.168.1.10:8080/v1",
            kind: .openai, needsKey: false, description: "Tout serveur compatible OpenAI.",
            color: 0xFFA7_8BFA, emoji: "🧩", custom: true
        )
    }
}

/// Un modèle choisi : fournisseur + identifiant (`fournisseur::modèle`).
public struct ModelRef: Hashable, Sendable, Codable {
    public let providerId: String
    public let model: String

    public init(_ providerId: String, _ model: String) {
        self.providerId = providerId
        self.model = model
    }

    public var key: String { "\(providerId)::\(model)" }

    public static func parse(_ s: String?) -> ModelRef? {
        guard let s, let r = s.range(of: "::"), r.lowerBound > s.startIndex else { return nil }
        return ModelRef(String(s[..<r.lowerBound]), String(s[r.upperBound...]))
    }

    public static let fallback = ModelRef("pollinations", "openai")
}

/// Un modèle proposé par un fournisseur.
public struct ModelInfo: Hashable, Sendable, Identifiable {
    public let id: String
    public let free: Bool
    public let detail: String?

    public init(_ id: String, free: Bool = false, detail: String? = nil) {
        self.id = id
        self.free = free
        self.detail = detail
    }
}
