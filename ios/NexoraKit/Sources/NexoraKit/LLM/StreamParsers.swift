import Foundation

/// Les tokens d'une réponse : envoyés (question, historique) et reçus.
public struct TokenUsage: Sendable, Hashable {
    public var input: Int
    public var output: Int

    public init(_ input: Int, _ output: Int) {
        self.input = input
        self.output = output
    }

    public static let zero = TokenUsage(0, 0)

    public var total: Int { input + output }

    public static func + (a: TokenUsage, b: TokenUsage) -> TokenUsage {
        TokenUsage(a.input + b.input, a.output + b.output)
    }

    /// `usage` au format OpenAI (`prompt_tokens`, `completion_tokens`) ou Anthropic
    /// (`input_tokens`, `output_tokens`).
    public static func from(_ u: Any?) -> TokenUsage? {
        guard let u = u as? [String: Any] else { return nil }
        let input = int(u["prompt_tokens"] ?? u["input_tokens"])
        let output = int(u["completion_tokens"] ?? u["output_tokens"])
        if input == 0 && output == 0 { return nil }
        return TokenUsage(input, output)
    }
}

func int(_ v: Any?) -> Int {
    if let n = v as? Int { return n }
    if let d = v as? Double { return Int(d) }
    if let n = v as? NSNumber { return n.intValue }
    return 0
}

/// Un morceau d'appel d'outil natif (canal `tool_calls`).
public struct ToolCallPart: Sendable, Hashable {
    public let index: Int
    public let name: String
    /// Les arguments en JSON (texte, reçu par morceaux).
    public let arguments: String

    public init(_ index: Int, name: String = "", arguments: String = "") {
        self.index = index
        self.name = name
        self.arguments = arguments
    }
}

/// Un morceau de réponse reçu en flux.
public struct ChatDelta: Sendable, Hashable {
    public var text: String
    public var thinking: String
    public var done: Bool
    public var usage: TokenUsage?
    public var toolCalls: [ToolCallPart]
    /// Pourquoi le modèle s'est arrêté : `stop`, `length` / `max_tokens` (coupé par
    /// la limite de longueur)… et `cut` quand la connexion s'est fermée sans signal.
    public var stop: String?

    public init(
        text: String = "", thinking: String = "", done: Bool = false,
        usage: TokenUsage? = nil, toolCalls: [ToolCallPart] = [], stop: String? = nil
    ) {
        self.text = text
        self.thinking = thinking
        self.done = done
        self.usage = usage
        self.toolCalls = toolCalls
        self.stop = stop
    }

    /// La réponse a été coupée avant la fin : il faut demander la suite.
    public var truncated: Bool { isCutStop(stop) }

    public var isEmpty: Bool {
        text.isEmpty && thinking.isEmpty && !done && usage == nil && toolCalls.isEmpty && stop == nil
    }
}

/// Une raison d'arrêt qui veut dire « coupé avant la fin ».
public func isCutStop(_ stop: String?) -> Bool {
    ["length", "max_tokens", "max_output_tokens", "cut"].contains(stop ?? "")
}

/// Une erreur d'un fournisseur d'IA.
public struct LLMError: Error, Sendable, CustomStringConvertible, LocalizedError {
    public let message: String
    public let status: Int?
    /// Coupure réseau ou délai dépassé : réessayer a des chances de marcher.
    public let transient: Bool

    public init(_ message: String, status: Int? = nil, transient: Bool = false) {
        self.message = message
        self.status = status
        self.transient = transient
    }

    /// Vaut-il la peine de réessayer (réseau, délai, saturation, limite de débit) ?
    public var retryable: Bool { transient || [408, 429, 500, 502, 503, 504, 529].contains(status ?? 0) }

    public var description: String { status.map { "HTTP \($0) · \(message)" } ?? message }
    public var errorDescription: String? { description }
}

func errorMessage(_ e: Any?) -> String {
    if let m = e as? [String: Any] {
        if let v = m["message"] ?? m["error"] ?? m["type"] { return "\(v)" }
        return "\(m)"
    }
    if let e { return "\(e)" }
    return "Erreur inconnue"
}

/// Le message d'erreur d'une réponse HTTP en échec, lisible par un humain.
public func errorFromBody(_ body: String) -> String {
    if let j = LooseJSON.object(body) as? [String: Any] {
        if let e = j["error"] { return errorMessage(e) }
        if let m = j["message"] { return "\(m)" }
        if let d = j["detail"] { return "\(d)" }
    }
    let t = body.trimmingCharacters(in: .whitespacesAndNewlines)
    if t.isEmpty { return "Réponse vide" }
    return t.count > 400 ? String(t.prefix(400)) + "…" : t
}

