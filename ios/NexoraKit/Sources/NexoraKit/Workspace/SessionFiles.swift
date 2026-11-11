import Foundation

// # Où sont gardées les sessions d'agent (port de `app/lib/services/session_store.dart`)
//
// Un fichier JSON par session (`<id>.json`, écrit de façon atomique) dans
// Application Support/sessions — le dossier de l'app Flutter, repris tel quel —,
// ou les préférences (`session_ids`, `session_<id>`) si les fichiers ne sont pas
// disponibles. Le JSON est celui de `AgentRun.toJSON()`.

/// Le rangement des sessions : chaque session est un objet JSON, passé en texte
/// encodé (`Data`) pour traverser les fils sans copie hasardeuse.
public protocol SessionFiles: Sendable {
    /// Toutes les sessions enregistrées (les fichiers abîmés sont ignorés).
    func loadAll() async -> [Data]
    func save(_ id: String, _ json: Data) async
    func delete(_ id: String) async
    /// Toutes les sessions, décodées (les fichiers abîmés sont ignorés). Un rangement
    /// sur fichiers les décode chez lui, hors du fil de l'appelant, une seule fois.
    func loadObjects() async -> sending [[String: Any]]
}

extension SessionFiles {
    /// Enregistre un objet JSON (encodé tout de suite, sur le fil de l'appelant).
    public func save(_ id: String, json: sending [String: Any]) async {
        guard let d = SessionJSON.encode(json) else { return }
        await save(id, d)
    }

    /// Toutes les sessions, décodées.
    public func loadObjects() async -> sending [[String: Any]] {
        await loadAll().compactMap(SessionJSON.decode)
    }
}

/// Encodage et décodage du JSON d'une session.
public enum SessionJSON {
    public static func encode(_ json: [String: Any]) -> Data? {
        guard JSONSerialization.isValidJSONObject(json) else { return nil }
        return try? JSONSerialization.data(withJSONObject: json, options: [.withoutEscapingSlashes])
    }

    public static func decode(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}

/// Un fichier JSON par session. Un acteur : les enregistrements d'une session
/// passent l'un après l'autre, et une suppression attend ceux en cours (sinon la
/// session reviendrait).
public actor FileSessionFiles: SessionFiles {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// Le dossier de l'app Flutter, repris tel quel (Application Support/sessions).
    public static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("sessions", isDirectory: true)
    }

    private func fileURL(_ id: String) -> URL {
        directory.appendingPathComponent("\(id).json")
    }

    public func loadAll() async -> [Data] {
        files().filter { SessionJSON.decode($0) != nil }
    }

    /// Les sessions décodées une seule fois (avant : une fois pour écarter les
    /// fichiers abîmés, une fois de plus sur le fil de l'appelant).
    public func loadObjects() async -> sending [[String: Any]] {
        files().compactMap(SessionJSON.decode)
    }

    /// Le contenu des fichiers `.json`, par ordre de nom.
    private func files() -> [Data] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: directory.path) else { return [] }
        var out: [Data] = []
        for name in names.sorted() where name.hasSuffix(".json") {
            // Fichier illisible : ignoré.
            guard let d = try? Data(contentsOf: directory.appendingPathComponent(name)) else { continue }
            out.append(d)
        }
        return out
    }

    public func save(_ id: String, _ json: Data) async {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            // Écrit à côté puis renommé : jamais de fichier à moitié écrit.
            try json.write(to: fileURL(id), options: .atomic)
        } catch {
            // Disque plein, dossier interdit : la session reste en mémoire.
        }
    }

    public func delete(_ id: String) async {
        try? FileManager.default.removeItem(at: fileURL(id))
    }
}

/// Les sessions dans les préférences (`session_ids` et `session_<id>`, en texte
/// JSON comme `Storage.writeJson` de l'app Flutter).
public final class DefaultsSessionFiles: SessionFiles, @unchecked Sendable {
    private let defaults: UserDefaults
    private let lock = NSLock()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private var ids: [String] {
        guard let raw = defaults.string(forKey: "session_ids"),
              let list = LooseJSON.object(raw) as? [Any] else { return [] }
        return list.compactMap { $0 as? String }
    }

    private func setIds(_ list: [String]) {
        defaults.set(LooseJSON.string(list), forKey: "session_ids")
    }

    public func loadAll() async -> [Data] {
        lock.withLock {
            ids.compactMap { id in
                guard let raw = defaults.string(forKey: "session_\(id)") else { return nil }
                let d = Data(raw.utf8)
                return SessionJSON.decode(d) == nil ? nil : d
            }
        }
    }

    public func save(_ id: String, _ json: Data) async {
        lock.withLock {
            defaults.set(String(decoding: json, as: UTF8.self), forKey: "session_\(id)")
            let list = ids
            if !list.contains(id) { setIds(list + [id]) }
        }
    }

    public func delete(_ id: String) async {
        lock.withLock {
            defaults.removeObject(forKey: "session_\(id)")
            setIds(ids.filter { $0 != id })
        }
    }
}

/// Les sessions en mémoire seulement (tests, aperçus).
public actor MemorySessionFiles: SessionFiles {
    private var order: [String] = []
    private var files: [String: Data] = [:]

    public init() {}

    public func loadAll() async -> [Data] { order.compactMap { files[$0] } }

    public func save(_ id: String, _ json: Data) async {
        if files[id] == nil { order.append(id) }
        files[id] = json
    }

    public func delete(_ id: String) async {
        files[id] = nil
        order.removeAll { $0 == id }
    }
}
