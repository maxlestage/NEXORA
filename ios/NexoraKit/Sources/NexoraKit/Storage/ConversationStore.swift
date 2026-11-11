import Foundation

/// Les conversations sur l'appareil, dans le même dossier et le même format que
/// l'app Flutter (`services/conversation_store.dart`) : un index léger
/// (`index.json` : titres, aperçus) lu au démarrage, et les messages de chaque
/// conversation dans leur propre fichier (`<id>.json`), lus seulement à
/// l'ouverture et réécrits seuls. L'app Swift, qui remplace l'app Flutter sur iOS,
/// retrouve ainsi toutes les conversations. Un acteur : les écritures passent l'une
/// après l'autre (une suppression ne peut pas être annulée par un enregistrement
/// en cours).
public actor ConversationStore {
    /// Le résumé d'une conversation dans l'index (`Conversation.toMeta` en Dart).
    public struct Meta: Codable, Sendable, Hashable, Identifiable {
        public let id: String
        public var title: String
        public var model: String?
        public var agentId: String?
        public var level: String?
        /// Les skills chargées dans la conversation (gardées telles quelles).
        public var skills: [String]
        public var updated: Date
        public var pinned: Bool
        public var preview: String
        public var count: Int

        public init(
            id: String, title: String, model: String? = nil, agentId: String? = nil, level: String? = nil,
            skills: [String] = [], updated: Date = Date(), pinned: Bool = false, preview: String = "", count: Int = 0
        ) {
            self.id = id
            self.title = title
            self.model = model
            self.agentId = agentId
            self.level = level
            self.skills = skills
            self.updated = updated
            self.pinned = pinned
            self.preview = preview
            self.count = count
        }

        public init(_ c: Conversation, skills: [String] = []) {
            self.init(
                id: c.id, title: c.title, model: c.model, agentId: c.agentId, level: c.level, skills: skills,
                updated: c.updated, pinned: c.pinned, preview: c.preview, count: c.messages.count
            )
        }

        enum CodingKeys: String, CodingKey {
            case id, title, model, agentId, level, skills, updated, pinned, preview, count
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            title = try c.decodeIfPresent(String.self, forKey: .title) ?? "Conversation"
            model = try? c.decodeIfPresent(String.self, forKey: .model)
            agentId = try? c.decodeIfPresent(String.self, forKey: .agentId)
            level = try? c.decodeIfPresent(String.self, forKey: .level)
            skills = (try? c.decodeIfPresent([String].self, forKey: .skills)) ?? []
            if let s = try? c.decodeIfPresent(String.self, forKey: .updated) {
                updated = ISO8601.parse(s) ?? Date()
            } else if let d = try? c.decodeIfPresent(Double.self, forKey: .updated) {
                // Ancien index de l'app Swift (date en secondes).
                updated = Date(timeIntervalSinceReferenceDate: d)
            } else {
                updated = Date()
            }
            pinned = (try? c.decodeIfPresent(Bool.self, forKey: .pinned)) ?? false
            preview = (try? c.decodeIfPresent(String.self, forKey: .preview)) ?? ""
            count = (try? c.decodeIfPresent(Int.self, forKey: .count)) ?? 0
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(id, forKey: .id)
            try c.encode(title, forKey: .title)
            try c.encodeIfPresent(model, forKey: .model)
            try c.encodeIfPresent(agentId, forKey: .agentId)
            try c.encodeIfPresent(level, forKey: .level)
            if !skills.isEmpty { try c.encode(skills, forKey: .skills) }
            try c.encode(ISO8601.string(updated), forKey: .updated)
            try c.encode(pinned, forKey: .pinned)
            try c.encode(preview, forKey: .preview)
            try c.encode(count, forKey: .count)
        }
    }

    public let directory: URL

    /// L'index gardé en mémoire : lu une fois sur le disque, puis tenu à jour à
    /// chaque écriture (l'acteur est le seul à écrire dans le dossier). Avant, chaque
    /// enregistrement, chaque `load` et chaque conversation parcourue par la
    /// recherche relisait et décodait tout `index.json`.
    private var cached: [Meta]?
    /// La dernière recherche et ses résultats : une recherche qui la prolonge (une
    /// lettre tapée en plus) ne relit que les conversations déjà trouvées. Oubliée à
    /// chaque écriture.
    private var lastSearch: (query: String, ids: Set<String>)?

    public init(directory: URL) {
        self.directory = directory
    }

    /// Le dossier de l'app Flutter, repris tel quel (Application Support/conversations).
    public static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("conversations", isDirectory: true)
    }

    private var indexURL: URL { directory.appendingPathComponent("index.json") }

    private func fileURL(_ id: String) -> URL {
        let safe = id.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        return directory.appendingPathComponent("\(safe).json")
    }

    private func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// L'index (résumés), du plus récent au plus ancien, épinglées d'abord.
    public func index() -> [Meta] {
        Self.sorted(rawIndex())
    }

    private func rawIndex() -> [Meta] {
        if let cached { return cached }
        let list = Self.readIndex(indexURL)
        cached = list
        return list
    }

    /// L'index lu sur le disque. Une entrée abîmée ne fait pas perdre les autres.
    static func readIndex(_ url: URL) -> [Meta] {
        guard let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([Lenient<Meta>].self, from: data) else { return [] }
        return list.compactMap(\.value)
    }

    /// Un élément de liste décodé sans faire échouer la liste entière.
    struct Lenient<T: Decodable>: Decodable {
        let value: T?

        init(from decoder: Decoder) throws {
            value = try? T(from: decoder)
        }
    }

    /// Le dossier a changé : la dernière recherche n'est plus valable.
    private func changed() {
        lastSearch = nil
    }

    public static func sorted(_ list: [Meta]) -> [Meta] {
        list.sorted { a, b in a.pinned != b.pinned ? a.pinned : a.updated > b.updated }
    }

    /// Une conversation et ses messages.
    public func load(_ id: String) -> Conversation? {
        let meta = rawIndex().first { $0.id == id }
        guard let data = try? Data(contentsOf: fileURL(id)) else {
            return meta.map { Self.conversation($0, messages: []) }
        }
        // Le format de l'app Flutter : la liste des messages.
        if let messages = try? JSONDecoder().decode([ChatMessage].self, from: data) {
            return meta.map { Self.conversation($0, messages: messages) }
                ?? Conversation(id: id, title: "Conversation", messages: messages)
        }
        // L'ancien format de l'app Swift : toute la conversation.
        return try? JSONDecoder().decode(Conversation.self, from: data)
    }

    static func conversation(_ m: Meta, messages: [ChatMessage]) -> Conversation {
        Conversation(
            id: m.id, title: m.title, model: m.model, agentId: m.agentId, level: m.level,
            messages: messages, updated: m.updated, pinned: m.pinned
        )
    }

    /// Les skills enregistrées pour une conversation.
    public func skills(_ id: String) -> [String] {
        rawIndex().first { $0.id == id }?.skills ?? []
    }

    /// Enregistre une conversation (ses messages, puis l'index), en écriture atomique.
    public func save(_ c: Conversation) throws {
        changed()
        try ensureDirectory()
        let data = try JSONEncoder().encode(c.messages)
        try data.write(to: fileURL(c.id), options: .atomic)
        var list = rawIndex()
        let skills = list.first { $0.id == c.id }?.skills ?? []
        list.removeAll { $0.id == c.id }
        list.append(Meta(c, skills: skills))
        try writeIndex(list)
    }

    /// Met à jour le résumé d'une conversation sans réécrire ses messages (titre,
    /// épingle…).
    public func saveMeta(_ m: Meta) throws {
        changed()
        var list = rawIndex()
        if let i = list.firstIndex(where: { $0.id == m.id }) { list[i] = m } else { list.append(m) }
        try writeIndex(list)
    }

    public func delete(_ id: String) throws {
        changed()
        try? FileManager.default.removeItem(at: fileURL(id))
        try writeIndex(rawIndex().filter { $0.id != id })
    }

    public func deleteAll() throws {
        changed()
        cached = nil
        try? FileManager.default.removeItem(at: directory)
    }

    /// La place prise sur l'appareil, en octets.
    public func sizeOnDisk() -> Int {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return files.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }

    /// Cherche un texte dans toutes les conversations (titre, aperçu et messages).
    public func search(_ query: String) -> [Meta] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return index() }
        var list = index()
        // Ce qui contient la nouvelle recherche contient aussi la précédente.
        if let last = lastSearch, q.contains(last.query) {
            list = list.filter { last.ids.contains($0.id) }
        }
        let found = list.filter { m in
            if m.title.lowercased().contains(q) || m.preview.lowercased().contains(q) { return true }
            guard let c = load(m.id) else { return false }
            return c.messages.contains { $0.content.lowercased().contains(q) }
        }
        lastSearch = (q, Set(found.map(\.id)))
        return found
    }

    /// Les conversations non épinglées sans activité depuis `days` jours (sauf
    /// celles en cours).
    public static func stale(_ list: [Meta], days: Int, now: Date = Date(), running: Set<String> = []) -> [String] {
        let limit = now.addingTimeInterval(-Double(days) * 86400)
        return list.filter { !$0.pinned && $0.updated < limit && !running.contains($0.id) }.map(\.id)
    }

    private func writeIndex(_ list: [Meta]) throws {
        try ensureDirectory()
        let sorted = Self.sorted(list)
        try JSONEncoder().encode(sorted).write(to: indexURL, options: .atomic)
        // Le fichier écrit est désormais l'index en mémoire.
        cached = sorted
    }
}

/// La place prise, lisible (« 12 Ko », « 3.4 Mo », comme dans l'app Flutter).
public func storageLabel(_ bytes: Int) -> String {
    if bytes < 1024 { return "\(bytes) o" }
    if bytes < 1024 * 1024 { return "\(Int((Double(bytes) / 1024).rounded())) Ko" }
    return String(format: "%.1f", Double(bytes) / 1024 / 1024) + " Mo"
}