func toolCallParts(_ raw: Any?) -> [ToolCallPart] {
    guard let list = raw as? [Any] else { return [] }
    var out: [ToolCallPart] = []
    for (i, t) in list.enumerated() {
        guard let t = t as? [String: Any] else { continue }
        let fn = (t["function"] as? [String: Any]) ?? t
        let args = fn["arguments"] ?? fn["input"]
        let argText: String
        if let s = args as? String {
            argText = s
        } else if let args, !(args is NSNull) {
            argText = LooseJSON.string(args)
        } else {
            argText = ""
        }
        let index = (t["index"] as? Int) ?? i
        out.append(ToolCallPart(index, name: fn["name"].map { "\($0)" } ?? "", arguments: argText))
    }
    return out
}

/// Réunit les morceaux d'appels d'outils natifs et les rend sous la forme que lit
/// l'agent (un bloc ```json {"actions": [...]}```).
public struct ToolCallCollector: Sendable {
    private var calls: [Int: (name: String, args: String)] = [:]

    public init() {}

    public mutating func add(_ d: ChatDelta) {
        for p in d.toolCalls {
            var c = calls[p.index] ?? ("", "")
            c.name += p.name
            c.args += p.arguments
            calls[p.index] = c
        }
    }

    public var isEmpty: Bool { calls.isEmpty }

    /// Le bloc à ajouter à la réponse, ou `nil` s'il n'y a eu aucun appel.
    public func render() -> String? {
        if calls.isEmpty { return nil }
        var actions: [[String: Any]] = []
        for k in calls.keys.sorted() {
            let (name, args) = calls[k]!
            let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if n.isEmpty { continue }
            let text = args.trimmingCharacters(in: .whitespacesAndNewlines)
            var parsed: Any? = LooseJSON.object(text.isEmpty ? "{}" : text)
            if parsed == nil {
                parsed = LooseJSON.decodeToolArgs(text) ?? ["raw": text]
            }
            actions.append(["tool": n, "args": (parsed as? [String: Any]) ?? ["value": parsed ?? NSNull()]])
        }
        if actions.isEmpty { return nil }
        return "\n```json\n\(LooseJSON.string(["actions": actions]))\n```\n"
    }
}

/// Lit le flux d'un fournisseur ligne par ligne, selon son protocole.
public struct StreamLineParser: Sendable {
    public let kind: ApiKind
    /// Ollama envoie chaque appel d'outil entier : chacun reçoit son propre numéro.
    private var ollamaCalls = 0

    public init(kind: ApiKind) {
        self.kind = kind
    }

    public mutating func parse(_ line: String) throws -> ChatDelta? {
        switch kind {
        case .openai: return try Self.openAI(line)
        case .anthropic: return try Self.anthropic(line)
        case .ollama: return try ollama(line)
        }
    }

