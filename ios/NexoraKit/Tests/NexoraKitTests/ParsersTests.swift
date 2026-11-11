import Foundation
import Testing
@testable import NexoraKit

@Suite("Flux des fournisseurs")
struct ParsersTests {
    @Test("SSE OpenAI")
    func openAI() throws {
        #expect(try StreamLineParser.openAI(#"data: {"choices":[{"delta":{"content":"Bon"}}]}"#)?.text == "Bon")
        #expect(try StreamLineParser.openAI("data: [DONE]")?.done == true)
        #expect(try StreamLineParser.openAI(": keep-alive") == nil)
        #expect(try StreamLineParser.openAI(#"data: {"choices":[{"delta":{"reasoning_content":"hmm"}}]}"#)?.thinking == "hmm")
        #expect(throws: LLMError.self) {
            try StreamLineParser.openAI(#"data: {"error":{"message":"quota"}}"#)
        }
    }

    @Test("NDJSON Ollama")
    func ollama() throws {
        var p = StreamLineParser(kind: .ollama)
        #expect(try p.parse(#"{"message":{"role":"assistant","content":"Salut"},"done":false}"#)?.text == "Salut")
        #expect(try p.parse(#"{"done":true}"#)?.done == true)
    }

    @Test("SSE Anthropic")
    func anthropic() throws {
        #expect(try StreamLineParser.anthropic(#"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hi"}}"#)?.text == "Hi")
        #expect(try StreamLineParser.anthropic(#"data: {"type":"message_stop"}"#)?.done == true)
        #expect(try StreamLineParser.anthropic("event: ping") == nil)
    }

    @Test("balises <think> coupées entre les morceaux")
    func thinkSplitter() {
        var s = ThinkSplitter()
        var text = ""
        var thinking = ""
        for p in ["<thi", "nk>je ré", "fléchis</th", "ink>Réponse", " finale"] {
            let d = s.feed(ChatDelta(text: p))
            text += d.text
            thinking += d.thinking
        }
        text += s.flush().text
        #expect(thinking == "je réfléchis")
        #expect(text == "Réponse finale")
    }

    @Test("raisons d'arrêt : OpenAI, Anthropic, Ollama")
    func stopReasons() throws {
        #expect(try StreamLineParser.openAI(#"data: {"choices":[{"delta":{},"finish_reason":"length"}]}"#)?.truncated == true)
        #expect(try StreamLineParser.openAI(#"data: {"choices":[{"delta":{"content":"x"},"finish_reason":"stop"}]}"#)?.truncated == false)
        #expect(try StreamLineParser.anthropic(#"data: {"type":"message_delta","delta":{"stop_reason":"max_tokens"},"usage":{"output_tokens":9}}"#)?.truncated == true)
        var p = StreamLineParser(kind: .ollama)
        #expect(try p.parse(#"{"message":{"content":""},"done":true,"done_reason":"length"}"#)?.truncated == true)
    }

    @Test("tokens : formats OpenAI et Anthropic")
    func usage() throws {
        let d = try StreamLineParser.openAI(#"data: {"choices":[],"usage":{"prompt_tokens":12,"completion_tokens":5}}"#)
        #expect(d?.usage == TokenUsage(12, 5))
        let a = try StreamLineParser.anthropic(#"data: {"type":"message_start","message":{"usage":{"input_tokens":40}}}"#)
        #expect(a?.usage == TokenUsage(40, 0))
    }

    @Test("appels d'outils natifs rendus en bloc d'actions")
    func toolCalls() throws {
        var c = ToolCallCollector()
        let d1 = try StreamLineParser.openAI(#"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"name":"read_file","arguments":"{\"path\":"}}]}}]}"#)
        let d2 = try StreamLineParser.openAI(#"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\"a.rs\"}"}}]}}]}"#)
        c.add(try #require(d1))
        c.add(try #require(d2))
        let block = try #require(c.render())
        #expect(block.contains(#""tool":"read_file""#))
        #expect(block.contains(#""path":"a.rs""#))
    }

    @Test("erreur HTTP lisible")
    func errorBody() {
        #expect(errorFromBody(#"{"error":{"message":"Clé invalide"}}"#) == "Clé invalide")
        #expect(errorFromBody("") == "Réponse vide")
        #expect(errorFromBody(#"{"detail":"Not found"}"#) == "Not found")
    }
}

@Suite("JSON écrit de travers par un modèle")
struct LooseJSONTests {
    @Test("retours à la ligne et tabulations bruts dans une chaîne")
    func rawNewlines() {
        let j = LooseJSON.decodeLoose("{\"path\": \"a.rs\", \"new\": \"fn a() {\n\tb();\n}\"}")
        #expect(j?["path"] as? String == "a.rs")
        #expect(j?["new"] as? String == "fn a() {\n\tb();\n}")
    }

    @Test("échappements invalides : \\' et \\d")
    func badEscapes() {
        #expect(LooseJSON.decodeLoose(#"{"a": "it\'s"}"#)?["a"] as? String == "it's")
        #expect(LooseJSON.decodeLoose(#"{"re": "\d+\.\w"}"#)?["re"] as? String == #"\d+\.\w"#)
        #expect(LooseJSON.decodeLoose(#"{"a": "xé\"y\\"}"#)?["a"] as? String == #"xé"y\"#)
    }

    @Test("guillemets du code non échappés")
    func unescapedQuotes() {
        let j = LooseJSON.decodeLoose(#"{"path": "src/main.rs", "new": "app.get("/sante", sante);"}"#)
        #expect(j?["new"] as? String == #"app.get("/sante", sante);"#)
        #expect(j?["path"] as? String == "src/main.rs")
    }

    @Test("virgule finale, objet répété ou suivi de texte")
    func trailing() {
        let j = LooseJSON.decodeLoose(#"{"a": 1, "b": [1, 2,],}"#)
        #expect(j?["a"] as? Int == 1)
        #expect((j?["b"] as? [Int]) == [1, 2])
        #expect(LooseJSON.decodeLoose(#"{"a": 1}{"a": 1}"#)?["a"] as? Int == 1)
        #expect(LooseJSON.decodeLoose(#"{"a": "x"} voilà"#)?["a"] as? String == "x")
    }

    @Test("un objet coupé avant la fin n'est jamais complété au hasard")
    func cut() {
        #expect(LooseJSON.decodeLoose(#"{"path": "a.rs", "new": "fn a() {"#) == nil)
        #expect(LooseJSON.decodeLoose("pas du json") == nil)
    }

    @Test("arguments sans l'accolade finale : complétés, jamais un texte coupé")
    func toolArgs() {
        let j = LooseJSON.decodeToolArgs(#"{"path": "a.rs", "line": 1800"#)
        #expect(j?["path"] as? String == "a.rs")
        #expect(j?["line"] as? Int == 1800)
        #expect(LooseJSON.decodeToolArgs(#"{"path": "a.rs", "content": "fn a() {"#) == nil)
        #expect(LooseJSON.decodeToolArgs(#"{"path":"#) == nil)
    }
}
