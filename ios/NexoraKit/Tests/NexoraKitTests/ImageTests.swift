import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import NexoraKit

/// Une « image » en texte ASCII (en-tête GIF) : le faux serveur rend du texte.
private let fakeGIF = "GIF89a-fausse-image"

@Suite("Images : envoi au modèle")
struct ImageSendTests {
    let groq = Catalog.providers.first { $0.id == "groq" }!
    let anthropic = Catalog.providers.first { $0.id == "anthropic" }!
    let ollama = Catalog.providers.first { $0.kind == .ollama }!
    let photo = LLMImage(base64: "QUJD", mimeType: "image/jpeg")

    @Test("sans image, le corps reste exactement le même (texte seul)")
    func unchanged() {
        let c = LLMClient()
        let msgs = [LLMMessage("user", "Salut"), LLMMessage("assistant", "Bonjour")]
        for p in [groq, ollama] {
            let sent = c.body(p, model: "m", messages: msgs, system: nil, options: LLMOptions(), stream: true)["messages"] as? [[String: Any]]
            #expect(sent?.count == 2)
            #expect(sent?.first?["content"] as? String == "Salut")
            #expect(sent?.first?["images"] == nil)
        }
        let a = c.body(anthropic, model: "m", messages: msgs, system: nil, options: LLMOptions(), stream: true)["messages"] as? [[String: Any]]
        #expect(a?.first?["content"] as? String == "Salut")
    }

    @Test("OpenAI : parties text et image_url en data URL")
    func openAI() {
        let m = LLMMessage("user", "Qu'est-ce ?", images: [photo, LLMImage(base64: "WFla", mimeType: "image/png")])
        let sent = LLMClient().body(groq, model: "m", messages: [m], system: "S", options: LLMOptions(), stream: true)["messages"] as? [[String: Any]]
        let parts = sent?.last?["content"] as? [[String: Any]]
        #expect(parts?.count == 3)
        #expect(parts?[0]["type"] as? String == "text")
        #expect(parts?[0]["text"] as? String == "Qu'est-ce ?")
        #expect(parts?[1]["type"] as? String == "image_url")
        #expect((parts?[1]["image_url"] as? [String: Any])?["url"] as? String == "data:image/jpeg;base64,QUJD")
        #expect((parts?[2]["image_url"] as? [String: Any])?["url"] as? String == "data:image/png;base64,WFla")
        // La consigne système reste un texte.
        #expect(sent?.first?["content"] as? String == "S")
    }

    @Test("OpenAI : une photo sans texte n'envoie pas de partie texte vide")
    func photoOnly() {
        let m = LLMMessage("user", "", images: [photo])
        let sent = LLMClient().body(groq, model: "m", messages: [m], system: nil, options: LLMOptions(), stream: true)["messages"] as? [[String: Any]]
        let parts = sent?.first?["content"] as? [[String: Any]]
        #expect(parts?.count == 1)
        #expect(parts?.first?["type"] as? String == "image_url")
    }

    @Test("Anthropic : blocs image base64 puis texte, tours fusionnés")
    func anthropicBlocks() {
        let msgs = [
            LLMMessage("assistant", "Bonjour"),
            LLMMessage("user", "Regarde", images: [photo]),
            LLMMessage("user", "et dis-moi"),
            LLMMessage("assistant", "Vu"),
            LLMMessage("user", "Merci"),
        ]
        let out = LLMClient.alternate(msgs)
        #expect(out.map { $0["role"] as? String ?? "" } == ["user", "assistant", "user", "assistant", "user"])
        let blocks = out[2]["content"] as? [[String: Any]]
        #expect(blocks?.count == 2)
        #expect(blocks?[0]["type"] as? String == "image")
        let source = blocks?[0]["source"] as? [String: Any]
        #expect(source?["type"] as? String == "base64")
        #expect(source?["media_type"] as? String == "image/jpeg")
        #expect(source?["data"] as? String == "QUJD")
        #expect(blocks?[1]["text"] as? String == "Regarde\n\net dis-moi")
        #expect(out[4]["content"] as? String == "Merci")
    }

