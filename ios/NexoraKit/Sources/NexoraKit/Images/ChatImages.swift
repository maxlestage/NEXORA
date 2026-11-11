import Foundation

/// Une image envoyée au modèle avec un message : ses octets en base64 et son type
/// MIME (`image/jpeg`, `image/png`…).
public struct LLMImage: Sendable, Hashable {
    public let base64: String
    public let mimeType: String

    public init(base64: String, mimeType: String = "image/jpeg") {
        self.base64 = base64
        self.mimeType = mimeType
    }

    public init(data: Data, mimeType: String? = nil) {
        base64 = data.base64EncodedString()
        self.mimeType = mimeType ?? ChatImageStore.mimeType(of: data)
    }

    /// `data:image/jpeg;base64,…` (format OpenAI).
    public var dataURL: String { "data:\(mimeType);base64,\(base64)" }

    /// La taille approximative des octets de l'image.
    public var byteCount: Int { base64.utf8.count * 3 / 4 }
}

/// Les images jointes aux conversations, enregistrées sur l'appareil
/// (Application Support/attachments) et référencées par leur nom de fichier dans
/// `ChatMessage.images`. Les écritures sont atomiques ; un nom suspect (chemin,
/// `..`) est refusé.
public struct ChatImageStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// Application Support/attachments.
    public static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("attachments", isDirectory: true)
    }

    /// Le dossier de l'app.
    public static let standard = ChatImageStore(directory: defaultDirectory())

    /// Un nom sûr : lettres, chiffres, `-`, `_` et `.`, sans `..` ni point en tête.
    public static func isSafeName(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= 120, !name.hasPrefix("."), !name.contains("..") else { return false }
        return name.unicodeScalars.allSatisfy { s in
            (s.value < 128) && (CharacterSet.alphanumerics.contains(s) || s == "-" || s == "_" || s == ".")
        }
    }

    /// Le fichier d'une image, ou `nil` si le nom n'est pas sûr.
    public func url(_ name: String) -> URL? {
        Self.isSafeName(name) ? directory.appendingPathComponent(name) : nil
    }

    /// Enregistre une image et rend son nom (`<id>.jpg`).
    @discardableResult
    public func save(_ data: Data) throws -> String {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = "\(newId())-\(UInt32.random(in: 0..<UInt32.max) % 46656).\(Self.fileExtension(of: data))"
        try data.write(to: directory.appendingPathComponent(name), options: .atomic)
        return name
    }

    public func load(_ name: String) -> Data? {
        url(name).flatMap { try? Data(contentsOf: $0) }
    }

    public func exists(_ name: String) -> Bool {
        url(name).map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    }

    /// L'image prête à envoyer au modèle.
    public func llmImage(_ name: String) -> LLMImage? {
        load(name).map { LLMImage(data: $0) }
    }

    /// Supprime des images (les noms inconnus sont ignorés).
    public func delete<S: Sequence>(_ names: S) where S.Element == String {
        for n in names {
            if let u = url(n) { try? FileManager.default.removeItem(at: u) }
        }
    }

    public func deleteAll() {
        try? FileManager.default.removeItem(at: directory)
    }

    /// La place prise sur l'appareil, en octets.
    public func sizeOnDisk() -> Int {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return files.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }

    /// Le type d'une image d'après ses premiers octets (JPEG par défaut).
    public static func mimeType(of data: Data) -> String {
        let b = [UInt8](data.prefix(12))
        if b.count >= 8 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47 { return "image/png" }
        if b.count >= 12 && b[0] == 0x52 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x46
            && b[8] == 0x57 && b[9] == 0x45 && b[10] == 0x42 && b[11] == 0x50 { return "image/webp" }
        if b.count >= 6 && b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46 { return "image/gif" }
        return "image/jpeg"
    }

    /// Des octets d'image reconnus (JPEG, PNG, WebP, GIF) ?
    public static func looksLikeImage(_ data: Data) -> Bool {
        let b = [UInt8](data.prefix(12))
        if b.count >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF { return true }
        return mimeType(of: data) != "image/jpeg"
    }

    public static func fileExtension(of data: Data) -> String {
        switch mimeType(of: data) {
        case "image/png": "png"
        case "image/webp": "webp"
        case "image/gif": "gif"
        default: "jpg"
        }
    }
}

/// Les règles des images dans le chat : combien on en joint, lesquelles partent au
/// modèle, et le repli quand le modèle ne les accepte pas.
public enum ChatImages {
    /// Images jointes à un message, au plus.
    public static let maxPerMessage = 4
    /// Images envoyées au modèle à chaque réponse, au plus (les plus récentes).
    public static let maxSent = 6
    /// Messages dont les images sont renvoyées, au plus (les plus récents).
    public static let maxSentMessages = 3
    /// Octets d'images envoyés à chaque réponse, au plus.
    public static let maxSentBytes = 15 * 1024 * 1024
    /// Côté le plus long d'une photo jointe (en pixels) et qualité JPEG.
    public static let maxSide = 1568
    public static let jpegQuality = 0.8

