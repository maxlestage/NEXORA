import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import NexoraKit

/// Une réponse du faux modèle.
enum Reply: Sendable {
    /// Du texte, en flux.
    case text(String)
    /// Un appel d'outil par le canal natif `tool_calls`, sans texte.
    case native(String, String)
    /// Une erreur HTTP.
    case error(Int, String)
    /// Du texte, puis la connexion se ferme avant la fin (ni raison d'arrêt, ni
    /// `[DONE]`).
    case cut(String)
    /// Rien ne vient jamais (jusqu'à l'annulation).
    case hang
}

/// Un faux modèle : rend les réponses prévues, dans l'ordre (ou calculées d'après
/// la requête), en flux SSE, et garde chaque requête.
final class ScriptLLM: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var replies: [Reply]
    private var stops: [String?] = []
    private var bodies: [[String: Any]] = []
    /// Une réponse calculée d'après la requête (n°, prompt complet, hôte) : prime
    /// sur la liste.
    var dynamic: (@Sendable (Int, String, String) -> Reply?)?
    /// Une réponse calculée d'après la requête (n°, modèle demandé, dernier message).
    var byModel: (@Sendable (Int, String, String) -> Reply?)?
    /// La raison d'arrêt envoyée à la fin de chaque réponse.
    var finish: String? = "stop"
    /// La réponse donnée quand la liste est épuisée (`nil` : une erreur).
    var whenEmpty: String?
    /// Appelé (et attendu) à chaque requête, avant la réponse.
    var onRequest: (@Sendable (Int) async -> Void)?

    init(_ replies: [String] = []) {
        self.replies = replies.map { .text($0) }
    }

    init(replies: [Reply]) {
        self.replies = replies
    }

    /// Les raisons d'arrêt, réponse par réponse (sinon `finish`).
    func setStops(_ s: [String?]) {
        lock.withLock { stops = s }
    }

    func push(_ r: String) {
        lock.withLock { replies.append(.text(r)) }
    }

    var count: Int {
        lock.withLock { bodies.count }
    }

    /// Le prompt complet de la requête n° i : consigne système et messages.
    func prompt(_ i: Int) -> String {
        lock.withLock { Self.text(bodies[i]) }
    }

    /// Les messages de la requête n° i.
    func messages(_ i: Int) -> [[String: String]] {
        lock.withLock {
            (bodies[i]["messages"] as? [[String: Any]] ?? []).map {
                ["role": $0["role"] as? String ?? "", "content": $0["content"] as? String ?? ""]
            }
        }
    }

    /// Les messages bruts de la requête n° i (avec leurs images).
    func rawMessages(_ i: Int) -> [[String: Any]] {
        lock.withLock { bodies[i]["messages"] as? [[String: Any]] ?? [] }
    }

    /// Le dernier message de la requête n° i.
    func last(_ i: Int) -> String { messages(i).last?["content"] ?? "" }

    static func text(_ b: [String: Any]) -> String {
        var parts: [String] = []
        if let s = b["system"] as? String { parts.append(s) }
        for m in b["messages"] as? [[String: Any]] ?? [] { parts.append(m["content"] as? String ?? "") }
        return parts.joined(separator: "\n")
    }

    func data(_ request: URLRequest) async throws -> (HTTPHead, Data) {
        (HTTPHead(status: 500), Data("{}".utf8))
    }

    static func chunk(_ delta: [String: Any], finish: String? = nil) -> String {
        var c: [String: Any] = ["index": 0, "delta": delta]
        if let finish { c["finish_reason"] = finish }
        return "data: " + LooseJSON.string(["choices": [c]]) + "\n"
    }

    func lines(_ request: URLRequest) async throws -> (HTTPHead, AsyncThrowingStream<String, Error>) {
        let body = (request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]) ?? [:]
        let (n, dyn, stop) = lock.withLock { () -> (Int, (@Sendable (Int, String, String) -> Reply?)?, String?) in
            let n = bodies.count
            bodies.append(body)
            return (n, dynamic, n < stops.count ? stops[n] : finish)
        }
        if let hook = lock.withLock({ onRequest }) { await hook(n) }
        var reply: Reply?
        if let dyn { reply = dyn(n, Self.text(body), request.url?.host ?? "") }
        if reply == nil, let f = lock.withLock({ byModel }) {
            let last = (body["messages"] as? [[String: Any]])?.last?["content"] as? String ?? ""
            reply = f(n, body["model"] as? String ?? "", last)
        }
        if reply == nil {
            reply = lock.withLock { replies.isEmpty ? whenEmpty.map { .text($0) } : replies.removeFirst() }
        }
        var status = 200
        var text: String
        switch reply {
        case nil:
            status = 400
            text = #"{"error":{"message":"plus de réponse prévue"}}"#
        case .text(let t)?:
            text = sse([t], finish: stop)
        case .native(let name, let args)?:
            let half = args.count / 2
            text = [
                Self.chunk(["role": "assistant", "content": ""]),
                Self.chunk(["tool_calls": [["index": 0, "id": "c1", "type": "function", "function": ["name": name, "arguments": ""]]]]),
                Self.chunk(["tool_calls": [["index": 0, "function": ["arguments": String(args.prefix(half))]]]]),
                Self.chunk(["tool_calls": [["index": 0, "function": ["arguments": String(args.dropFirst(half))]]]], finish: "tool_calls"),
                "data: [DONE]\n",
            ].joined(separator: "\n")
        case .hang?:
            return (HTTPHead(status: 200, headers: ["content-type": "text/event-stream"]), AsyncThrowingStream { c in
                // Gardée vivante jusqu'à l'annulation.
                c.onTermination = { _ in _ = c }
            })
        case .cut(let t)?:
            text = Self.chunk(["content": t])
        case .error(let s, let b)?:
            status = s
            text = b
        }
        let head = HTTPHead(status: status, headers: ["content-type": status == 200 ? "text/event-stream" : "application/json"])
        return (head, AsyncThrowingStream { c in
            for l in text.components(separatedBy: "\n") { c.yield(l) }
            c.finish()
        })
    }
}

