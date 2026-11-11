import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Le moteur qui crée les images.
public enum ImageGenEngine: String, Sendable, CaseIterable, Codable {
    /// OpenAI si une clé OpenAI est enregistrée, sinon Pollinations.
    case auto
    /// Pollinations : gratuit, sans clé (modèle Flux).
    case pollinations
    /// OpenAI Images (`gpt-image-1`), avec votre clé OpenAI.
    case openai

    public var label: String {
        switch self {
        case .auto: "Automatique"
        case .pollinations: "Pollinations (gratuit)"
        case .openai: "OpenAI (gpt-image-1)"
        }
    }

    public var detail: String {
        switch self {
        case .auto: "OpenAI si une clé OpenAI est enregistrée, sinon Pollinations."
        case .pollinations: "Gratuit et sans clé (modèle Flux). Une image à la fois par demande, en parallèle."
        case .openai: "Meilleure qualité, payant (de ≈ 0,01 $ à ≈ 0,25 $ par image selon la qualité choisie), avec votre clé OpenAI."
        }
    }

    /// Le moteur réellement utilisé.
    public func resolved(hasOpenAIKey: Bool) -> ImageGenEngine {
        self == .auto ? (hasOpenAIKey ? .openai : .pollinations) : self
    }

    public static func named(_ s: String?) -> ImageGenEngine { s.flatMap(ImageGenEngine.init(rawValue:)) ?? .auto }
}

/// La qualité des images OpenAI (`quality` de gpt-image-1) : plus elle est haute,
/// plus l'image est soignée… et chère. Pollinations l'ignore (toujours gratuit).
public enum ImageGenQuality: String, Sendable, CaseIterable, Codable {
    case low, medium, high, auto

    public var label: String {
        switch self {
        case .low: "Basse"
        case .medium: "Moyenne"
        case .high: "Haute"
        case .auto: "Automatique"
        }
    }

    /// Le prix d'une image d'après la grille d'OpenAI (gpt-image-1), en dollars ;
    /// `nil` en automatique (OpenAI choisit la qualité, donc le prix).
    public func perImage(_ shape: ImageGenShape) -> Double? {
        let square = shape == .square
        switch self {
        case .low: return square ? 0.011 : 0.016
        case .medium: return square ? 0.042 : 0.063
        case .high: return square ? 0.167 : 0.25
        case .auto: return nil
        }
    }

    /// Le libellé avec son prix : « Haute · ≈ 0,17 $ / image ».
    public func priced(_ shape: ImageGenShape) -> String {
        guard let p = perImage(shape) else { return "\(label) · OpenAI choisit (jusqu'à ≈ \(ImageGenQuality.dollars(ImageGenQuality.high.perImage(shape) ?? 0)) / image)" }
        return "\(label) · ≈ \(ImageGenQuality.dollars(p)) / image"
    }

    static func dollars(_ v: Double) -> String {
        String(format: v < 0.1 ? "%.3f" : "%.2f", v).replacingOccurrences(of: ".", with: ",") + " $"
    }

    public static func named(_ s: String?) -> ImageGenQuality { s.flatMap(ImageGenQuality.init(rawValue:)) ?? .medium }
}

/// Le format des images créées.
public enum ImageGenShape: String, Sendable, CaseIterable, Codable {
    case square, portrait, landscape

    public var label: String {
        switch self {
        case .square: "Carré"
        case .portrait: "Portrait"
        case .landscape: "Paysage"
        }
    }

    public var width: Int { self == .landscape ? 1536 : 1024 }
    public var height: Int { self == .portrait ? 1536 : 1024 }
    /// La taille au format OpenAI (`1024x1536`).
    public var size: String { "\(width)x\(height)" }

    public static func named(_ s: String?) -> ImageGenShape { s.flatMap(ImageGenShape.init(rawValue:)) ?? .square }
}

/// `/image [nombre] description` tapé dans le chat.
public struct ImageGenCommand: Sendable, Hashable {
    public let count: Int
    public let prompt: String

    public static let maxCount = 4

    public init(count: Int, prompt: String) {
        self.count = min(max(count, 1), Self.maxCount)
        self.prompt = prompt
    }

