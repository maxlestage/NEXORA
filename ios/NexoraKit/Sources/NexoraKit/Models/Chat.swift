import Foundation

public enum Role: String, Codable, Sendable {
    case system, user, assistant
}

/// Un message d'une conversation, enregistré sur l'appareil (même format JSON que
/// l'app Flutter, pour pouvoir relire une sauvegarde).
public struct ChatMessage: Codable, Sendable, Identifiable, Hashable {
    public var id: UUID
    public var role: Role
    public var content: String
    /// Le raisonnement affiché par certains modèles (DeepSeek R1, Qwen3…).
    public var thinking: String
    public var at: Date
    /// `fournisseur::modèle` qui a répondu.
    public var model: String?
    public var error: Bool
    public var tokensIn: Int
    public var tokensOut: Int
    /// Ce qu'a coûté la réponse, en dollars, si le prix du modèle est connu.
    public var cost: Double?
    /// Décompte estimé (~4 caractères par token).
    public var estimated: Bool
    /// Le sous-agent qui a répondu (`@nom`), affiché à la place du modèle.
    public var by: String?
    /// La commande tapée (`/nom arguments`).
    public var command: String?
    /// Votre avis : 1 (bonne), -1 (mauvaise), 0 (aucun).
    public var rating: Int

    public init(
        role: Role, content: String, thinking: String = "", at: Date = Date(),
        model: String? = nil, error: Bool = false, by: String? = nil, command: String? = nil
    ) {
        id = UUID()
        self.role = role
        self.content = content
        self.thinking = thinking
        self.at = at
        self.model = model
        self.error = error
        tokensIn = 0
        tokensOut = 0
        cost = nil
        estimated = false
        self.by = by
        self.command = command
        rating = 0
    }

    enum CodingKeys: String, CodingKey {
        case role, content, thinking, at, model, error
        case tokensIn = "tin", tokensOut = "tout", cost, estimated = "est", by, command = "cmd", rating
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = UUID()
        role = (try? c.decode(Role.self, forKey: .role)) ?? .user
        content = try c.decodeIfPresent(String.self, forKey: .content) ?? ""
        thinking = try c.decodeIfPresent(String.self, forKey: .thinking) ?? ""
        at = ISO8601.parse(try c.decodeIfPresent(String.self, forKey: .at)) ?? Date()
        model = try c.decodeIfPresent(String.self, forKey: .model)
        error = try c.decodeIfPresent(Bool.self, forKey: .error) ?? false
        tokensIn = try c.decodeIfPresent(Int.self, forKey: .tokensIn) ?? 0
        tokensOut = try c.decodeIfPresent(Int.self, forKey: .tokensOut) ?? 0
        cost = try c.decodeIfPresent(Double.self, forKey: .cost)
        estimated = try c.decodeIfPresent(Bool.self, forKey: .estimated) ?? false
        by = try c.decodeIfPresent(String.self, forKey: .by)
        command = try c.decodeIfPresent(String.self, forKey: .command)
        rating = try c.decodeIfPresent(Int.self, forKey: .rating) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(role, forKey: .role)
        try c.encode(content, forKey: .content)
        if !thinking.isEmpty { try c.encode(thinking, forKey: .thinking) }
        try c.encode(ISO8601.string(at), forKey: .at)
        try c.encodeIfPresent(model, forKey: .model)
        if error { try c.encode(true, forKey: .error) }
        if tokensIn > 0 { try c.encode(tokensIn, forKey: .tokensIn) }
        if tokensOut > 0 { try c.encode(tokensOut, forKey: .tokensOut) }
        try c.encodeIfPresent(cost, forKey: .cost)
        if estimated { try c.encode(true, forKey: .estimated) }
        try c.encodeIfPresent(by, forKey: .by)
        try c.encodeIfPresent(command, forKey: .command)
        if rating != 0 { try c.encode(rating, forKey: .rating) }
    }
}

/// Une conversation : son titre, son modèle, son agent et ses messages.
public struct Conversation: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public var title: String
    /// `fournisseur::modèle`.
    public var model: String?
    /// L'agent (prompt système) utilisé.
    public var agentId: String?
    /// Le niveau de réflexion choisi (`ThinkLevel.rawValue`).
    public var level: String?
    public var messages: [ChatMessage]
    public var updated: Date
    public var pinned: Bool

    public init(
        id: String = newId(), title: String = "Nouvelle conversation", model: String? = nil,
        agentId: String? = nil, level: String? = nil, messages: [ChatMessage] = [],
        updated: Date = Date(), pinned: Bool = false
    ) {
        self.id = id
        self.title = title
        self.model = model
        self.agentId = agentId
        self.level = level
        self.messages = messages
        self.updated = updated
        self.pinned = pinned
    }

    enum CodingKeys: String, CodingKey {
        case id, title, model, agentId, level, messages, updated, pinned
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? "Conversation"
        model = try c.decodeIfPresent(String.self, forKey: .model)
        agentId = try c.decodeIfPresent(String.self, forKey: .agentId)
        level = try c.decodeIfPresent(String.self, forKey: .level)
        messages = try c.decodeIfPresent([ChatMessage].self, forKey: .messages) ?? []
        updated = ISO8601.parse(try c.decodeIfPresent(String.self, forKey: .updated)) ?? Date()
        pinned = try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(model, forKey: .model)
        try c.encodeIfPresent(agentId, forKey: .agentId)
        try c.encodeIfPresent(level, forKey: .level)
        try c.encode(messages, forKey: .messages)
        try c.encode(ISO8601.string(updated), forKey: .updated)
        try c.encode(pinned, forKey: .pinned)
    }

    /// Le coût total de la conversation, en dollars.
    public var cost: Double { messages.reduce(0) { $0 + ($1.cost ?? 0) } }

    /// Les tokens de la conversation (envoyés + reçus).
    public var tokens: Int { messages.reduce(0) { $0 + $1.tokensIn + $1.tokensOut } }

    /// Le début du dernier message, pour la liste.
    public var preview: String {
        guard let last = messages.last else { return "" }
        let t = last.content.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return t.count > 140 ? String(t.prefix(140)) : t
    }

    /// La conversation en Markdown, pour l'exporter ou la partager.
    public func markdown() -> String {
        var out = "# \(title)\n\n"
        for m in messages where m.role != .system {
            out += m.role == .user ? "**Vous**\n\n" : "**\(m.by ?? m.model ?? "NEXORA")**\n\n"
            out += m.content + "\n\n"
        }
        return out
    }
}

/// Un identifiant court et unique.
public func newId() -> String {
    let t = UInt64(Date().timeIntervalSince1970 * 1_000_000)
    let r = UInt16.random(in: 0..<1296)
    let suffix = String(r, radix: 36)
    return String(t, radix: 36) + String(repeating: "0", count: max(0, 2 - suffix.count)) + suffix
}

/// Dates au format ISO 8601 (avec ou sans fractions de seconde, comme Dart).
enum ISO8601 {
    static func string(_ d: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: d)
    }

    static func parse(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        if let d = f.date(from: s) { return d }
        // Dart écrit l'heure locale sans fuseau : « 2026-11-11T08:30:00.123456 ».
        let local = DateFormatter()
        local.locale = Locale(identifier: "en_US_POSIX")
        for format in ["yyyy-MM-dd'T'HH:mm:ss.SSSSSS", "yyyy-MM-dd'T'HH:mm:ss.SSS", "yyyy-MM-dd'T'HH:mm:ss"] {
            local.dateFormat = format
            if let d = local.date(from: s) { return d }
        }
        return nil
    }
}
