import Foundation

/// Un agent : un nom, une consigne système, des outils et éventuellement un modèle
/// préféré. Le format d'échange est un fichier Markdown avec un en-tête YAML,
/// compatible avec les sous-agents de Claude Code (`.claude/agents/*.md`) :
///
/// ```markdown
/// ---
/// name: relecteur
/// description: Relit le code et propose des corrections.
/// tools: read_file, search
/// model: groq::llama-3.3-70b-versatile
/// emoji: 🔍
/// ---
/// Tu es un relecteur de code exigeant…
/// ```
public struct Agent: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public var name: String
    public var description: String
    public var emoji: String
    public var systemPrompt: String
    /// `fournisseur::modèle` préféré (facultatif).
    public var model: String?
    /// Effort préféré (`faible`, `moyen`, `eleve`, `extra`, `max`).
    public var level: String?
    /// Outils autorisés en mode autonome (vide : tous).
    public var tools: [String]
    /// `builtin`, `custom`, ou l'URL d'où il a été installé.
    public var source: String
    public var builtin: Bool
    public var category: String

    public init(
        id: String, name: String, systemPrompt: String, description: String = "",
        emoji: String = "🤖", model: String? = nil, level: String? = nil,
        tools: [String] = [], source: String = "custom", builtin: Bool = false,
        category: String = "Perso"
    ) {
        self.id = id
        self.name = name
        self.systemPrompt = systemPrompt
        self.description = description
        self.emoji = emoji
        self.model = model
        self.level = level
        self.tools = tools
        self.source = source
        self.builtin = builtin
        self.category = category
    }

    enum CodingKeys: String, CodingKey {
        case id, name, description, emoji, systemPrompt, model, level, tools, source, builtin, category
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Agent"
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        emoji = try c.decodeIfPresent(String.self, forKey: .emoji) ?? "🤖"
        systemPrompt = try c.decodeIfPresent(String.self, forKey: .systemPrompt) ?? ""
        model = try c.decodeIfPresent(String.self, forKey: .model)
        level = try c.decodeIfPresent(String.self, forKey: .level)
        tools = try c.decodeIfPresent([String].self, forKey: .tools) ?? []
        source = try c.decodeIfPresent(String.self, forKey: .source) ?? "custom"
        builtin = try c.decodeIfPresent(Bool.self, forKey: .builtin) ?? id.hasPrefix("builtin:")
        category = try c.decodeIfPresent(String.self, forKey: .category) ?? "Perso"
    }

    /// Le fichier Markdown de l'agent, pour le partager ou le pousser dans un dépôt.
    public func toMarkdown() -> String {
        var b = "---\n"
        b += "name: \(Self.yamlScalar(name))\n"
        if !description.isEmpty { b += "description: \(Self.yamlScalar(description))\n" }
        if !tools.isEmpty { b += "tools: \(tools.joined(separator: ", "))\n" }
        if let model, !model.isEmpty { b += "model: \(model)\n" }
        if let level, !level.isEmpty { b += "level: \(level)\n" }
        b += "emoji: \(emoji)\n"
        b += "---\n"
        b += systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
        return b
    }

    /// Lit un agent au format Markdown + YAML. Rend `nil` si le texte ne contient pas
    /// de consigne.
    public static func fromMarkdown(_ text: String, id: String, source: String? = nil) -> Agent? {
        var body = text.replacingOccurrences(of: "\r\n", with: "\n")
        var meta: [String: String] = [:]
        if body.hasPrefix("---") {
            let afterOpen = body.index(body.startIndex, offsetBy: 3)
            if let end = body.range(of: "\n---", range: afterOpen..<body.endIndex) {
                let header = String(body[afterOpen..<end.lowerBound])
                body = String(body[end.upperBound...])
                var lastKey: String?
                for raw in header.components(separatedBy: "\n") {
                    let trimmed = raw.trimmingCharacters(in: .whitespaces)
                    if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
                    let continuation = raw.hasPrefix(" ") || raw.hasPrefix("\t")
                    if continuation, let key = lastKey {
                        let v = trimmed.hasPrefix("- ") ? String(trimmed.dropFirst(2)) : trimmed
                        let parts = [meta[key], v].compactMap { $0 }.filter { !$0.isEmpty }
                        meta[key] = parts.joined(separator: key == "tools" ? ", " : " ")
                        continue
                    }
                    guard let colon = raw.firstIndex(of: ":"), colon > raw.startIndex else { continue }
                    let key = raw[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
                    lastKey = key
                    meta[key] = unquote(raw[raw.index(after: colon)...].trimmingCharacters(in: .whitespaces))
                }
            }
        }
        body = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if body.isEmpty { return nil }
        let name = (meta["name"].flatMap { $0.isEmpty ? nil : $0 }) ?? firstHeading(body) ?? "Agent importé"
        let tools = (meta["tools"] ?? "")
            .replacingOccurrences(of: "[", with: "")
            .replacingOccurrences(of: "]", with: "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let model = meta["model"]
        return Agent(
            id: id, name: name, systemPrompt: body, description: meta["description"] ?? "",
            emoji: (meta["emoji"].flatMap { $0.isEmpty ? nil : $0 }) ?? "🧩",
            // Les alias de Claude Code (sonnet, opus, haiku, inherit) ne désignent pas
            // un fournisseur : on garde le modèle de la conversation.
            model: (model?.contains("::") ?? false) ? model : nil,
            level: meta["level"], tools: tools, source: source ?? "custom", category: "Installés"
        )
    }

    private static func firstHeading(_ body: String) -> String? {
        for line in body.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("#") {
                return String(t.drop(while: { $0 == "#" })).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    private static func unquote(_ s: String) -> String {
        if s.count >= 2, (s.hasPrefix("\"") && s.hasSuffix("\"")) || (s.hasPrefix("'") && s.hasSuffix("'")) {
            return String(s.dropFirst().dropLast())
        }
        return s
    }

    private static func yamlScalar(_ s: String) -> String {
        if s.contains(":") || s.contains("#") || s.hasPrefix(" ") {
            return "\"\(s.replacingOccurrences(of: "\"", with: "\\\""))\""
        }
        return s
    }
}