    /// La commande, ou `nil` si le texte ne commence pas par `/image` (ou
    /// `/images`). La description peut être vide (à signaler à l'utilisateur).
    public static func parse(_ text: String) -> ImageGenCommand? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let r = t.range(of: #"^/images?(?=\s|$)"#, options: [.regularExpression, .caseInsensitive]) else { return nil }
        var rest = t[r.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        var count = 1
        if let n = rest.range(of: #"^\d{1,2}(?=\s|$)"#, options: .regularExpression) {
            count = Int(rest[n]) ?? 1
            rest = rest[n.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        } else if let n = rest.range(of: #"^[x×]\s?(\d)(?=\s|$)"#, options: .regularExpression) {
            count = Int(rest[n].filter(\.isNumber)) ?? 1
            rest = rest[n.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ImageGenCommand(count: count, prompt: rest)
    }

    /// Le message quand la description manque.
    public static let missingPrompt = "Écrivez une description après /image (ex. : /image 3 un chat astronaute)."

    /// La proposition de la barre de saisie pour `/`, `/i`, `/ima`…
    public static func suggestion(for text: String) -> ChatSuggestion? {
        guard text.hasPrefix("/"), !text.contains(" "), !text.contains("\n") else { return nil }
        let q = text.dropFirst().lowercased()
        guard "image".hasPrefix(q) || q == "images" else { return nil }
        return ChatSuggestion(insert: "/image ", title: "/image [nombre] description", subtitle: "Créer 1 à 4 images à partir d'un texte")
    }

    /// Le texte de la réponse « images créées ».
    public static func caption(prompt: String, made: Int, requested: Int) -> String {
        let p = prompt.count > 300 ? String(prompt.prefix(300)) + "…" : prompt
        var s = made > 1 ? "\(made) images créées : « \(p) »" : "Image créée : « \(p) »"
        let missing = requested - made
        if missing > 0 {
            s += missing > 1 ? "\n\n(\(missing) images n'ont pas pu être créées.)" : "\n\n(1 image n'a pas pu être créée.)"
        }
        return s
    }
}

/// Une image créée.
public struct GeneratedImage: Sendable, Hashable {
    public let data: Data
    public let mimeType: String

    public init(data: Data, mimeType: String? = nil) {
        self.data = data
        self.mimeType = mimeType ?? ChatImageStore.mimeType(of: data)
    }
}

/// Le résultat d'une demande d'images.
public struct ImageGenResult: Sendable {
    public let images: [GeneratedImage]
    public let engine: ImageGenEngine
    /// `pollinations::flux` ou `openai::gpt-image-1`.
    public let modelKey: String
    /// En dollars (OpenAI) ; 0 pour Pollinations (gratuit).
    public let cost: Double?
    public let requested: Int
    /// Un avis (ex. : OpenAI a refusé, Pollinations a pris le relais).
    public var note: String?

    public init(images: [GeneratedImage], engine: ImageGenEngine, modelKey: String, cost: Double?, requested: Int, note: String? = nil) {
        self.images = images
        self.engine = engine
        self.modelKey = modelKey
        self.cost = cost
        self.requested = requested
        self.note = note
    }

    public var failed: Int { max(0, requested - images.count) }
}

/// Crée des images à partir d'un texte : Pollinations (gratuit, une requête par
/// image, en parallèle, avec un nouvel essai) ou OpenAI Images (`gpt-image-1`).
public struct ImageGenClient: Sendable {
    public let transport: HTTPTransport
    /// Attente avant un nouvel essai, selon la tentative (1, 2…).
    public let retryDelay: @Sendable (Int) -> Duration
    /// Délai d'une requête, en secondes.
    public let timeout: TimeInterval

    public static let pollinationsModel = "flux"
    public static let openAIModel = "gpt-image-1"
    public static let openAIBase = "https://api.openai.com/v1"
    /// Pollinations : essais par image, au plus.
    public static let pollinationsAttempts = 3
    public static let noOpenAIKey = "Le moteur OpenAI est choisi, mais aucune clé OpenAI n'est enregistrée (Fournisseurs → OpenAI). Ou choisissez Pollinations (gratuit) dans Réglages → Images."

    public init(
        transport: HTTPTransport = URLSessionTransport(),
        retryDelay: @escaping @Sendable (Int) -> Duration = { .seconds(3 * $0) },
        timeout: TimeInterval = 180
    ) {
        self.transport = transport
        self.retryDelay = retryDelay
        self.timeout = timeout
    }

    /// Lettres et chiffres ASCII, `-._~` : tout le reste est encodé (espaces,
    /// accents, `/`, `?`…).
    static let pathSafe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")

    /// L'adresse d'une image Pollinations.
    public static func pollinationsURL(prompt: String, width: Int, height: Int, seed: Int, model: String = pollinationsModel) -> URL? {
        let clean = prompt.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let text = clean.count > 1500 ? String(clean.prefix(1500)) : clean
        guard let encoded = text.addingPercentEncoding(withAllowedCharacters: pathSafe) else { return nil }
        return URL(string: "https://image.pollinations.ai/prompt/\(encoded)?width=\(width)&height=\(height)&seed=\(seed)&nologo=true&model=\(model)")
    }

    /// Crée `count` images (1 à 4). `openAIKey` : la clé OpenAI enregistrée, s'il y
    /// en a une. En automatique, si OpenAI refuse (clé, crédit, vérification),
    /// Pollinations prend le relais.
    public func generate(
        prompt: String, count: Int, shape: ImageGenShape, engine: ImageGenEngine,
        openAIKey: String?, openAIBase: String = ImageGenClient.openAIBase, quality: ImageGenQuality = .medium
    ) async throws -> ImageGenResult {
        let n = min(max(count, 1), ImageGenCommand.maxCount)
        let p = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !p.isEmpty else { throw LLMError(ImageGenCommand.missingPrompt) }
        let key = (openAIKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if engine == .openai && key.isEmpty { throw LLMError(Self.noOpenAIKey) }
        switch engine.resolved(hasOpenAIKey: !key.isEmpty) {
        case .openai:
            do {
                return try await openAI(prompt: p, count: n, shape: shape, apiKey: key, base: openAIBase, quality: quality)
            } catch let e as LLMError where engine == .auto && !e.transient && !(e.status.map { $0 >= 500 } ?? false) {
                // Automatique : OpenAI refuse, on passe à Pollinations (gratuit).
                var r = try await pollinations(prompt: p, count: n, shape: shape)
                r.note = "OpenAI a refusé (\(e.message)) : images créées avec Pollinations."
                return r
            }
        case .pollinations, .auto:
            return try await pollinations(prompt: p, count: n, shape: shape)
        }
    }

    // MARK: - Pollinations

    public func pollinations(prompt: String, count: Int, shape: ImageGenShape, seed: Int? = nil) async throws -> ImageGenResult {
        let base = seed ?? Int.random(in: 0..<1_000_000_000)
        let urls = (0..<count).map { Self.pollinationsURL(prompt: prompt, width: shape.width, height: shape.height, seed: base + $0 * 7919) }
        let results = await withTaskGroup(of: (Int, Result<GeneratedImage, LLMError>).self) { group in
            for (i, url) in urls.enumerated() {
                group.addTask {
                    guard let url else { return (i, .failure(LLMError("Description illisible pour Pollinations."))) }
                    return (i, await self.pollinationsImage(url))
                }
            }
            var out: [(Int, Result<GeneratedImage, LLMError>)] = []
            for await r in group { out.append(r) }
            return out.sorted { $0.0 < $1.0 }.map(\.1)
        }
        let images = results.compactMap { try? $0.get() }
        if images.isEmpty {
            let errors = results.compactMap { r -> LLMError? in
                if case .failure(let e) = r { return e }
                return nil
            }
            throw errors.first ?? LLMError("Pollinations n'a renvoyé aucune image.")
        }
        return ImageGenResult(
            images: images, engine: .pollinations, modelKey: "pollinations::\(Self.pollinationsModel)",
            cost: 0, requested: count
        )
    }

    /// Une image Pollinations, avec de nouveaux essais (saturation, coupure).
    func pollinationsImage(_ url: URL) async -> Result<GeneratedImage, LLMError> {
        var last = LLMError("Pollinations n'a renvoyé aucune image.")
        for attempt in 1...Self.pollinationsAttempts {
            if Task.isCancelled { return .failure(LLMError("Annulé.")) }
            var r = URLRequest(url: url)
            r.httpMethod = "GET"
            r.timeoutInterval = timeout
            r.setValue("image/*", forHTTPHeaderField: "accept")
            do {
                let (head, data) = try await transport.data(r)
                if head.ok && ChatImageStore.looksLikeImage(data) {
                    return .success(GeneratedImage(data: data, mimeType: head.headers["content-type"].flatMap { $0.hasPrefix("image/") ? $0.components(separatedBy: ";")[0] : nil }))
                }
                last = Self.pollinationsError(head.status, data)
                // Une demande refusée (contenu, adresse) ne passera pas mieux ensuite.
                if !LLMClient.retryStatuses.contains(head.status) && head.ok == false && head.status != 0 {
                    return .failure(last)
                }
            } catch is CancellationError {
                return .failure(LLMError("Annulé."))
            } catch {
                last = LLMError("Impossible de joindre Pollinations. Détail : \(error.localizedDescription)", transient: true)
            }
            if attempt < Self.pollinationsAttempts {
                try? await Task.sleep(for: retryDelay(attempt))
            }
        }
        return .failure(last)
    }

    static func pollinationsError(_ status: Int, _ data: Data) -> LLMError {
        let body = errorFromBody(String(decoding: data.prefix(2000), as: UTF8.self))
        switch status {
        case 200..<300:
            return LLMError("Pollinations n'a pas renvoyé d'image. Réessayez.", status: status, transient: true)
        case 429:
            return LLMError("Pollinations est saturé (trop de demandes à la fois). Réessayez dans un instant, ou demandez moins d'images.", status: 429)
        case 500...599:
            return LLMError("Pollinations ne répond pas pour le moment (HTTP \(status)). Réessayez plus tard.", status: status, transient: true)
        default:
            return LLMError("Pollinations a refusé la demande : \(body)", status: status)
        }
    }

    // MARK: - OpenAI

    public func openAI(prompt: String, count: Int, shape: ImageGenShape, apiKey: String, base: String = ImageGenClient.openAIBase, quality: ImageGenQuality = .medium) async throws -> ImageGenResult {
        let root = base.hasSuffix("/") ? String(base.dropLast()) : base
        guard let url = URL(string: root + "/images/generations") else { throw LLMError("Adresse invalide : \(base)") }
        var r = URLRequest(url: url)
        r.httpMethod = "POST"
        r.timeoutInterval = timeout
        r.setValue("application/json", forHTTPHeaderField: "content-type")
        r.setValue("Bearer \(apiKey)", forHTTPHeaderField: "authorization")
        let body: [String: Any] = [
            "model": Self.openAIModel, "prompt": prompt, "n": count, "size": shape.size, "quality": quality.rawValue,
        ]
        r.httpBody = try? JSONSerialization.data(withJSONObject: body)
        let head: HTTPHead
        let data: Data
        do {
            (head, data) = try await transport.data(r)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw LLMError("Impossible de joindre OpenAI. Détail : \(error.localizedDescription)", transient: true)
        }
        let text = String(decoding: data, as: UTF8.self)
        if !head.ok { throw Self.openAIError(head.status, text) }
        guard let j = LooseJSON.object(text) as? [String: Any], let list = j["data"] as? [Any] else {
            throw LLMError("Réponse d'OpenAI illisible.", status: head.status)
        }
        var images: [GeneratedImage] = []
        for case let item as [String: Any] in list {
            if let b64 = item["b64_json"] as? String, let d = Data(base64Encoded: b64, options: .ignoreUnknownCharacters) {
                images.append(GeneratedImage(data: d))
            } else if let link = item["url"] as? String, let u = URL(string: link),
                      let got = try? await transport.data(URLRequest(url: u)), got.0.ok {
                images.append(GeneratedImage(data: got.1))
            }
        }
        if images.isEmpty { throw LLMError("OpenAI n'a renvoyé aucune image.", status: head.status) }
        return ImageGenResult(
            images: images, engine: .openai, modelKey: "openai::\(Self.openAIModel)",
            cost: Self.openAICost(usage: j["usage"] as? [String: Any], count: images.count, shape: shape, quality: quality),
            requested: count
        )
    }

    /// Le coût d'une demande OpenAI : d'après les tokens rendus (texte 5 $, image
    /// 10 $ en entrée, 40 $ en sortie, par million), sinon le prix moyen d'une image
    /// selon la qualité choisie (grille d'OpenAI ; moyenne en automatique).
    public static func openAICost(usage: [String: Any]?, count: Int, shape: ImageGenShape, quality: ImageGenQuality = .medium) -> Double {
        if let u = usage {
            let input = Double(int(u["input_tokens"]))
            let output = Double(int(u["output_tokens"]))
            if input + output > 0 {
                let details = u["input_tokens_details"] as? [String: Any]
                let imageIn = Double(int(details?["image_tokens"]))
                let textIn = details == nil ? input : Double(int(details?["text_tokens"]))
                return (textIn * 5 + imageIn * 10 + output * 40) / 1e6
            }
        }
        return Double(count) * (quality.perImage(shape) ?? ImageGenQuality.medium.perImage(shape) ?? 0.042)
    }

    static func openAIError(_ status: Int, _ body: String) -> LLMError {
        let msg = errorFromBody(body)
        let low = msg.lowercased()
        if status == 401 {
            return LLMError("Clé OpenAI refusée : vérifiez-la dans Fournisseurs → OpenAI. (\(msg))", status: status)
        }
        if low.contains("verif") {
            return LLMError("OpenAI demande de vérifier votre organisation pour gpt-image-1 (platform.openai.com → Settings → Organization → Verify). En attendant, choisissez Pollinations dans Réglages → Images. (\(msg))", status: status)
        }
        if low.contains("safety") || low.contains("moderation") || low.contains("content_policy") {
            return LLMError("OpenAI a refusé cette description (règles de contenu). Reformulez-la. (\(msg))", status: status)
        }
        return LLMError(msg, status: status)
    }
}
