import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Un message envoyé au modèle.
public struct LLMMessage: Sendable, Hashable {
    /// `user`, `assistant` ou `system`.
    public let role: String
    public let content: String
    /// Les images jointes (photos de l'utilisateur), envoyées au format de chaque
    /// protocole. Sans image, le message part exactement comme avant (texte seul).
    public var images: [LLMImage]

    public init(_ role: String, _ content: String, images: [LLMImage] = []) {
        self.role = role
        self.content = content
        self.images = images
    }

    var json: [String: Any] { ["role": role, "content": content] }

    /// Le message au format d'un protocole (OpenAI ou Ollama ; Anthropic : voir
    /// `LLMClient.alternate`).
    func payload(_ kind: ApiKind) -> [String: Any] {
        if images.isEmpty { return json }
        switch kind {
        case .ollama:
            return ["role": role, "content": content, "images": images.map(\.base64)]
        case .openai, .anthropic:
            var parts: [[String: Any]] = []
            if !content.isEmpty { parts.append(["type": "text", "text": content]) }
            for i in images {
                parts.append(["type": "image_url", "image_url": ["url": i.dataURL]])
            }
            return ["role": role, "content": parts]
        }
    }
}

/// Options d'un appel.
public struct LLMOptions: Sendable {
    public var temperature: Double?
    public var maxTokens: Int
    /// Le niveau de réflexion, traduit pour chaque fournisseur.
    public var level: ThinkLevel?

    public init(temperature: Double? = nil, maxTokens: Int = 8192, level: ThinkLevel? = nil) {
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.level = level
    }
}

/// Parle à tous les fournisseurs : OpenAI et compatibles, Ollama, Anthropic.
public struct LLMClient: Sendable {
    public let transport: HTTPTransport
    /// Attente avant de réessayer, selon la tentative (1, 2) et `Retry-After`.
    public let retryDelay: @Sendable (Int, Int?) -> Duration
    /// Une réponse en flux qui n'envoie plus rien pendant ce temps est coupée.
    public let idleTimeout: Duration

    /// Le même délai quand le modèle réfléchit (niveau de réflexion activé).
    public static let reasoningIdleTimeout: Duration = .seconds(300)
    /// Codes pour lesquels on réessaie tout seul, avant le début de la réponse.
    public static let retryStatuses: Set<Int> = [408, 429, 500, 502, 503, 504, 529]
    public static let maxRetries = 2
    /// Ces fournisseurs envoient le décompte des tokens à la fin du flux si on le
    /// demande ; les autres l'envoient d'eux-mêmes ou il est estimé.
    static let streamUsage: Set<String> = ["openai", "deepseek", "together", "xai"]

    public init(
        transport: HTTPTransport = URLSessionTransport(),
        retryDelay: @escaping @Sendable (Int, Int?) -> Duration = LLMClient.defaultRetryDelay,
        idleTimeout: Duration = .seconds(90)
    ) {
        self.transport = transport
        self.retryDelay = retryDelay
        self.idleTimeout = idleTimeout
    }

    public static let defaultRetryDelay: @Sendable (Int, Int?) -> Duration = { attempt, retryAfter in
        if let r = retryAfter, r >= 0 { return .seconds(min(max(r, 1), 20)) }
        return .seconds(2 * attempt)
    }

    static func trim(_ url: String) -> String {
        url.hasSuffix("/") ? String(url.dropLast()) : url
    }

    func headers(_ p: ProviderDef, key: String?) -> [String: String] {
        var h = ["content-type": "application/json"]
        for (k, v) in p.extraHeaders { h[k] = v }
        if let key, !key.isEmpty {
            if p.kind == .anthropic { h["x-api-key"] = key } else { h["authorization"] = "Bearer \(key)" }
        }
        if p.kind == .anthropic { h["anthropic-version"] = "2023-06-01" }
        return h
    }

