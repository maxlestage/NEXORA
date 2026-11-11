import Foundation

/// L'en-tête YAML (`---` … `---`) d'un fichier Markdown, et le reste du texte.
public func parseFrontmatter(_ text: String) -> ([String: String], String) {
    var body = text.replacingOccurrences(of: "\r\n", with: "\n")
    var meta: [String: String] = [:]
    let trimmedBody = { (s: String) in s.trimmingCharacters(in: .whitespacesAndNewlines) }
    guard body.hasPrefix("---") else { return (meta, trimmedBody(body)) }
    let afterOpen = body.index(body.startIndex, offsetBy: 3)
    guard let end = body.range(of: "\n---", range: afterOpen..<body.endIndex) else { return (meta, trimmedBody(body)) }
    let header = String(body[afterOpen..<end.lowerBound])
    body = String(body[end.upperBound...])
    var last: String?
    for raw in header.components(separatedBy: "\n") {
        let t = raw.trimmingCharacters(in: .whitespaces)
        if t.isEmpty || t.hasPrefix("#") { continue }
        let cont = raw.hasPrefix(" ") || raw.hasPrefix("\t")
        if cont, let key = last {
            let v = t.hasPrefix("- ") ? String(t.dropFirst(2)) : t
            meta[key] = [meta[key], v].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
            continue
        }
        guard let colon = raw.firstIndex(of: ":"), colon > raw.startIndex else { continue }
        let key = raw[..<colon].trimmingCharacters(in: .whitespaces)
        last = key
        var v = raw[raw.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        if [">", "|", ">-", "|-"].contains(v) { v = "" }
        if v.count >= 2, (v.hasPrefix("\"") && v.hasSuffix("\"")) || (v.hasPrefix("'") && v.hasSuffix("'")) {
            v = String(v.dropFirst().dropLast())
        }
        meta[key] = v
    }
    return (meta, trimmedBody(body))
}

/// Une skill au format de Claude Code : un dossier avec un `SKILL.md` (en-tête `name`
/// et `description`, puis les instructions) et parfois d'autres fichiers. Seuls son nom
/// et sa description sont donnés au modèle ; il charge le reste quand elle sert.
public struct Skill: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public var name: String
    public var description: String
    /// Les instructions (le `SKILL.md` sans son en-tête).
    public var body: String
    /// D'où elle vient (URL), et où relire ses autres fichiers sur GitHub.
    public var source: String
    public var owner: String?
    public var repo: String?
    public var ref: String?
    public var dir: String?
    /// Les autres fichiers du dossier de la skill (chemins relatifs).
    public var files: [String]
    /// Toujours active dans les conversations (sinon : chargée quand elle sert).
    public var always: Bool

    public init(
        id: String, name: String, description: String, body: String, source: String = "",
        owner: String? = nil, repo: String? = nil, ref: String? = nil, dir: String? = nil,
        files: [String] = [], always: Bool = false
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.body = body
        self.source = source
        self.owner = owner
        self.repo = repo
        self.ref = ref
        self.dir = dir
        self.files = files
        self.always = always
    }

    enum CodingKeys: String, CodingKey {
        case id, name, description, body, source, owner, repo, ref, dir, files, always
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "skill"
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        body = try c.decodeIfPresent(String.self, forKey: .body) ?? ""
        source = try c.decodeIfPresent(String.self, forKey: .source) ?? ""
        owner = try c.decodeIfPresent(String.self, forKey: .owner)
        repo = try c.decodeIfPresent(String.self, forKey: .repo)
        ref = try c.decodeIfPresent(String.self, forKey: .ref)
        dir = try c.decodeIfPresent(String.self, forKey: .dir)
        files = try c.decodeIfPresent([String].self, forKey: .files) ?? []
        always = try c.decodeIfPresent(Bool.self, forKey: .always) ?? false
    }

    /// Le texte donné au modèle quand la skill est chargée.
    public var instructions: String {
        var parts = ["# Skill « \(name) »", body]
        if !files.isEmpty { parts.append("Fichiers de la skill (à lire au besoin) : \(files.joined(separator: ", "))") }
        return parts.joined(separator: "\n\n")
    }

    /// Lit un `SKILL.md`. Le nom vient de l'en-tête, sinon du dossier.
    public static func fromMarkdown(
        _ text: String, id: String, fallbackName: String = "skill", source: String = "",
        owner: String? = nil, repo: String? = nil, ref: String? = nil, dir: String? = nil,
        files: [String] = []
    ) -> Skill? {
        let (meta, body) = parseFrontmatter(text)
        if body.isEmpty { return nil }
        let name = (meta["name"] ?? "").isEmpty ? fallbackName : meta["name"]!
        return Skill(
            id: id, name: name, description: meta["description"] ?? "", body: body, source: source,
            owner: owner, repo: repo, ref: ref, dir: dir, files: files
        )
    }
}

/// Une commande : un fichier `commands/nom.md`, modèle de message lancé avec `/nom`
/// (`$ARGUMENTS` est remplacé par ce qui suit, `$1`…`$9` par chaque mot).
public struct SlashCommand: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public var name: String
    public var description: String
    public var body: String
    public var argumentHint: String
    public var source: String

    public init(id: String, name: String, description: String, body: String, argumentHint: String = "", source: String = "") {
        self.id = id
        self.name = name
        self.description = description
        self.body = body
        self.argumentHint = argumentHint
        self.source = source
    }

    enum CodingKeys: String, CodingKey {
        case id, name, description, body, argumentHint = "hint", source
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "commande"
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        body = try c.decodeIfPresent(String.self, forKey: .body) ?? ""
        argumentHint = try c.decodeIfPresent(String.self, forKey: .argumentHint) ?? ""
        source = try c.decodeIfPresent(String.self, forKey: .source) ?? ""
    }

    /// Le message envoyé pour `/nom arguments`.
    public func expand(_ args: String) -> String {
        let a = args.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = a.isEmpty ? [] : a.split(whereSeparator: \.isWhitespace).map(String.init)
        var out = body.replacingOccurrences(of: "$ARGUMENTS", with: a)
        for i in 0..<9 {
            out = out.replacingOccurrences(of: "$\(i + 1)", with: i < parts.count ? parts[i] : "")
        }
        // Sans $ARGUMENTS dans le modèle, les arguments sont ajoutés à la fin.
        let placeholders = body.contains("$ARGUMENTS") || body.range(of: #"\$[1-9]"#, options: .regularExpression) != nil
        if !placeholders && !a.isEmpty { out = "\(out)\n\n\(a)" }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func fromMarkdown(_ text: String, id: String, name: String, source: String = "") -> SlashCommand? {
        let (meta, body) = parseFrontmatter(text)
        if body.isEmpty { return nil }
        return SlashCommand(
            id: id, name: name, description: meta["description"] ?? "", body: body,
            argumentHint: meta["argument-hint"] ?? "", source: source
        )
    }
}
