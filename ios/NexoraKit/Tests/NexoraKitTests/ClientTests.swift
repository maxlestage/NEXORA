import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import NexoraKit

/// Un faux serveur : rend les réponses prévues, dans l'ordre, et garde les requêtes.
final class FakeTransport: HTTPTransport, @unchecked Sendable {
    struct Reply {
        var status = 200
        var headers = ["content-type": "text/event-stream"]
        var body: String
    }

    private let lock = NSLock()
    private var replies: [Reply]
    private(set) var requests: [URLRequest] = []

    init(_ replies: [Reply]) {
        self.replies = replies
    }

    private func next(_ r: URLRequest) -> Reply {
        lock.lock()
        defer { lock.unlock() }
        requests.append(r)
        return replies.isEmpty ? Reply(status: 500, body: "plus de réponse") : replies.removeFirst()
    }

    func data(_ request: URLRequest) async throws -> (HTTPHead, Data) {
        let r = next(request)
        return (HTTPHead(status: r.status, headers: r.headers), Data(r.body.utf8))
    }

    func lines(_ request: URLRequest) async throws -> (HTTPHead, AsyncThrowingStream<String, Error>) {
        let r = next(request)
        let parts = r.body.components(separatedBy: "\n")
        return (HTTPHead(status: r.status, headers: r.headers), AsyncThrowingStream { c in
            for p in parts { c.yield(p) }
            c.finish()
        })
    }

    func body(_ i: Int) -> [String: Any] {
        lock.lock()
        defer { lock.unlock() }
        guard let d = requests[i].httpBody else { return [:] }
        return (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] ?? [:]
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return requests.count
    }
}

func sse(_ texts: [String], finish: String? = "stop") -> String {
    var out = texts.map { "data: " + LooseJSON.string(["choices": [["delta": ["content": $0]]]]) + "\n" }
    if let finish { out.append("data: " + LooseJSON.string(["choices": [["delta": [String: String](), "finish_reason": finish]]]) + "\n") }
    out.append("data: [DONE]\n")
    return out.joined(separator: "\n")
}

func collect(_ s: AsyncThrowingStream<ChatDelta, Error>) async throws -> (String, String?) {
    var text = ""
    var stop: String?
    for try await d in s {
        text += d.text
        if let st = d.stop { stop = st }
    }
    return (text, stop)
}

@Suite("Client des modèles")
struct ClientTests {
    let groq = Catalog.providers.first { $0.id == "groq" }!
    let anthropic = Catalog.providers.first { $0.id == "anthropic" }!

    @Test("flux OpenAI compatible, avec en-têtes et clé")
    func openAIStream() async throws {
        let t = FakeTransport([.init(body: sse(["Bon", "jour"]))])
        let client = LLMClient(transport: t)
        let (text, stop) = try await collect(client.stream(provider: groq, apiKey: "k1", model: "m", messages: [LLMMessage("user", "Salut")], system: "Sois bref"))
        #expect(text == "Bonjour")
        #expect(stop == "stop")
        let req = t.requests[0]
        #expect(req.url?.absoluteString == "https://api.groq.com/openai/v1/chat/completions")
        #expect(req.value(forHTTPHeaderField: "authorization") == "Bearer k1")
        let msgs = t.body(0)["messages"] as? [[String: String]]
        #expect(msgs?.first?["role"] == "system")
        #expect(msgs?.last?["content"] == "Salut")
    }

    @Test("connexion fermée sans signal de fin : la réponse est marquée coupée")
    func cut() async throws {
        let body = "data: " + LooseJSON.string(["choices": [["delta": ["content": "Début"]]]])
        let t = FakeTransport([.init(body: body)])
        let (text, stop) = try await collect(LLMClient(transport: t).stream(provider: groq, apiKey: nil, model: "m", messages: [LLMMessage("user", "x")]))
        #expect(text == "Début")
        #expect(stop == "cut")
    }