    /// Une ligne d'un flux SSE OpenAI (`data: {...}`), ou `nil` si elle ne porte rien.
    public static func openAI(_ line: String) throws -> ChatDelta? {
        let l = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard l.hasPrefix("data:") else { return nil }
        let data = l.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)
        if data.isEmpty { return nil }
        if data == "[DONE]" { return ChatDelta(done: true) }
        guard let j = LooseJSON.object(data) as? [String: Any] else { return nil }
        if let e = j["error"], !(e is NSNull) {
            // Une erreur au milieu du flux : souvent passagère chez le fournisseur.
            throw LLMError(errorMessage(e), transient: true)
        }
        let usage = TokenUsage.from(j["usage"]) ?? TokenUsage.from((j["x_groq"] as? [String: Any])?["usage"])
        guard let choices = j["choices"] as? [Any], let c = choices.first as? [String: Any] else {
            return usage.map { ChatDelta(usage: $0) }
        }
        let delta = (c["delta"] ?? c["message"]) as? [String: Any]
        let finish = c["finish_reason"] as? String
        let out = ChatDelta(
            text: delta?["content"] as? String ?? "",
            thinking: (delta?["reasoning_content"] as? String) ?? (delta?["reasoning"] as? String) ?? "",
            usage: usage,
            toolCalls: toolCallParts(delta?["tool_calls"]),
            stop: (finish?.isEmpty ?? true) ? nil : finish
        )
        return out.isEmpty ? nil : out
    }

    /// Une ligne NDJSON de l'API native d'Ollama.
    public mutating func ollama(_ line: String) throws -> ChatDelta? {
        let l = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if l.isEmpty { return nil }
        guard let j = LooseJSON.object(l) as? [String: Any] else { return nil }
        if let e = j["error"], !(e is NSNull) { throw LLMError("\(e)", transient: true) }
        let msg = j["message"] as? [String: Any]
        let done = (j["done"] as? Bool) == true
        var calls: [ToolCallPart] = []
        if let raw = msg?["tool_calls"] as? [Any] {
            for p in toolCallParts(raw) {
                calls.append(ToolCallPart(ollamaCalls, name: p.name, arguments: p.arguments))
                ollamaCalls += 1
            }
        }
        return ChatDelta(
            text: msg?["content"] as? String ?? "",
            thinking: msg?["thinking"] as? String ?? "",
            done: done,
            usage: done ? TokenUsage.from(["prompt_tokens": j["prompt_eval_count"] ?? 0, "completion_tokens": j["eval_count"] ?? 0]) : nil,
            toolCalls: calls,
            stop: done ? (j["done_reason"] as? String ?? "stop") : nil
        )
    }

    /// Un événement SSE de l'API Messages d'Anthropic (la ligne `data: {...}`).
    public static func anthropic(_ line: String) throws -> ChatDelta? {
        let l = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard l.hasPrefix("data:") else { return nil }
        guard let j = LooseJSON.object(l.dropFirst(5).trimmingCharacters(in: .whitespaces)) as? [String: Any] else {
            return nil
        }
        switch j["type"] as? String {
        case "content_block_delta":
            guard let d = j["delta"] as? [String: Any] else { return nil }
            if d["type"] as? String == "text_delta" { return ChatDelta(text: d["text"] as? String ?? "") }
            if d["type"] as? String == "thinking_delta" { return ChatDelta(thinking: d["thinking"] as? String ?? "") }
            return nil
        case "message_start":
            guard let u = TokenUsage.from((j["message"] as? [String: Any])?["usage"]) else { return nil }
            return ChatDelta(usage: TokenUsage(u.input, 0))
        case "message_delta":
            let u = TokenUsage.from(j["usage"])
            let reason = (j["delta"] as? [String: Any])?["stop_reason"] as? String
            if u == nil && reason == nil { return nil }
            return ChatDelta(usage: u.map { TokenUsage(0, $0.output) }, stop: reason)
        case "message_stop":
            return ChatDelta(done: true)
        case "error":
            throw LLMError(errorMessage(j["error"]), transient: true)
        default:
            return nil
        }
    }
}

/// Sépare le raisonnement écrit entre `<think>` et `</think>` (DeepSeek R1, Qwen3…)
/// du texte de la réponse, même quand les balises arrivent coupées en morceaux.
public struct ThinkSplitter: Sendable {
    private var inThink = false
    private var pending = ""
    private static let open = "<think>"
    private static let close = "</think>"

    public init() {}

    public mutating func feed(_ d: ChatDelta) -> ChatDelta {
        if d.text.isEmpty { return d }
        var s = pending + d.text
        pending = ""
        var text = ""
        var thinking = d.thinking
        while !s.isEmpty {
            let tag = inThink ? Self.close : Self.open
            if let r = s.range(of: tag) {
                if inThink { thinking += s[..<r.lowerBound] } else { text += s[..<r.lowerBound] }
                s = String(s[r.upperBound...])
                inThink.toggle()
                continue
            }
            // Une balise peut commencer à la fin du morceau : on la garde pour la suite.
            var keep = 0
            for k in stride(from: tag.count - 1, to: 0, by: -1) where s.hasSuffix(String(tag.prefix(k))) {
                keep = k
                break
            }
            let cut = s.index(s.endIndex, offsetBy: -keep)
            if inThink { thinking += s[..<cut] } else { text += s[..<cut] }
            pending = String(s[cut...])
            s = ""
        }
        return ChatDelta(text: text, thinking: thinking, done: d.done, usage: d.usage, stop: d.stop)
    }

    /// Ce qui reste en attente à la fin du flux.
    public mutating func flush() -> ChatDelta {
        let rest = pending
        pending = ""
        return inThink ? ChatDelta(thinking: rest) : ChatDelta(text: rest)
    }
}