    func chatURL(_ p: ProviderDef) -> URL? {
        let base = Self.trim(p.baseUrl)
        if let path = p.chatPath { return URL(string: base + path) }
        switch p.kind {
        case .openai: return URL(string: base + "/chat/completions")
        case .ollama: return URL(string: base + "/api/chat")
        case .anthropic: return URL(string: base + "/messages")
        }
    }

    /// Le corps JSON de la requête de chat.
    func body(
        _ p: ProviderDef, model: String, messages: [LLMMessage], system: String?,
        options o: LLMOptions, stream: Bool, reasoning: Bool = true
    ) -> [String: Any] {
        let extra = reasoning ? reasoningParams(p, model: model, level: o.level) : [:]
        var b: [String: Any]
        switch p.kind {
        case .anthropic:
            b = [
                "model": model,
                "max_tokens": max(o.maxTokens, 1024),
                "messages": Self.alternate(messages),
                "stream": stream,
            ]
            // Cache des prompts : l'historique déjà envoyé est relu plus vite (et moins
            // cher) au tour suivant. Retiré si le serveur le refuse.
            if reasoning { b["cache_control"] = ["type": "ephemeral"] }
            if let system, !system.isEmpty { b["system"] = system }
        case .ollama:
            var msgs: [[String: Any]] = []
            if let system, !system.isEmpty { msgs.append(["role": "system", "content": system]) }
            msgs += messages.map { $0.payload(.ollama) }
            b = ["model": model, "messages": msgs, "stream": stream]
            if let t = o.temperature { b["options"] = ["temperature": t] }
        case .openai:
            var msgs: [[String: Any]] = []
            if let system, !system.isEmpty { msgs.append(["role": "system", "content": system]) }
            msgs += messages.map { $0.payload(.openai) }
            b = ["model": model, "messages": msgs, "stream": stream]
            if let t = o.temperature { b["temperature"] = t }
            if stream && Self.streamUsage.contains(p.id) { b["stream_options"] = ["include_usage": true] }
            if p.id == "openrouter" { b["usage"] = ["include": true] }
            // Pollinations garde en cache la réponse d'une requête identique : sans
            // graine nouvelle, « Régénérer » rejouerait la même réponse.
            if p.id == "pollinations" {
                b["seed"] = Int.random(in: 0..<(1 << 31))
                b["private"] = true
            }
        }
        for (k, v) in extra { b[k] = v }
        return b
    }

    /// L'API Messages veut des tours alternés qui commencent par l'utilisateur.
    /// Les images partent en blocs `image` (source base64) avant le texte ; sans
    /// image, `content` reste un simple texte.
    static func alternate(_ messages: [LLMMessage]) -> [[String: Any]] {
        var turns: [(role: String, text: String, images: [LLMImage])] = []
        for m in messages where m.role != "system" {
            let blank = m.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if blank && m.images.isEmpty { continue }
            let text = blank ? "" : m.content
            if let last = turns.last, last.role == m.role {
                let joined = last.text.isEmpty ? text : text.isEmpty ? last.text : last.text + "\n\n" + text
                turns[turns.count - 1] = (m.role, joined, last.images + m.images)
            } else {
                turns.append((m.role, text, m.images))
            }
        }
        var out: [[String: Any]] = turns.map { t in
            if t.images.isEmpty { return ["role": t.role, "content": t.text] }
            var blocks: [[String: Any]] = t.images.map { i in
                ["type": "image", "source": ["type": "base64", "media_type": i.mimeType, "data": i.base64]]
            }
            if !t.text.isEmpty { blocks.append(["type": "text", "text": t.text]) }
            return ["role": t.role, "content": blocks]
        }
        if let first = out.first, first["role"] as? String != "user" {
            out.insert(["role": "user", "content": "(début de la conversation)"], at: 0)
        }
        return out
    }

