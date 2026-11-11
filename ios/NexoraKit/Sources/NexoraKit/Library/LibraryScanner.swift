import Foundation

/// Ce qu'on peut installer depuis un dépôt : sous-agent, skill ou commande.
public enum LibraryItemKind: String, Sendable, Hashable, CaseIterable, Codable {
    case agent, skill, command

    /// « Sous-agent », « Skill », « Commande » (ou au pluriel).
    public func label(plural: Bool = false) -> String {
        switch self {
        case .agent: plural ? "Sous-agents" : "Sous-agent"
        case .skill: plural ? "Skills" : "Skill"
        case .command: plural ? "Commandes" : "Commande"
        }
    }
}

/// Un élément trouvé dans un dépôt.
public struct LibraryItem: Sendable, Hashable, Identifiable {
    public let kind: LibraryItemKind
    public let owner: String
    public let repo: String
    public let ref: String
    /// Le fichier : `agents/x.md`, `skills/y/SKILL.md`, `commands/z.md`.
    public let path: String
    /// Le plugin auquel il appartient (dossier `plugins/<nom>/`), s'il y en a un.
    public let plugin: String?
    /// Pour une skill : ses autres fichiers (chemins relatifs à son dossier).
    public let files: [String]

    public init(kind: LibraryItemKind, owner: String, repo: String, ref: String, path: String, plugin: String? = nil, files: [String] = []) {
        self.kind = kind
        self.owner = owner
        self.repo = repo
        self.ref = ref
        self.path = path
        self.plugin = plugin
        self.files = files
    }

    /// Le nom affiché : le fichier, ou le dossier pour une skill.
    public var name: String {
        let parts = path.components(separatedBy: "/")
        if kind == .skill { return parts.count > 1 ? parts[parts.count - 2] : "skill" }
        let last = parts.last ?? path
        return last.hasSuffix(".md") ? String(last.dropLast(3)) : last
    }

    /// Le dossier (pour une skill : celui qui contient SKILL.md).
    public var dir: String {
        guard let i = path.lastIndex(of: "/") else { return "" }
        return String(path[..<i])
    }

    public var key: String { "\(owner)/\(repo)/\(path)" }
    public var id: String { key }
    public var source: String { "https://github.com/\(owner)/\(repo)/blob/\(ref)/\(path)" }
}

/// Un plugin annoncé par un catalogue (`.claude-plugin/marketplace.json`) : un
/// paquet d'agents, de skills et de commandes, parfois dans un autre dépôt.
public struct PluginRef: Sendable, Hashable, Identifiable {
    public let name: String
    public let description: String
    /// `propriétaire/dépôt/dossier`, à scanner pour l'installer.
    public let spec: String
    public let category: String

    public init(name: String, description: String, spec: String, category: String = "") {
        self.name = name
        self.description = description
        self.spec = spec
        self.category = category
    }

    public var id: String { "\(name)|\(spec)" }
}

/// Ce que contient un dépôt.
public struct RepoScan: Sendable, Hashable {
    public let owner: String
    public let repo: String
    public let ref: String
    public let items: [LibraryItem]
    public let plugins: [PluginRef]

    public init(owner: String, repo: String, ref: String, items: [LibraryItem], plugins: [PluginRef]) {
        self.owner = owner
        self.repo = repo
        self.ref = ref
        self.items = items
        self.plugins = plugins
    }

    public func of(_ k: LibraryItemKind) -> [LibraryItem] { items.filter { $0.kind == k } }
    public var isEmpty: Bool { items.isEmpty && plugins.isEmpty }
}

/// Une source sûre, installable en un geste.
public struct LibrarySource: Sendable, Hashable, Identifiable {
    public let spec: String
    public let title: String
    public let description: String
    public let emoji: String

    public init(_ spec: String, _ title: String, _ description: String, _ emoji: String) {
        self.spec = spec
        self.title = title
        self.description = description
        self.emoji = emoji
    }

    public var id: String { spec }
}