/// Un faux serveur web : chaque requête passe par une fonction (méthode, chemin
/// décodé, corps JSON) qui rend (statut, corps).
final class Routes: HTTPTransport, @unchecked Sendable {
    struct Call {
        let method: String
        let path: String
        let query: String
        let body: [String: Any]
    }

    private let lock = NSLock()
    private var log: [Call] = []
    let handler: @Sendable (Call) -> (Int, String, [String: String])

    init(_ handler: @escaping @Sendable (Call) -> (Int, String)) {
        self.handler = { let (s, b) = handler($0); return (s, b, [:]) }
    }

    init(headers handler: @escaping @Sendable (Call) -> (Int, String, [String: String])) {
        self.handler = handler
    }

    var calls: [String] {
        lock.lock()
        defer { lock.unlock() }
        return log.map { "\($0.method) \($0.path)" }
    }

    func data(_ request: URLRequest) async throws -> (HTTPHead, Data) {
        let body = (request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]) ?? [:]
        let url = request.url!
        let path = url.host == "api.github.com" || url.host == nil ? url.path : "//\(url.host!)\(url.path)"
        let call = Call(method: request.httpMethod ?? "GET", path: path, query: url.query ?? "", body: body)
        lock.withLock { log.append(call) }
        let (s, b, h) = handler(call)
        return (HTTPHead(status: s, headers: h), Data(b.utf8))
    }

    func lines(_ request: URLRequest) async throws -> (HTTPHead, AsyncThrowingStream<String, Error>) {
        let (h, d) = try await data(request)
        let text = String(decoding: d, as: UTF8.self)
        return (h, AsyncThrowingStream { c in
            c.yield(text)
            c.finish()
        })
    }
}

/// Une réponse de l'API Contents pour un fichier.
func fileJSON(_ text: String, sha: String = "s") -> String {
    LooseJSON.string(["sha": sha, "content": Data(text.utf8).base64EncodedString(), "encoding": "base64", "size": text.utf8.count])
}

/// Une réponse « arbre du dépôt » pour ces fichiers.
func treeJSON(_ files: [String]) -> String {
    LooseJSON.string(["tree": files.map { ["path": $0, "type": "blob"] }])
}

let notFound = (404, #"{"message":"Not Found"}"#)

/// Un dépôt simulé : ses fichiers (lus par l'arbre, l'API Contents et raw).
func repoHub(_ files: [String: String], extra: (@Sendable (Routes.Call) -> (Int, String)?)? = nil) -> Routes {
    Routes { c in
        if let r = extra?(c) { return r }
        if c.path.contains("/git/trees/") { return (200, treeJSON(files.keys.sorted())) }
        if c.path.contains("/contents/") {
            let f = c.path.components(separatedBy: "/contents/").last ?? ""
            if let t = files[f] { return (200, fileJSON(t)) }
            return notFound
        }
        if c.path.hasPrefix("//raw.githubusercontent.com/") {
            // /owner/repo/ref/chemin
            let parts = c.path.dropFirst("//raw.githubusercontent.com/".count).split(separator: "/", maxSplits: 3).map(String.init)
            if parts.count == 4, let t = files[parts[3]] { return (200, t) }
            return notFound
        }
        return notFound
    }
}

/// Une action, dans un bloc ```json.
func act(_ j: [String: Any]) -> String {
    "```json\n\(LooseJSON.string(j))\n```"
}

let groq = Catalog.providers.first { $0.id == "groq" }!

/// Une session de test : faux modèle et faux GitHub, sans attente.
@MainActor
func makeRun(
    _ llm: ScriptLLM = ScriptLLM(), hub: HTTPTransport, owner: String = "max", repo: String = "site",
    branch: String = "main", task: String = "Tâche", extra: [RepoTarget] = [], checks: Bool = true,
    compile: Bool = false, agent: Agent? = nil, maxSteps: Int = 24
) -> AgentRun {
    var gh = GitHubAPI(token: "t", transport: hub)
    gh.retryPause = .zero
    let run = AgentRun(
        llm: LLMClient(transport: llm, retryDelay: { _, _ in .zero }), github: gh, provider: groq, apiKey: "k",
        model: "m", owner: owner, repo: repo, branch: branch, task: task, agent: agent, maxSteps: maxSteps,
        extraRepos: extra
    )
    run.checks = checks
    run.compile = compile
    run.retryPause = .zero
    return run
}

extension AgentRun {
    /// Les textes des étapes d'un genre, réunis.
    func texts(_ kind: StepKind) -> String {
        steps.filter { $0.kind == kind }.map(\.text).joined(separator: "\n")
    }
}