    @Test("erreur HTTP lisible, et nouvel essai sur une saturation")
    func errors() async throws {
        let t = FakeTransport([
            .init(status: 503, headers: ["retry-after": "0"], body: "occupé"),
            .init(status: 401, headers: ["content-type": "application/json"], body: #"{"error":{"message":"Clé invalide"}}"#),
        ])
        let client = LLMClient(transport: t, retryDelay: { _, _ in .milliseconds(1) })
        do {
            _ = try await collect(client.stream(provider: groq, apiKey: "x", model: "m", messages: [LLMMessage("user", "x")]))
            Issue.record("une erreur était attendue")
        } catch let e as LLMError {
            #expect(e.status == 401)
            #expect(e.message == "Clé invalide")
        }
        #expect(t.count == 2)
    }

    @Test("réponse d'un seul bloc JSON malgré stream: true")
    func whole() async throws {
        let body = #"{"choices":[{"message":{"content":"<think>hm</think>Réponse"},"finish_reason":"length"}],"usage":{"prompt_tokens":3,"completion_tokens":4}}"#
        let t = FakeTransport([.init(headers: ["content-type": "application/json"], body: body)])
        var text = ""
        var thinking = ""
        var stop: String?
        var usage: TokenUsage?
        for try await d in LLMClient(transport: t).stream(provider: groq, apiKey: nil, model: "m", messages: [LLMMessage("user", "x")]) {
            text += d.text
            thinking += d.thinking
            if let s = d.stop { stop = s }
            if let u = d.usage { usage = u }
        }
        #expect(text == "Réponse" && thinking == "hm")
        #expect(stop == "length")
        #expect(usage == TokenUsage(3, 4))
    }

    @Test("Anthropic : en-têtes, tours alternés, repli sans réflexion")
    func anthropicRequest() async throws {
        let ok = [
            #"data: {"type":"message_start","message":{"usage":{"input_tokens":10}}}"#,
            #"data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"Hi"}}"#,
            #"data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":2}}"#,
            #"data: {"type":"message_stop"}"#,
        ].joined(separator: "\n")
        let t = FakeTransport([.init(status: 400, body: "réglage refusé"), .init(body: ok)])
        let msgs = [LLMMessage("assistant", "Bonjour"), LLMMessage("user", "a"), LLMMessage("user", "b")]
        let (text, stop) = try await collect(LLMClient(transport: t).stream(provider: anthropic, apiKey: "sk", model: "claude-opus-5-5", messages: msgs, options: LLMOptions(level: .eleve)))
        #expect(text == "Hi" && stop == "end_turn")
        #expect(t.requests[1].value(forHTTPHeaderField: "x-api-key") == "sk")
        #expect(t.requests[1].value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        #expect(t.body(0)["output_config"] != nil)
        #expect(t.body(1)["output_config"] == nil)
        let sent = t.body(1)["messages"] as? [[String: String]]
        #expect(sent?.map { $0["role"] ?? "" } == ["user", "assistant", "user"])
        #expect(sent?.last?["content"] == "a\n\nb")
    }

    @Test("liste des modèles OpenRouter : gratuits en premier")
    func models() async throws {
        let body = #"{"data":[{"id":"z/pay","pricing":{"prompt":"0.1","completion":"0.2"}},{"id":"a/libre:free"},{"id":"b/zero","pricing":{"prompt":"0","completion":"0"},"context_length":128000}]}"#
        let openrouter = Catalog.providers.first { $0.id == "openrouter" }!
        let list = try await LLMClient(transport: FakeTransport([.init(body: body)])).listModels(openrouter, apiKey: "k")
        #expect(list.map(\.id) == ["a/libre:free", "b/zero", "z/pay"])
        #expect(list[1].detail == "128k tokens")
        #expect(!list[2].free)
    }

    @Test("GitHub : lecture d'un fichier et erreurs détaillées")
    func github() async throws {
        let file = #"{"sha":"s1","size":5,"content":"Ym9uam91cg==\n"}"#
        let err = #"{"message":"Validation Failed","errors":[{"message":"name already exists"}]}"#
        let t = FakeTransport([.init(body: file), .init(status: 422, body: err)])
        let gh = GitHubAPI(token: "t", transport: t)
        let f = try await gh.readFile("o", "r", path: "dossier/a b.txt", ref: "main")
        #expect(f.text == "bonjour" && f.sha == "s1" && !f.binary)
        #expect(t.requests[0].url?.absoluteString == "https://api.github.com/repos/o/r/contents/dossier/a%20b.txt?ref=main")
        #expect(t.requests[0].value(forHTTPHeaderField: "authorization") == "Bearer t")
        do {
            _ = try await gh.createRepo(name: "x")
            Issue.record("une erreur était attendue")
        } catch let e as GitHubError {
            #expect(e.status == 422)
            #expect(e.message == "Validation Failed (name already exists)")
        }
    }
}