/// L'explorateur de bibliothèque : trouve dans un dépôt GitHub les sous-agents,
/// skills, commandes et plugins au format de Claude Code.
public enum LibraryScanner {
    /// Les sources recommandées.
    public static let sources: [LibrarySource] = [
        LibrarySource(
            "anthropics/skills", "Skills officielles d'Anthropic",
            "Documents (PDF, Word, Excel, PowerPoint), design, art génératif, création de serveurs MCP, création de skills…",
            "🧩"
        ),
        LibrarySource(
            "anthropics/claude-code", "Plugins officiels de Claude Code",
            "Revue de code, développement de fonctionnalités, commits et pull requests : agents, commandes et skills prêts à l'emploi.",
            "🟠"
        ),
        LibrarySource(
            "obra/superpowers", "Superpowers",
            "Des skills de méthode : TDD, débogage systématique, planification, revue.",
            "🦸"
        ),
        LibrarySource(
            "openai/skills", "Skills d'OpenAI",
            "Applications ChatGPT, déploiement sur Cloudflare, Figma, outils en ligne de commande, ASP.NET…",
            "⚪"
        ),
        LibrarySource(
            "vercel-labs/agent-skills", "Skills de Vercel",
            "Bonnes pratiques React et React Native, transitions de vues, design web, déploiement sur Vercel.",
            "▲"
        ),
        LibrarySource(
            "mrgoonie/claudekit-skills", "ClaudeKit",
            "Débogage systématique, recherche de la cause, revue de code, bases de données, back-end, multimodal…",
            "🧰"
        ),
        LibrarySource(
            "huggingface/skills", "Skills de Hugging Face",
            "Modèles, jeux de données, entraînement et déploiement avec Hugging Face.",
            "🤗"
        ),
        LibrarySource(
            "microsoft/skills", "Skills de Microsoft",
            "Azure et Kubernetes (AKS) : coûts, dépannage, réseau, déploiement… plus de 200 skills.",
            "🪟"
        ),
        LibrarySource(
            "K-Dense-AI/claude-scientific-skills", "Skills scientifiques (K-Dense)",
            "Biologie, chimie, bio-informatique, analyse de données de recherche : plus de 170 skills.",
            "🔬"
        ),
        LibrarySource(
            "ComposioHQ/awesome-claude-skills", "Awesome Claude Skills (Composio)",
            "Des centaines de skills : documents, design, contenu, et automatisation de services en ligne.",
            "🌐"
        ),
        LibrarySource(
            "alirezarezvani/claude-skills", "Skills métier (alirezarezvani)",
            "Près de 500 skills par métier : produit, marketing, ingénierie, finance, direction…",
            "💼"
        ),
        LibrarySource(
            "wshobson/agents", "Agents spécialistes (wshobson)",
            "Des dizaines de sous-agents : back-end, front-end, sécurité, données, DevOps, IA, langages…",
            "🧑‍💻"
        ),
        LibrarySource(
            "VoltAgent/awesome-claude-code-subagents", "Awesome sub-agents (VoltAgent)",
            "Plus de cent sous-agents classés par métier.",
            "⚡"
        ),
        LibrarySource(
            "wshobson/commands", "Commandes (wshobson)",
            "Des commandes /… pour les flux de travail courants.",
            "⌘"
        ),
    ]