    func request(_ url: URL, method: String, headers: [String: String], body: [String: Any]?, timeout: TimeInterval) -> URLRequest {
        var r = URLRequest(url: url)
        r.httpMethod = method
        r.timeoutInterval = timeout
        for (k, v) in headers { r.setValue(v, forHTTPHeaderField: k) }
        if let body { r.httpBody = try? JSONSerialization.data(withJSONObject: body) }
        return r
    }

    func networkHint(_ p: ProviderDef, _ e: Error) -> String {
        let base = "Impossible de joindre \(p.name) (\(p.baseUrl))."
        if p.local {
            return "\(base) Le serveur tourne-t-il, sur le même Wi-Fi, en écoute sur le réseau (OLLAMA_HOST=0.0.0.0) ? Détail : \(e.localizedDescription)"
        }
        return "\(base) Détail : \(e.localizedDescription)"
    }

    /// La réponse du modèle, morceau par morceau. Annuler la tâche qui lit le flux
    /// coupe la connexion.
    public func stream(
        provider: ProviderDef, apiKey: String?, model: String, messages: [LLMMessage],
        system: String? = nil, options: LLMOptions = LLMOptions(),
        onHeaders: (@Sendable (HTTPHead) -> Void)? = nil
    ) -> AsyncThrowingStream<ChatDelta, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                await run(
                    provider: provider, apiKey: apiKey, model: model, messages: messages,
                    system: system, options: options, onHeaders: onHeaders, out: continuation
                )
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func run(
        provider: ProviderDef, apiKey: String?, model: String, messages: [LLMMessage],
        system: String?, options: LLMOptions, onHeaders: (@Sendable (HTTPHead) -> Void)?,
        out: AsyncThrowingStream<ChatDelta, Error>.Continuation
    ) async {
        guard let url = chatURL(provider) else {
            out.finish(throwing: LLMError("Adresse invalide : \(provider.baseUrl)"))
            return
        }
        let thinks = !reasoningParams(provider, model: model, level: options.level).isEmpty
        let limit = thinks && idleTimeout < Self.reasoningIdleTimeout ? Self.reasoningIdleTimeout : idleTimeout
        let seconds = Double(limit.components.seconds)
        // Les messages envoyés : sans leurs images si le modèle les refuse.
        var sent = messages
        var imagesDropped = false
        func make(_ reasoning: Bool) -> URLRequest {
            request(
                url, method: "POST", headers: headers(provider, key: apiKey),
                body: body(provider, model: model, messages: sent, system: system, options: options, stream: true, reasoning: reasoning),
                timeout: max(60, seconds)
            )
        }
        var head: HTTPHead
        var lines: AsyncThrowingStream<String, Error>
        do {
            (head, lines) = try await transport.lines(make(true))
            var reasoning = true
            var refusalChecked = false
            while head.status == 400 || head.status == 422 || head.status == 415 {
                // Le modèle ne voit pas les images : on réessaie une fois sans elles,
                // avec une note à leur place.
                if !imagesDropped && !refusalChecked && ChatImages.hasImages(sent) {
                    refusalChecked = true
                    let text = await lines.joined()
                    if ChatImages.refusesImages(status: head.status, body: text) {
                        imagesDropped = true
                        sent = ChatImages.withoutImages(sent)
                        (head, lines) = try await transport.lines(make(reasoning))
                        continue
                    }
                    lines = AsyncThrowingStream { c in
                        c.yield(text)
                        c.finish()
                    }
                }
                // Le fournisseur refuse le réglage de réflexion : on réessaie sans.
                if reasoning && head.status != 415 && (provider.kind == .anthropic || thinks) {
                    reasoning = false
                    refusalChecked = false
                    (head, lines) = try await transport.lines(make(false))
                    continue
                }
                break
            }
            // Fournisseur saturé ou limite de débit : on réessaie un peu plus tard.
            var attempt = 1
            while attempt <= Self.maxRetries && Self.retryStatuses.contains(head.status) {
                onHeaders?(head)
                // Quota ou crédit épuisé (pas une simple limite de débit) : réessayer
                // ne sert à rien, on rend l'erreur tout de suite (l'appelant peut
                // passer à un autre modèle).
                if head.status == 429 {
                    let text = await lines.joined()
                    let e = LLMError(errorFromBody(text), status: head.status)
                    if e.quotaExhausted {
                        out.finish(throwing: e)
                        return
                    }
                }
                let after = head.headers["retry-after"].flatMap { Int($0) }
                try await Task.sleep(for: retryDelay(attempt, after))
                (head, lines) = try await transport.lines(make(reasoning))
                attempt += 1
            }
        } catch is CancellationError {
            out.finish()
            return
        } catch {
            if Task.isCancelled { out.finish(); return }
            out.finish(throwing: LLMError(networkHint(provider, error), transient: true))
            return
        }
        onHeaders?(head)
        if !head.ok {
            let text = await lines.joined()
            out.finish(throwing: LLMError(errorFromBody(text), status: head.status))
            return
        }
        if imagesDropped { out.yield(ChatDelta(notice: ChatImages.refusedNotice)) }
        // Certains serveurs ignorent `stream: true` et répondent en un seul JSON.
        let whole = (head.headers["content-type"] ?? "").contains("application/json") && provider.kind != .ollama
        if whole {
            var splitter = ThinkSplitter()
            var tools = ToolCallCollector()
            let bodyText = await lines.joined()
            var text = Self.wholeText(provider, bodyText)
            var usage: TokenUsage?
            if let j = LooseJSON.object(bodyText) as? [String: Any] {
                usage = TokenUsage.from(j["usage"])
                if let msg = ((j["choices"] as? [Any])?.first as? [String: Any])?["message"] as? [String: Any],
                   let calls = msg["tool_calls"] {
                    tools.add(ChatDelta(toolCalls: toolCallParts(calls)))
                    text += tools.render() ?? ""
                }
            }
            let d = splitter.feed(ChatDelta(text: text, usage: usage))
            if !d.isEmpty { out.yield(d) }
            let rest = splitter.flush()
            if !rest.isEmpty { out.yield(rest) }
            if let reason = Self.wholeStop(bodyText) { out.yield(ChatDelta(stop: reason)) }
            out.finish()
            return
        }

        // Le chien de garde : une réponse muette trop longtemps est coupée.
        let lastActivity = Locked(ContinuousClock.now)
        let timedOut = Locked(false)
        let reader = Task {
            var splitter = ThinkSplitter()
            var tools = ToolCallCollector()
            var parser = StreamLineParser(kind: provider.kind)
            var stop: String?
            var ended = false
            do {
                for try await line in lines {
                    lastActivity.set(.now)
                    do {
                        guard let d = try parser.parse(line) else { continue }
                        if let s = d.stop { stop = s }
                        if d.done { ended = true }
                        tools.add(d)
                        let o = splitter.feed(d)
                        if !o.isEmpty { out.yield(o) }
                        // Fin annoncée par le fournisseur : on n'attend pas qu'il ferme.
                        if d.done { break }
                    } catch let e as LLMError {
                        out.finish(throwing: e)
                        return
                    }
                }
            } catch {
                if timedOut.get() || Task.isCancelled {
                    // Géré par le chien de garde, ou arrêté par l'utilisateur.
                } else {
                    let rest = splitter.flush()
                    if !rest.isEmpty { out.yield(rest) }
                    out.finish(throwing: LLMError(networkHint(provider, error), transient: true))
                    return
                }
            }
            let rest = splitter.flush()
            if !rest.isEmpty { out.yield(rest) }
            if timedOut.get() {
                out.finish(throwing: LLMError(
                    "\(provider.name) n'envoie plus rien depuis \(Int(seconds)) s : réponse interrompue. Réessayez.",
                    status: 408, transient: true
                ))
                return
            }
            if Task.isCancelled { out.finish(); return }
            if let calls = tools.render() { out.yield(ChatDelta(text: calls)) }
            if stop == nil && !ended { out.yield(ChatDelta(stop: "cut")) }
            out.finish()
        }
        let watchdog = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                if ContinuousClock.now - lastActivity.get() > limit {
                    timedOut.set(true)
                    reader.cancel()
                    return
                }
            }
        }
        await withTaskCancellationHandler {
            _ = await reader.value
        } onCancel: {
            reader.cancel()
        }
        watchdog.cancel()
    }

    /// Toute la réponse d'un coup (pour les titres, les agents…).
    public func complete(
        provider: ProviderDef, apiKey: String?, model: String, messages: [LLMMessage],
        system: String? = nil, options: LLMOptions = LLMOptions()
    ) async throws -> (text: String, usage: TokenUsage) {
        var text = ""
        var total = TokenUsage.zero
        for try await d in stream(provider: provider, apiKey: apiKey, model: model, messages: messages, system: system, options: options) {
            text += d.text
            if let u = d.usage { total = total + u }
        }
        if total.total == 0 {
            let input = messages.reduce(0) { $0 + $1.content.count } + (system?.count ?? 0)
            total = TokenUsage((input + 3) / 4, (text.count + 3) / 4)
        }
        return (text.trimmingCharacters(in: .whitespacesAndNewlines), total)
    }

    /// La raison d'arrêt d'une réponse reçue d'un bloc.
    static func wholeStop(_ body: String) -> String? {
        guard let j = LooseJSON.object(body) as? [String: Any] else { return nil }
        let r = j["stop_reason"] ?? j["done_reason"] ?? ((j["choices"] as? [Any])?.first as? [String: Any])?["finish_reason"]
        guard let s = r as? String, !s.isEmpty else { return nil }
        return s
    }

    static func wholeText(_ p: ProviderDef, _ body: String) -> String {
        guard let j = LooseJSON.object(body) as? [String: Any] else { return body }
        if p.kind == .anthropic, let content = j["content"] as? [Any] {
            return content.compactMap { ($0 as? [String: Any]).flatMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil } }.joined()
        }
        if let choices = j["choices"] as? [Any], let first = choices.first as? [String: Any] {
            if let m = first["message"] as? [String: Any] {
                // Pas de texte (seulement des appels d'outils) : réponse vide.
                return m["content"] as? String ?? ""
            }
        }
        return body
    }

    // MARK: - Modèles

    /// Les modèles du fournisseur, lus en direct.
    public func listModels(_ p: ProviderDef, apiKey: String?) async throws -> [ModelInfo] {
        let base = Self.trim(p.baseUrl)
        func get(_ url: String, auth: Bool = true) async throws -> Any? {
            guard let u = URL(string: url) else { throw LLMError("Adresse invalide : \(url)") }
            let (head, data) = try await transport.data(request(u, method: "GET", headers: auth ? headers(p, key: apiKey) : [:], body: nil, timeout: 15))
            let text = String(decoding: data, as: UTF8.self)
            if !head.ok { throw LLMError(errorFromBody(text), status: head.status) }
            return LooseJSON.object(text)
        }
        switch p.listing {
        case .none:
            return p.defaultModels.map { ModelInfo($0, free: p.free) }
        case .ollama:
            let j = try await get(base + "/api/tags") as? [String: Any]
            var list = ((j?["models"] as? [Any]) ?? []).compactMap { $0 as? [String: Any] }.map { m -> ModelInfo in
                let name = "\(m["name"] ?? m["model"] ?? "")"
                let detail = p.local ? Self.size(m["size"]) : Catalog.price(provider: p.id, model: name)?.label
                return ModelInfo(name, free: p.free, detail: detail)
            }
            if !p.local { list.sort { $0.id < $1.id } }
            return list
        case .githubCatalog:
            let j = try await get("https://models.github.ai/catalog/models")
            let list = (j as? [Any]) ?? ((j as? [String: Any])?["data"] as? [Any]) ?? []
            return list.compactMap { $0 as? [String: Any] }.map {
                ModelInfo("\($0["id"] ?? "")", free: true, detail: $0["publisher"].map { "\($0)" })
            }
        case .pollinations:
            let j = try await get("https://text.pollinations.ai/models", auth: false)
            return ((j as? [Any]) ?? []).map { m in
                if let m = m as? [String: Any] {
                    return ModelInfo("\(m["name"] ?? m["id"] ?? "")", free: true, detail: m["description"].map { "\($0)" })
                }
                return ModelInfo("\(m)", free: true)
            }
        case .openai:
            let j = try await get(base + "/models")
            let list = (j as? [Any]) ?? ((j as? [String: Any]).flatMap { ($0["data"] ?? $0["models"]) as? [Any] }) ?? []
            var out: [ModelInfo] = []
            for case let m as [String: Any] in list {
                var id = "\(m["id"] ?? m["name"] ?? "")"
                if id.hasPrefix("models/") { id = String(id.dropFirst(7)) }
                var free = p.free
                if let suffix = p.freeModelSuffix {
                    let pricing = m["pricing"] as? [String: Any]
                    free = id.hasSuffix(suffix) || (pricing.map { "\($0["prompt"] ?? "")" == "0" && "\($0["completion"] ?? "")" == "0" } ?? false)
                }
                let ctx = int(m["context_length"])
                out.append(ModelInfo(id, free: free, detail: ctx > 0 ? "\(ctx / 1000)k tokens" : nil))
            }
            out.sort { a, b in a.free != b.free ? a.free : a.id < b.id }
            return out
        }
    }

    static func size(_ bytes: Any?) -> String? {
        let b = Double(int(bytes))
        if b <= 0 { return nil }
        let gb = b / (1024 * 1024 * 1024)
        return gb >= 1 ? String(format: "%.1f Go", gb) : "\(Int((b / (1024 * 1024)).rounded())) Mo"
    }

    /// Télécharge un modèle dans Ollama ; rend la progression (0 à 1, ou -1 si
    /// inconnue) et le statut.
    public func ollamaPull(_ p: ProviderDef, apiKey: String?, model: String) -> AsyncThrowingStream<(Double, String), Error> {
        AsyncThrowingStream { c in
            let task = Task {
                do {
                    guard let url = URL(string: Self.trim(p.baseUrl) + "/api/pull") else { throw LLMError("Adresse invalide") }
                    let (head, lines) = try await transport.lines(request(url, method: "POST", headers: headers(p, key: apiKey), body: ["model": model, "stream": true], timeout: 600))
                    if head.status != 200 { throw LLMError(errorFromBody(await lines.joined()), status: head.status) }
                    for try await line in lines {
                        guard !line.trimmingCharacters(in: .whitespaces).isEmpty,
                              let j = LooseJSON.object(line) as? [String: Any] else { continue }
                        if let e = j["error"] { throw LLMError("\(e)") }
                        let total = Double(int(j["total"]))
                        let done = Double(int(j["completed"]))
                        c.yield((total > 0 ? done / total : -1, j["status"].map { "\($0)" } ?? ""))
                    }
                    c.finish()
                } catch {
                    c.finish(throwing: error)
                }
            }
            c.onTermination = { _ in task.cancel() }
        }
    }

    /// Supprime un modèle d'Ollama.
    public func ollamaDelete(_ p: ProviderDef, apiKey: String?, model: String) async throws {
        guard let url = URL(string: Self.trim(p.baseUrl) + "/api/delete") else { throw LLMError("Adresse invalide") }
        let (head, data) = try await transport.data(request(url, method: "DELETE", headers: headers(p, key: apiKey), body: ["model": model], timeout: 30))
        if !head.ok { throw LLMError(errorFromBody(String(decoding: data, as: UTF8.self)), status: head.status) }
    }
}