    /// Ajouté au message quand le modèle refuse les images.
    public static let refusedNote = "(image non prise en charge par ce modèle)"
    /// Le message affiché quand le modèle a refusé les images.
    public static let refusedNotice = "Ce modèle ne prend pas les images : la réponse a été faite sans elles. Choisissez un modèle « vision » (GPT-4o, Claude, Gemini, Llava…) pour qu'il les voie."

    /// La note d'un message dont les images ne sont pas renvoyées.
    public static func notSentNote(_ n: Int) -> String {
        n > 1 ? "(\(n) images jointes ici, non renvoyées)" : "(image jointe ici, non renvoyée)"
    }

    /// Le texte d'un message, avec une note en plus.
    static func appending(_ content: String, _ note: String) -> String {
        content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? note : content + "\n\n" + note
    }

    /// Ajoute à l'historique (rendu par `ChatLogic.recentHistory`) les images des
    /// derniers messages de l'utilisateur, dans la limite du budget. Les messages
    /// plus anciens gardent une note à la place de leurs images.
    public static func attach(
        _ history: [LLMMessage], from messages: [ChatMessage], dropped: Int,
        load: (String) -> LLMImage?
    ) -> [LLMMessage] {
        let usable = messages.filter(ChatLogic.isUsable)
        guard usable.count == dropped + history.count else { return history }
        var out = history
        var sentImages = 0
        var sentMessages = 0
        var bytes = 0
        for i in stride(from: history.count - 1, through: 0, by: -1) {
            let m = usable[dropped + i]
            guard m.role == .user, !m.images.isEmpty else { continue }
            var images: [LLMImage] = []
            if sentMessages < maxSentMessages {
                for name in m.images.prefix(maxPerMessage) where sentImages < maxSent {
                    guard let img = load(name) else { continue }
                    if bytes + img.byteCount > maxSentBytes { break }
                    images.append(img)
                    bytes += img.byteCount
                    sentImages += 1
                }
            }
            if images.isEmpty {
                out[i] = LLMMessage(out[i].role, appending(out[i].content, notSentNote(m.images.count)))
            } else {
                sentMessages += 1
                out[i] = LLMMessage(out[i].role, out[i].content, images: images)
            }
        }
        return out
    }

    public static func hasImages(_ messages: [LLMMessage]) -> Bool {
        messages.contains { !$0.images.isEmpty }
    }

    /// Les mêmes messages sans leurs images, avec une note à leur place.
    public static func withoutImages(_ messages: [LLMMessage], note: String = refusedNote) -> [LLMMessage] {
        messages.map { m in
            m.images.isEmpty ? m : LLMMessage(m.role, appending(m.content, note))
        }
    }

    /// Le fournisseur refuse-t-il les images (modèle sans vision) ? Une erreur 400
    /// (ou 415, 422) qui parle d'image, de vision ou de multimodal.
    public static func refusesImages(status: Int, body: String) -> Bool {
        guard [400, 415, 422].contains(status) else { return false }
        let t = body.lowercased()
        return ["image", "vision", "multimodal", "multi-modal", "modalit", "must be a string", "content type"]
            .contains { t.contains($0) }
    }
}

/// Le modèle voit-il les images ? Déduit de son nom (les catalogues ne le disent
/// pas) : on avertit seulement, l'envoi reste possible.
public enum ModelVision {
    static let yes = [
        "gpt-4o", "gpt-4.1", "gpt-4.5", "gpt-4-turbo", "gpt-4-vision", "gpt-5", "chatgpt-4o",
        "claude", "gemini", "gemma-3", "gemma3", "llava", "bakllava", "moondream", "minicpm-v", "pixtral",
        "qwen-vl", "qwen2-vl", "qwen2.5-vl", "qwen3-vl", "qwen-omni", "qvq", "-vl", "vl-", "vision",
        "llama-4", "llama4", "llama-3.2-11b", "llama-3.2-90b", "grok-4", "grok-2-vision", "mistral-small-3",
        "mistral-medium", "mistral-large-3", "internvl", "phi-4-multimodal", "phi-3.5-vision", "kimi-vl",
        "multimodal", "omni", "glm-4v", "glm-4.5v", "step-1v", "nova-pro", "nova-lite",
    ]
    static let no = ["o1-mini", "o3-mini", "gpt-oss", "embed", "whisper", "tts", "codestral", "devstral"]

    /// Vrai si le modèle voit probablement les images.
    public static func likelySees(providerId: String, model: String) -> Bool {
        let m = model.lowercased()
        if no.contains(where: { m.contains($0) }) { return false }
        // Pollinations : `openai` et ses variantes sont des modèles GPT qui voient.
        if providerId == "pollinations" && (m.hasPrefix("openai") || m.hasPrefix("gemini") || m.hasPrefix("claude")) { return true }
        // Les modèles de raisonnement o1, o3, o4 d'OpenAI (sauf les « mini » du début).
        let base = m.split(separator: "/").last.map(String.init) ?? m
        if ["o1", "o3", "o4"].contains(where: { base == $0 || base.hasPrefix($0 + "-") }) { return true }
        return yes.contains { m.contains($0) }
    }
}