    /// Lit `propriétaire/dépôt[/tree/branche][/dossier]` ou une URL github.com :
    /// (propriétaire, dépôt, branche, dossier).
    public static func parseRepoSpec(_ spec: String) throws -> (owner: String, repo: String, ref: String?, sub: String) {
        var s = spec.trimmingCharacters(in: .whitespacesAndNewlines)
        if let r = s.range(of: #"^https?://github\.com/"#, options: .regularExpression) { s.removeSubrange(r) }
        if let r = s.range(of: #"\.git$"#, options: .regularExpression) { s.removeSubrange(r) }
        let parts = s.components(separatedBy: "/").filter { !$0.isEmpty }
        if parts.count < 2 { throw GitHubError("Format attendu : propriétaire/dépôt[/dossier]") }
        var ref: String?
        var rest = Array(parts.dropFirst(2))
        if let first = rest.first, first == "tree" || first == "blob" {
            ref = rest.count > 1 ? rest[1] : nil
            rest = Array(rest.dropFirst(2))
        }
        return (parts[0], parts[1], ref, rest.joined(separator: "/"))
    }

    static let skipFiles: Set<String> = [
        "readme.md", "contributing.md", "license.md", "changelog.md", "claude.md",
        "agents.md", "code_of_conduct.md", "security.md",
    ]

    /// Le plugin d'un chemin (`…/plugins/<nom>/…`).
    static func pluginOf(_ p: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: #"(?:^|/)plugins/([^/]+)/"#),
              let m = re.firstMatch(in: p, range: NSRange(p.startIndex..., in: p)),
              let r = Range(m.range(at: 1), in: p) else { return nil }
        return String(p[r])
    }

    /// Classe les fichiers d'un dépôt en sous-agents, skills et commandes.
    public static func classify(owner: String, repo: String, ref: String, paths: [String], sub: String = "") -> [LibraryItem] {
        let inSub = sub.isEmpty ? paths : paths.filter { $0 == sub || $0.hasPrefix(sub + "/") }
        var items: [LibraryItem] = []
        var skillDirs: [String] = []
        for p in inSub {
            let low = p.lowercased()
            guard low.hasSuffix("/skill.md") || low == "skill.md" else { continue }
            let dir = p.lastIndex(of: "/").map { String(p[..<$0]) } ?? ""
            if !skillDirs.contains(dir) { skillDirs.append(dir) }
            let prefix = dir.isEmpty ? "" : dir + "/"
            let files = inSub.filter { $0 != p && $0.hasPrefix(prefix) }
                .map { dir.isEmpty ? $0 : String($0.dropFirst(dir.count + 1)) }
            items.append(LibraryItem(
                kind: .skill, owner: owner, repo: repo, ref: ref, path: p,
                plugin: pluginOf(p), files: Array(files.prefix(40))
            ))
        }
        func insideSkill(_ p: String) -> Bool {
            skillDirs.contains { $0.isEmpty || p.hasPrefix($0 + "/") }
        }
        for p in inSub {
            let low = p.lowercased()
            var dirs = low.components(separatedBy: "/")
            let file = dirs.removeLast()
            if !low.hasSuffix(".md") || skipFiles.contains(file) || insideSkill(p) { continue }
            let kind: LibraryItemKind?
            if dirs.contains("commands") {
                kind = .command
            } else if dirs.contains("agents") || dirs.contains("subagents") {
                kind = .agent
            } else if !sub.isEmpty {
                // Un dossier précis demandé : ses .md sont des agents.
                kind = .agent
            } else {
                kind = nil
            }
            guard let kind else { continue }
            items.append(LibraryItem(kind: kind, owner: owner, repo: repo, ref: ref, path: p, plugin: pluginOf(p)))
        }
        return items.sorted { $0.path.utf16.lexicographicallyPrecedes($1.path.utf16) }
    }

    /// Lit le catalogue de plugins d'un dépôt (`.claude-plugin/marketplace.json`).
    public static func parseMarketplace(_ raw: String, owner: String, repo: String) -> [PluginRef] {
        guard let data = raw.data(using: .utf8),
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let plugins = j["plugins"] as? [Any] else { return [] }
        func str(_ v: Any?) -> String {
            guard let v, !(v is NSNull) else { return "" }
            return v as? String ?? "\(v)"
        }
        var out: [PluginRef] = []
        for case let p as [String: Any] in plugins {
            guard let name = p["name"], !(name is NSNull) else { continue }
            var spec: String?
            if let src = p["source"] as? String {
                var path = src
                if path.hasPrefix("./") { path.removeFirst(2) }
                spec = "\(owner)/\(repo)\(path.isEmpty ? "" : "/\(path)")"
            } else if let src = p["source"] as? [String: Any] {
                let url = str(src["url"] ?? src["repo"])
                if let re = try? NSRegularExpression(pattern: #"(?:github\.com/)?([\w.-]+)/([\w.-]+?)(?:\.git)?$"#),
                   let m = re.firstMatch(in: url, range: NSRange(url.startIndex..., in: url)),
                   let o = Range(m.range(at: 1), in: url), let r = Range(m.range(at: 2), in: url) {
                    let path = str(src["path"])
                    spec = "\(url[o])/\(url[r])\(path.isEmpty ? "" : "/\(path)")"
                }
            }
            guard let spec else { continue }
            out.append(PluginRef(name: str(name), description: str(p["description"]), spec: spec, category: str(p["category"])))
        }
        return out
    }

    /// Le catalogue de plugins à lire, s'il y en a un.
    public static func marketplacePath(paths: [String], sub: String) -> String? {
        var candidates: [String] = []
        if !sub.isEmpty { candidates.append("\(sub)/.claude-plugin/marketplace.json") }
        candidates.append(".claude-plugin/marketplace.json")
        return candidates.first { paths.contains($0) }
    }

    /// L'adresse brute (raw.githubusercontent.com) d'un fichier de dépôt.
    public static func rawURL(owner: String, repo: String, ref: String, path: String) -> URL? {
        // Comme Uri.encodeComponent : seuls les caractères non réservés restent tels quels.
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()")
        let encoded = path.components(separatedBy: "/")
            .map { $0.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0 }
            .joined(separator: "/")
        return URL(string: "https://raw.githubusercontent.com/\(owner)/\(repo)/\(ref)/\(encoded)")
    }

    /// Une page `github.com/…/blob/…` devient le fichier brut ; les autres adresses
    /// restent telles quelles.
    public static func rawFileURL(_ url: String) -> String {
        let u = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let re = try? NSRegularExpression(pattern: #"^https://github\.com/([^/]+)/([^/]+)/blob/(.+)$"#),
              let m = re.firstMatch(in: u, range: NSRange(u.startIndex..., in: u)),
              let a = Range(m.range(at: 1), in: u), let b = Range(m.range(at: 2), in: u),
              let c = Range(m.range(at: 3), in: u) else { return u }
        return "https://raw.githubusercontent.com/\(u[a])/\(u[b])/\(u[c])"
    }
}