    @Test("Anthropic : une photo seule (sans texte) n'est pas ignorée")
    func anthropicPhotoOnly() {
        let out = LLMClient.alternate([LLMMessage("user", "  ", images: [photo])])
        #expect(out.count == 1)
        let blocks = out[0]["content"] as? [[String: Any]]
        #expect(blocks?.count == 1)
        #expect(blocks?[0]["type"] as? String == "image")
    }

    @Test("Ollama : images en base64 à côté du texte")
    func ollamaImages() {
        let m = LLMMessage("user", "Décris", images: [photo])
        let sent = LLMClient().body(ollama, model: "llava", messages: [m], system: nil, options: LLMOptions(), stream: true)["messages"] as? [[String: Any]]
        #expect(sent?.first?["content"] as? String == "Décris")
        #expect(sent?.first?["images"] as? [String] == ["QUJD"])
    }

    @Test("modèle sans vision : nouvel essai sans les images, avec une note et un avis")
    func refusedImages() async throws {
        let t = FakeTransport([
            .init(status: 400, headers: ["content-type": "application/json"], body: #"{"error":{"message":"This model does not support image input"}}"#),
            .init(body: sse(["Réponse"])),
        ])
        var text = ""
        var notice: String?
        let msgs = [LLMMessage("user", "Voici", images: [photo])]
        for try await d in LLMClient(transport: t).stream(provider: groq, apiKey: "k", model: "llama-3.1-8b", messages: msgs) {
            text += d.text
            if let n = d.notice { notice = n }
        }
        #expect(text == "Réponse")
        #expect(notice == ChatImages.refusedNotice)
        #expect(t.count == 2)
        let parts = t.body(0)["messages"] as? [[String: Any]]
        #expect(parts?.first?["content"] is [Any])
        let retried = t.body(1)["messages"] as? [[String: String]]
        #expect(retried?.first?["content"] == "Voici\n\n(image non prise en charge par ce modèle)")
    }

    @Test("une erreur 400 sans rapport avec les images est rendue telle quelle")
    func otherError() async throws {
        let t = FakeTransport([
            .init(status: 400, headers: ["content-type": "application/json"], body: #"{"error":{"message":"Unknown model"}}"#),
        ])
        do {
            _ = try await collect(LLMClient(transport: t).stream(provider: groq, apiKey: "k", model: "x", messages: [LLMMessage("user", "a", images: [photo])]))
            Issue.record("une erreur était attendue")
        } catch let e as LLMError {
            #expect(e.status == 400)
            #expect(e.message == "Unknown model")
        }
        #expect(t.count == 1)
    }

    @Test("Anthropic : repli sans réflexion, puis sans images")
    func anthropicBoth() async throws {
        let ok = [
            #"data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"Hi"}}"#,
            #"data: {"type":"message_stop"}"#,
        ].joined(separator: "\n")
        let t = FakeTransport([
            .init(status: 400, body: "réglage refusé"),
            .init(status: 400, body: #"{"error":{"message":"image input is not supported"}}"#),
            .init(body: ok),
        ])
        let (text, _) = try await collect(LLMClient(transport: t).stream(
            provider: anthropic, apiKey: "sk", model: "claude-opus-5-5",
            messages: [LLMMessage("user", "Vois", images: [photo])], options: LLMOptions(level: .eleve)
        ))
        #expect(text == "Hi")
        #expect(t.count == 3)
        #expect(t.body(2)["output_config"] == nil)
        let last = t.body(2)["messages"] as? [[String: String]]
        #expect(last?.first?["content"] == "Vois\n\n(image non prise en charge par ce modèle)")
    }

    @Test("refus d'images : seulement une erreur 400/415/422 qui en parle")
    func refusalText() {
        #expect(ChatImages.refusesImages(status: 400, body: "Model does not support vision"))
        #expect(ChatImages.refusesImages(status: 422, body: "multimodal input not allowed"))
        #expect(ChatImages.refusesImages(status: 400, body: "messages[0].content must be a string"))
        #expect(!ChatImages.refusesImages(status: 401, body: "image"))
        #expect(!ChatImages.refusesImages(status: 400, body: "Unknown model"))
    }
}

@Suite("Images : conversations")
struct ImageChatTests {
    @Test("le champ images est facultatif et relu")
    func json() throws {
        var m = ChatMessage(role: .user, content: "Regarde", images: ["a.jpg", "b.jpg"])
        m.imagePrompt = nil
        let data = try JSONEncoder().encode(m)
        let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(raw?["images"] as? [String] == ["a.jpg", "b.jpg"])
        #expect(raw?["imagePrompt"] == nil && raw?["imageCount"] == nil)
        let back = try JSONDecoder().decode(ChatMessage.self, from: data)
        #expect(back.images == ["a.jpg", "b.jpg"])
        // Un ancien message, sans le champ.
        let old = try JSONDecoder().decode(ChatMessage.self, from: Data(#"{"role":"user","content":"x","at":"2026-01-01T00:00:00Z"}"#.utf8))
        #expect(old.images.isEmpty && old.imagePrompt == nil && old.imageCount == 0)
        // Sans image, rien de nouveau n'est écrit.
        let plain = try JSONSerialization.jsonObject(with: JSONEncoder().encode(ChatMessage(role: .user, content: "x"))) as? [String: Any]
        #expect(plain?["images"] == nil)
        let made = ChatMessage(role: .assistant, content: "Image créée", images: ["c.png"], imagePrompt: "un chat", imageCount: 2)
        let again = try JSONDecoder().decode(ChatMessage.self, from: JSONEncoder().encode(made))
        #expect(again.imagePrompt == "un chat" && again.imageCount == 2)
    }

    @Test("une photo sans texte part au modèle")
    func photoOnlyHistory() {
        let msgs = [ChatMessage(role: .user, content: "", images: ["a.jpg"])]
        let (h, dropped) = ChatLogic.recentHistory(msgs, budgetTokens: 1000)
        #expect(h.count == 1 && dropped == 0)
        let out = ChatImages.attach(h, from: msgs, dropped: dropped) { _ in LLMImage(base64: "QUJD") }
        #expect(out[0].images.count == 1)
    }

    @Test("seules les images des derniers messages sont renvoyées")
    func budget() {
        var msgs: [ChatMessage] = []
        for i in 0..<5 {
            msgs.append(ChatMessage(role: .user, content: "photo \(i)", images: ["\(i)a.jpg", "\(i)b.jpg"]))
            msgs.append(ChatMessage(role: .assistant, content: "vu \(i)"))
        }
        msgs.append(ChatMessage(role: .assistant, content: "", error: true))
        let (h, dropped) = ChatLogic.recentHistory(msgs, budgetTokens: 0)
        let out = ChatImages.attach(h, from: msgs, dropped: dropped) { LLMImage(base64: $0) }
        let counts = out.filter { $0.role == "user" }.map(\.images.count)
        #expect(counts == [0, 0, 2, 2, 2])
        #expect(out[0].content == "photo 0\n\n(2 images jointes ici, non renvoyées)")
        #expect(out[8].images.map(\.base64) == ["4a.jpg", "4b.jpg"])
        // Une image introuvable sur l'appareil est sautée.
        let missing = ChatImages.attach(h, from: msgs, dropped: dropped) { $0.hasPrefix("4") ? nil : LLMImage(base64: $0) }
        #expect(missing[8].images.isEmpty)
        #expect(missing[8].content.contains("non renvoyées"))
    }

    @Test("historique coupé par la mémoire : les images suivent les bons messages")
    func trimmed() {
        let msgs = [
            ChatMessage(role: .user, content: String(repeating: "a", count: 4000), images: ["old.jpg"]),
            ChatMessage(role: .assistant, content: "ok"),
            ChatMessage(role: .user, content: "nouvelle", images: ["new.jpg"]),
        ]
        let (h, dropped) = ChatLogic.recentHistory(msgs, budgetTokens: 100)
        #expect(dropped == 1)
        let out = ChatImages.attach(h, from: msgs, dropped: dropped) { LLMImage(base64: $0) }
        #expect(out.last?.images.map(\.base64) == ["new.jpg"])
    }

    @Test("fichiers : enregistrer, relire, supprimer ; noms suspects refusés")
    func store() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("img-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let s = ChatImageStore(directory: dir)
        let name = try s.save(Data(fakeGIF.utf8))
        #expect(name.hasSuffix(".gif"))
        #expect(s.exists(name))
        #expect(s.load(name) == Data(fakeGIF.utf8))
        #expect(s.llmImage(name)?.mimeType == "image/gif")
        #expect(s.sizeOnDisk() == fakeGIF.utf8.count)
        #expect(s.url("../secret") == nil && s.url("a/b.jpg") == nil && s.url(".x") == nil)
        s.delete([name, "../nope"])
        #expect(!s.exists(name))
        let other = try s.save(Data([0xFF, 0xD8, 0xFF, 0xE0]))
        #expect(other.hasSuffix(".jpg"))
        s.deleteAll()
        #expect(!FileManager.default.fileExists(atPath: dir.path))
    }

    @Test("type d'image reconnu à ses premiers octets")
    func mime() {
        #expect(ChatImageStore.mimeType(of: Data([0x89, 0x50, 0x4E, 0x47, 0, 0, 0, 0])) == "image/png")
        #expect(ChatImageStore.mimeType(of: Data("RIFFabcdWEBP".utf8)) == "image/webp")
        #expect(ChatImageStore.looksLikeImage(Data([0xFF, 0xD8, 0xFF, 0x00])))
        #expect(!ChatImageStore.looksLikeImage(Data("<html>".utf8)))
    }

    @Test("modèles qui voient les images (d'après leur nom)")
    func vision() {
        for (p, m) in [("openai", "gpt-4o-mini"), ("openai", "gpt-5"), ("anthropic", "claude-opus-5-5"), ("gemini", "gemini-2.5-flash"),
                       ("ollama", "llava:13b"), ("ollama", "qwen2.5-vl:7b"), ("mistral", "pixtral-large-latest"),
                       ("groq", "meta-llama/llama-4-scout-17b-16e-instruct"), ("ollama", "llama3.2-vision"), ("pollinations", "openai"),
                       ("openai", "o3"), ("openrouter", "openai/o4-mini")] {
            #expect(ModelVision.likelySees(providerId: p, model: m), "\(m)")
        }
        for (p, m) in [("groq", "llama-3.1-8b-instant"), ("deepseek", "deepseek-chat"), ("openai", "gpt-oss-120b"),
                       ("openai", "o3-mini"), ("mistral", "codestral-latest"), ("ollama", "qwen3:8b")] {
            #expect(!ModelVision.likelySees(providerId: p, model: m), "\(m)")
        }
    }
}

@Suite("Images : création")
struct ImageGenTests {
    @Test("/image [nombre] description")
    func command() {
        #expect(ImageGenCommand.parse("/image 3 un chat astronaute") == ImageGenCommand(count: 3, prompt: "un chat astronaute"))
        #expect(ImageGenCommand.parse("/image un chat") == ImageGenCommand(count: 1, prompt: "un chat"))
        #expect(ImageGenCommand.parse("/images 9 des chiens") == ImageGenCommand(count: 4, prompt: "des chiens"))
        #expect(ImageGenCommand.parse("/IMAGE x2 un phare") == ImageGenCommand(count: 2, prompt: "un phare"))
        #expect(ImageGenCommand.parse("/image 2048 en pixel art") == ImageGenCommand(count: 1, prompt: "2048 en pixel art"))
        #expect(ImageGenCommand.parse("/image")?.prompt == "")
        #expect(ImageGenCommand.parse("/imagine un chat") == nil)
        #expect(ImageGenCommand.parse("une /image") == nil)
        #expect(ImageGenCommand.suggestion(for: "/im")?.insert == "/image ")
        #expect(ImageGenCommand.suggestion(for: "/") != nil)
        #expect(ImageGenCommand.suggestion(for: "/review") == nil)
        #expect(ImageGenCommand.suggestion(for: "/image un") == nil)
    }

    @Test("adresse Pollinations : texte encodé, taille, graine, sans logo, Flux")
    func url() throws {
        let u = try #require(ImageGenClient.pollinationsURL(prompt: "un chat  astronaute / été ?&", width: 1024, height: 1536, seed: 42))
        #expect(u.absoluteString == "https://image.pollinations.ai/prompt/un%20chat%20astronaute%20%2F%20%C3%A9t%C3%A9%20%3F%26?width=1024&height=1536&seed=42&nologo=true&model=flux")
    }

    @Test("Pollinations : une requête par image, en parallèle, graines différentes")
    func pollinations() async throws {
        let t = FakeTransport((0..<3).map { _ in .init(headers: ["content-type": "image/jpeg"], body: fakeGIF) })
        let r = try await ImageGenClient(transport: t).generate(prompt: "un chat", count: 3, shape: .landscape, engine: .auto, openAIKey: nil)
        #expect(r.images.count == 3 && r.failed == 0)
        #expect(r.engine == .pollinations && r.cost == 0)
        #expect(r.modelKey == "pollinations::flux")
        #expect(t.count == 3)
        let urls = t.requests.compactMap { $0.url?.absoluteString }
        #expect(urls.allSatisfy { $0.hasPrefix("https://image.pollinations.ai/prompt/un%20chat?width=1536&height=1024&seed=") })
        #expect(Set(urls).count == 3)
        #expect(r.images[0].mimeType == "image/jpeg")
    }

    @Test("Pollinations : nouvel essai après une saturation")
    func retry() async throws {
        let t = FakeTransport([.init(status: 503, body: "busy"), .init(headers: ["content-type": "text/html"], body: "<html>"), .init(body: fakeGIF)])
        let r = try await ImageGenClient(transport: t, retryDelay: { _ in .milliseconds(1) }).pollinations(prompt: "x", count: 1, shape: .square)
        #expect(r.images.count == 1)
        #expect(r.images[0].mimeType == "image/gif")
        #expect(t.count == 3)
    }

    @Test("Pollinations : erreurs lisibles, pas de nouvel essai sur un refus")
    func errors() async throws {
        let busy = FakeTransport((0..<3).map { _ in .init(status: 429, body: "Too Many Requests") })
        do {
            _ = try await ImageGenClient(transport: busy, retryDelay: { _ in .milliseconds(1) }).pollinations(prompt: "x", count: 1, shape: .square)
            Issue.record("une erreur était attendue")
        } catch let e as LLMError {
            #expect(e.status == 429)
            #expect(e.message.contains("saturé"))
        }
        #expect(busy.count == 3)
        let refused = FakeTransport([.init(status: 400, body: #"{"error":"Bad prompt"}"#)])
        do {
            _ = try await ImageGenClient(transport: refused).pollinations(prompt: "x", count: 1, shape: .square)
            Issue.record("une erreur était attendue")
        } catch let e as LLMError {
            #expect(e.message == "Pollinations a refusé la demande : Bad prompt")
        }
        #expect(refused.count == 1)
    }

    @Test("Pollinations : une image ratée sur deux, l'autre est gardée")
    func partial() async throws {
        let t = FakeTransport([.init(status: 400, body: "non"), .init(body: fakeGIF)])
        let r = try await ImageGenClient(transport: t).pollinations(prompt: "x", count: 2, shape: .square)
        #expect(r.images.count == 1 && r.failed == 1)
        #expect(ImageGenCommand.caption(prompt: "x", made: 1, requested: 2) == "Image créée : « x »\n\n(1 image n'a pas pu être créée.)")
        #expect(ImageGenCommand.caption(prompt: "x", made: 3, requested: 3) == "3 images créées : « x »")
    }

    @Test("OpenAI : requête gpt-image-1, images en base64, coût")
    func openAI() async throws {
        let b64 = Data(fakeGIF.utf8).base64EncodedString()
        let body = #"{"data":[{"b64_json":"\#(b64)"},{"b64_json":"\#(b64)"}],"usage":{"input_tokens":20,"output_tokens":2000,"input_tokens_details":{"text_tokens":20,"image_tokens":0}}}"#
        let t = FakeTransport([.init(headers: ["content-type": "application/json"], body: body)])
        let r = try await ImageGenClient(transport: t).generate(prompt: "un chat", count: 2, shape: .portrait, engine: .auto, openAIKey: "sk-1")
        #expect(r.engine == .openai && r.modelKey == "openai::gpt-image-1")
        #expect(r.images.count == 2)
        #expect(r.images[0].data == Data(fakeGIF.utf8))
        #expect(abs((r.cost ?? 0) - (20 * 5 + 2000 * 40) / 1e6) < 1e-9)
        let req = t.requests[0]
        #expect(req.url?.absoluteString == "https://api.openai.com/v1/images/generations")
        #expect(req.httpMethod == "POST")
        #expect(req.value(forHTTPHeaderField: "authorization") == "Bearer sk-1")
        let sent = t.body(0)
        #expect(sent["model"] as? String == "gpt-image-1")
        #expect(sent["n"] as? Int == 2)
        #expect(sent["size"] as? String == "1024x1536")
        #expect(sent["prompt"] as? String == "un chat")
        #expect(ImageGenClient.openAICost(usage: nil, count: 2, shape: .square) == 0.084)
    }

    @Test("OpenAI refuse : erreur lisible, ou Pollinations en automatique")
    func openAIFallback() async throws {
        let refused = #"{"error":{"message":"Your organization must be verified to use the model gpt-image-1"}}"#
        let t = FakeTransport([.init(status: 403, body: refused)])
        do {
            _ = try await ImageGenClient(transport: t).generate(prompt: "x", count: 1, shape: .square, engine: .openai, openAIKey: "sk")
            Issue.record("une erreur était attendue")
        } catch let e as LLMError {
            #expect(e.status == 403)
            #expect(e.message.hasPrefix("OpenAI demande de vérifier votre organisation"))
        }
        let auto = FakeTransport([.init(status: 401, body: #"{"error":{"message":"Incorrect API key"}}"#), .init(body: fakeGIF)])
        let r = try await ImageGenClient(transport: auto).generate(prompt: "x", count: 1, shape: .square, engine: .auto, openAIKey: "sk")
        #expect(r.engine == .pollinations && r.images.count == 1)
        #expect(r.note?.contains("Pollinations") == true)
        #expect(auto.requests[1].url?.host == "image.pollinations.ai")
    }

    @Test("moteur : automatique selon la clé ; OpenAI sans clé est expliqué")
    func engine() async throws {
        #expect(ImageGenEngine.auto.resolved(hasOpenAIKey: true) == .openai)
        #expect(ImageGenEngine.auto.resolved(hasOpenAIKey: false) == .pollinations)
        #expect(ImageGenEngine.pollinations.resolved(hasOpenAIKey: true) == .pollinations)
        #expect(ImageGenEngine.named("rien") == .auto)
        #expect(ImageGenShape.named("landscape").size == "1536x1024")
        let t = FakeTransport([])
        await #expect(throws: LLMError.self) {
            _ = try await ImageGenClient(transport: t).generate(prompt: "x", count: 1, shape: .square, engine: .openai, openAIKey: nil)
        }
        await #expect(throws: LLMError.self) {
            _ = try await ImageGenClient(transport: t).generate(prompt: "  ", count: 1, shape: .square, engine: .pollinations, openAIKey: nil)
        }
        #expect(t.count == 0)
    }
}
