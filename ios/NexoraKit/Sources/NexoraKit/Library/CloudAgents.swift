import Foundation

/// Un agent « cloud » : un workflow GitHub Actions que NEXORA installe dans un
/// dépôt, puis lance avec une instruction (`workflow_dispatch`) depuis le
/// téléphone. L'agent travaille sur les serveurs de GitHub et ouvre une pull
/// request. Catalogue recopié de l'app Flutter (`data/github_agents.dart`) par
/// `ios/Tools/sync_catalogs.py`.
public struct CloudAgent: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let emoji: String
    public let description: String
    /// Les secrets à ajouter dans le dépôt (Settings → Secrets and variables → Actions).
    public let secrets: [String]
    /// Nom du fichier dans `.github/workflows/`.
    public let workflowFile: String
    public let yaml: String
    public let free: Bool
    /// Mention qui déclenche l'agent dans une issue ou un commentaire.
    public let mention: String?
    public let secretHelpUrl: String?

    public init(
        id: String, name: String, emoji: String, description: String, secrets: [String],
        workflowFile: String, yaml: String, free: Bool = false, mention: String? = nil, secretHelpUrl: String? = nil
    ) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.description = description
        self.secrets = secrets
        self.workflowFile = workflowFile
        self.yaml = yaml
        self.free = free
        self.mention = mention
        self.secretHelpUrl = secretHelpUrl
    }

    enum CodingKeys: String, CodingKey {
        case id, name, emoji, description, secrets, workflowFile, yaml, free, mention, secretHelpUrl
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        emoji = try c.decodeIfPresent(String.self, forKey: .emoji) ?? "🤖"
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        secrets = try c.decodeIfPresent([String].self, forKey: .secrets) ?? []
        workflowFile = try c.decode(String.self, forKey: .workflowFile)
        yaml = try c.decodeIfPresent(String.self, forKey: .yaml) ?? ""
        free = try c.decodeIfPresent(Bool.self, forKey: .free) ?? false
        mention = try c.decodeIfPresent(String.self, forKey: .mention)
        secretHelpUrl = try c.decodeIfPresent(String.self, forKey: .secretHelpUrl)
    }

    /// Le chemin du workflow dans le dépôt.
    public var path: String { ".github/workflows/\(workflowFile)" }
}

extension Catalog {
    /// Les agents cloud (workflows GitHub) que NEXORA sait installer.
    public static let cloudAgents: [CloudAgent] = load("cloud_agents", as: [CloudAgent].self) ?? []
}
