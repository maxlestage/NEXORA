import Foundation

/// Les conversations sur l'appareil : un fichier JSON par conversation, plus un
/// index léger (titre, aperçu) pour démarrer vite même avec des centaines de
/// conversations.
public actor ConversationStore {
    public struct Meta: Codable, Sendable, Hashable, Identifiable {
        public let id: String
        public var title: String
        public var model: String?
        public var agentId: String?
        public var updated: Date
        public var pinned: Bool
        public var preview: String
        public var count: Int
    }

    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// Le dossier par défaut de l'app (Application Support/Conversations).
    public static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("Conversations", isDirectory: true)
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
        guard let data = try? Data(contentsOf: indexURL),
              let list = try? JSONDecoder().decode([Meta].self, from: data) else { return [] }
        return Self.sorted(list)
    }

    static func sorted(_ list: [Meta]) -> [Meta] {
        list.sorted { a, b in a.pinned != b.pinned ? a.pinned : a.updated > b.updated }
    }

    public func load(_ id: String) -> Conversation? {
        guard let data = try? Data(contentsOf: fileURL(id)) else { return nil }
        return try? JSONDecoder().decode(Conversation.self, from: data)
    }

    /// Enregistre une conversation et met l'index à jour (écriture atomique).
    public func save(_ c: Conversation) throws {
        try ensureDirectory()
        let data = try JSONEncoder().encode(c)
        try data.write(to: fileURL(c.id), options: .atomic)
        var list = index().filter { $0.id != c.id }
        list.append(Meta(
            id: c.id, title: c.title, model: c.model, agentId: c.agentId, updated: c.updated,
            pinned: c.pinned, preview: c.preview, count: c.messages.count
        ))
        try writeIndex(list)
    }

    public func delete(_ id: String) throws {
        try? FileManager.default.removeItem(at: fileURL(id))
        try writeIndex(index().filter { $0.id != id })
    }

    public func deleteAll() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    /// La place prise sur l'appareil, en octets.
    public func sizeOnDisk() -> Int {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return files.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }

    /// Cherche un texte dans toutes les conversations (titre et messages).
    public func search(_ query: String) -> [Meta] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return index() }
        return index().filter { m in
            if m.title.lowercased().contains(q) { return true }
            guard let c = load(m.id) else { return false }
            return c.messages.contains { $0.content.lowercased().contains(q) }
        }
    }

    private func writeIndex(_ list: [Meta]) throws {
        try ensureDirectory()
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .deferredToDate
        try enc.encode(Self.sorted(list)).write(to: indexURL, options: .atomic)
    }
}
