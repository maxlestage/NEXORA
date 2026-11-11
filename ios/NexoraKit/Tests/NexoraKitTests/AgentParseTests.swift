import Foundation
import Testing
@testable import NexoraKit

func nativeText(_ name: String, _ arguments: String) -> String {
    var c = ToolCallCollector()
    c.add(ChatDelta(toolCalls: [ToolCallPart(0, name: name, arguments: arguments)]))
    return c.render()!
}

func same(_ a: [String: Any], _ b: [String: Any]) -> Bool {
    LooseJSON.string(a) == LooseJSON.string(b)
}

/// La lecture des actions écrites par les modèles, quelle que soit leur forme.
@Suite("Agent : lecture des actions")
struct AgentParseTests {
    @Test("dans un bloc ```json, avec du code écrit de travers")
    func looseBlock() {
        let calls = parseToolCalls(
            "Je modifie.\n```json\n{\"tool\": \"edit_file\", \"args\": {\"path\": \"src/main.rs\", \"old\": \"    app\n}\", \"new\": \"    app.get(\\\"/sante\\\", sante);\n    app\n}\"}}\n```"
        )
        #expect(calls.count == 1)
        #expect(calls.first?.tool == "edit_file")
        #expect(calls.first?.args["old"] as? String == "    app\n}")
        #expect(calls.first?.args["new"] as? String == "    app.get(\"/sante\", sante);\n    app\n}")
    }

    @Test("sans bloc de code : l'action est comprise aussi")
    func bare() {
        let calls = parseToolCalls("Voici : {\"tool\": \"write_file\", \"args\": {\"path\": \"a.txt\", \"content\": \"ligne 1\nligne 2\"}}")
        #expect(calls.first?.tool == "write_file")
        #expect(calls.first?.args["content"] as? String == "ligne 1\nligne 2")
    }

    @Test("appel natif (tool_calls) aux arguments mal échappés")
    func nativeLoose() {
        let call = parseToolCalls(nativeText("edit_file", "{\"path\": \"a.rs\", \"old\": \"\", \"new\": \"x\ny\"}")).first
        #expect(call.map { same($0.args, ["path": "a.rs", "old": "", "new": "x\ny"]) } == true)
    }

    @Test("autres écritures d'une action : {\"finish\": …} et {\"name\": …}")
    func otherForms() {
        #expect(parseToolCalls(#"{"thought":"x","finish":{"summary":"fait"}}"#).first?.tool == "finish")
        let c = parseToolCalls(#"{"name":"read_file","arguments":"{\"path\":\"a.md\"}"}"#).first
        #expect(c?.tool == "read_file")
        #expect(c?.args["path"] as? String == "a.md")
        #expect(parseToolCalls("```json\n{\"summary\":\"fini\"}\n```").first?.tool == "finish")
    }

    @Test("noms d'outils inventés ramenés aux vrais")
    func canonical() {
        #expect(canonicalTool("repo_browser.search_code") == "search_code")
        #expect(canonicalTool("functions.read_file") == "read_file")
        #expect(canonicalTool("Grep") == "search_code")
        #expect(canonicalTool("str_replace") == "edit_file")
        #expect(parseToolCalls(#"{"tool":"repo_browser.edit_file","args":{"path":"a"}}"#).first?.tool == "edit_file")
        for n in ["print_tree", "repo_browser.print_tree", "tree", "show_tree", "file_tree", "directory_tree"] {
            #expect(canonicalTool(n) == "list_files", "\(n)")
        }
    }

    @Test("plusieurs blocs d'actions dans une réponse : toutes sont faites")
    func multiBlocks() {
        let reply = "```json\n{\"thought\":\"Je corrige\",\"tool\":\"repo_browser.edit_file\",\"args\":{\"path\":\"lib/a.dart\",\"old\":\"x\",\"new\":\"y\"}}\n```"
            + "<|start|>assistant<|channel|>commentary<|message|>Now create test file.\n"
            + "```json\n{\"actions\":[{\"tool\":\"repo_browser.write_file\",\"args\":{\"path\":\"test/a_test.dart\"}}]}\n```\n"
            + "```dart\nvoid main() {}\n```\n"
        let calls = parseToolCalls(reply)
        #expect(calls.map(\.tool) == ["edit_file", "write_file"])
        #expect(calls.first?.args["new"] as? String == "y")
        #expect(calls.first?.thought == "Je corrige")
        #expect(calls.last?.args["content"] as? String == "void main() {}\n")
        #expect(calls.last?.thought == "")
    }

    @Test("un contenu de fichier en JSON reste un contenu")
    func jsonContent() {
        let calls = parseToolCalls("```json\n{\"tool\":\"write_file\",\"args\":{\"path\":\"conf.json\"}}\n```\n```json\n{\"summary\":\"pas une fin\"}\n```\n")
        #expect(calls.count == 1)
        #expect(calls.first?.args["content"] as? String == "{\"summary\":\"pas une fin\"}\n")
    }

    @Test("edit_file : ancien puis nouveau passage, puis l'action suivante")
    func editBlocks() {
        let calls = parseToolCalls(
            "```json\n{\"tool\":\"edit_file\",\"args\":{\"path\":\"a.dart\"}}\n```\n```dart\nold\n```\n```dart\nnew\n```\n```json\n{\"tool\":\"finish\",\"args\":{\"summary\":\"ok\"}}\n```\n"
        )
        #expect(calls.map(\.tool) == ["edit_file", "finish"])
        #expect(calls.first?.args["old"] as? String == "old")
        #expect(calls.first?.args["new"] as? String == "new")
    }

    @Test("les arguments envoyés dans l'élément suivant rejoignent l'action")
    func splitArgs() {
        let calls = parseToolCalls(
            "```json\n{\"actions\":[{\"tool\":\"repo_browser.edit_file\",\"args\":{\"path\":\"README.md\"}},{\"old\":\"## Crédits\",\"new\":\"## Contribuer\\n\\n1. Tests\\n\\n## Crédits\"}]}\n```"
        )
        #expect(calls.count == 1)
        #expect(calls.first?.args["path"] as? String == "README.md")
        #expect(calls.first?.args["old"] as? String == "## Crédits")
        #expect((calls.first?.args["new"] as? String)?.hasPrefix("## Contribuer") == true)

        let w = parseToolCalls(#"{"actions":[{"tool":"write_file","args":{"path":"a.txt"}},{"content":"bonjour"},{"tool":"finish","args":{"summary":"ok"}}]}"#)
        #expect(w.map(\.tool) == ["write_file", "finish"])
        #expect(same(w[0].args, ["path": "a.txt", "content": "bonjour"]))

        let n = parseToolCalls(#"{"actions":[{"tool":"edit_file","arguments":{"path":"a.md","old":"x"}},{"args":{"path":"b.md","new":"y"}}]}"#)
        #expect(n.count == 1 && same(n[0].args, ["path": "a.md", "old": "x", "new": "y"]))

        let t = parseToolCalls(#"{"actions":[{"tool":"edit_file","args":"{\"path\": \"a.md\"}"},{"old":"x","new":"y"}]}"#)
        #expect(t.count == 1 && same(t[0].args, ["path": "a.md", "old": "x", "new": "y"]))

        let h = parseToolCalls(#"{"actions":[{"old":"x"},{"tool":"read_file","args":{"path":"a"}}]}"#)
        #expect(h.count == 1 && h[0].tool == "read_file" && same(h[0].args, ["path": "a"]))
    }

    @Test("une accolade dans le texte avant le JSON ne masque pas l'action")
    func strayBrace() {
        let r = parseToolCalls("Je corrige f() { return 1; } puis : {\"tool\":\"read_file\",\"args\":{\"path\":\"a.txt\"}}")
        #expect(r.map(\.tool) == ["read_file"])
        #expect(r.first?.args["path"] as? String == "a.txt")
        #expect(parseToolCalls("Note {x}\n{\"tool\":\"read_file\",\"args\":{\"path\":\"b.txt\"}}").first?.args["path"] as? String == "b.txt")
        #expect(parseToolCalls("du texte {sans} action").isEmpty)
    }

    @Test("arguments auxquels il ne manque que la fermeture")
    func unclosed() {
        let call = parseToolCalls(nativeText("repo_browser.read_file", #"{"path":"site/src/main.rs","line":1800,"end":1860"#)).first
        #expect(call?.tool == "read_file")
        #expect(call.map { same($0.args, ["path": "site/src/main.rs", "line": 1800, "end": 1860]) } == true)
        let w = parseToolCalls(nativeText("write_file", #"{"path": "a.dart", "content": "void ma"#)).first
        #expect(w?.args["raw"] is String)
        let s = parseToolCalls("```json\n{\"tool\": \"read_file\", \"args\": \"{\\\"path\\\": \\\"lib/a.dart\\\", \\\"line\\\": 12}\"}\n```").first
        #expect(s.map { same($0.args, ["path": "lib/a.dart", "line": 12]) } == true)
        let cut = parseToolCalls("```json\n{\"tool\": \"find_in_file\", \"args\": \"{\\\"path\\\": \\\"a.rs\\\", \\\"pattern\\\": \\\"fn app\\\"\"}\n```").first
        #expect(cut.map { same($0.args, ["path": "a.rs", "pattern": "fn app"]) } == true)
    }

    @Test("réflexion sans action : lisible, pas en JSON brut")
    func actionless() {
        let stuck = "```json\n{\"demande\": \"Ajoute une fonction somme\", \"thought\": \"Accès refusé, je ne peux rien faire.\"}\n```"
        #expect(actionlessThought(stuck) == "🎯 Ajoute une fonction somme\nAccès refusé, je ne peux rien faire.")
        #expect(actionlessThought("Je réfléchis encore.") == nil)
        #expect(parseToolCalls(stuck).isEmpty)
    }

    @Test("blocs de code : barrières plus longues, CRLF, bloc en milieu de ligne")
    func blocks() {
        let b = codeBlocks("````md\n```dart\nx\n```\n````\n")
        #expect(b.count == 1)
        #expect(b.first?.body == "```dart\nx\n```\n")
        #expect(b.first?.lang == "md")
        let crlf = codeBlocks("```rust\r\nfn a() {}\r\n```\r\n")
        #expect(crlf.first?.body == "fn a() {}\n")
        #expect(crlf.first?.lang == "rust")
        let inline = codeBlocks("Voici : ```json\n{\"a\":1}\n```")
        #expect(inline.first?.body == "{\"a\":1}\n")
        #expect(inline.first?.lang == "json")
    }

    @Test("contenu attendu : seul, avant les actions, ou perdu")
    func pending() {
        #expect(pendingContent("```dart\nvoid main() {}\n```") == "void main() {}\n")
        #expect(pendingContent("ligne 1\nligne 2\nligne 3") == "ligne 1\nligne 2\nligne 3\n")
        #expect(pendingContent(act(["tool": "read_file", "args": ["path": "a"]])) == nil)
        let lead = "```rust\nfn t() {}\n```\n" + act(["tool": "read_file", "args": ["path": "a"]])
        #expect(leadingContent(lead) == "fn t() {}\n")
        #expect(leadingContent(act(["tool": "read_file", "args": ["path": "a"]])) == nil)
        #expect(lostContentNote("a.rs").contains("a.rs n'a PAS été écrit"))
    }

    @Test("contenu écrit avant le write_file : repris")
    func contentBefore() {
        let reply = "Voici le test :\n```rust\n#[test]\nfn t() {}\n```\n```json\n{\"tool\":\"write_file\",\"args\":{\"path\":\"tests/t.rs\"}}\n```"
        let c = parseToolCalls(reply)
        #expect(c.first?.args["content"] as? String == "#[test]\nfn t() {}\n")
    }

    @Test("résumés qui laissent du travail de côté")
    func excuses() {
        #expect(unfinishedWorkIn("Fait. Je pourrais aussi ajouter un test.") == "Je pourrais")
        #expect(unfinishedWorkIn("Limites : pas de tests") != nil)
        #expect(unfinishedWorkIn("Ce n'était pas demandé") != nil)
        #expect(unfinishedWorkIn("✅ Route /sante ajoutée et testée.") == nil)
    }
}

@Suite("Agent : JSON écrit de travers")
struct AgentLooseJSONTests {
    @Test("retours à la ligne bruts, échappements invalides, guillemets du code")
    func loose() {
        #expect(LooseJSON.decodeLoose("{\"path\": \"a.rs\", \"new\": \"fn a() {\n\tb();\n}\"}").map { same($0, ["path": "a.rs", "new": "fn a() {\n\tb();\n}"]) } == true)
        #expect(LooseJSON.decodeLoose(#"{"a": "it\'s"}"#)?["a"] as? String == "it's")
        #expect(LooseJSON.decodeLoose(#"{"re": "\d+\.\w"}"#)?["re"] as? String == #"\d+\.\w"#)
        #expect(LooseJSON.decodeLoose(#"{"path": "src/main.rs", "new": "app.get("/sante", sante);"}"#)?["new"] as? String == #"app.get("/sante", sante);"#)
        #expect(LooseJSON.decodeLoose(#"{"a": 1}{"a": 1}"#).map { same($0, ["a": 1]) } == true)
        #expect(LooseJSON.decodeLoose("{\"path\": \"a.rs\", \"new\": \"fn a() {") == nil)
        #expect(LooseJSON.decodeToolArgs(#"{"path": "a", "tags": ["x", "y","#).map { same($0, ["path": "a", "tags": ["x", "y"]]) } == true)
        #expect(LooseJSON.decodeToolArgs(#"{"path": "a.dart", "content":"#) == nil)
    }
}

/// Les mêmes cas, dans une vraie session.
@Suite("Agent : actions dans une session")
@MainActor
struct AgentNativeSessionTests {
    static let readme = "# Projet\n\nUn projet.\n"

    func build(_ llm: ScriptLLM, max: Int = 24) -> AgentRun {
        makeRun(llm, hub: repoHub(["README.md": Self.readme]), task: "Ajoute une section Contribuer à la fin du README", checks: false, maxSteps: max)
    }

    func act(_ tool: String, _ args: [String: Any]) -> String { NexoraKitTests.act(["tool": tool, "args": args]) }

    @Test("les appels d'outils natifs (tool_calls) sont compris")
    func native() async {
        let run = build(ScriptLLM(replies: [
            .native("read_file", #"{"path":"README.md"}"#),
            .native("edit_file", ###"{"path":"README.md","old_string":"","new_string":"## Contribuer\n\nBienvenue."}"###),
            .native("finish", #"{"summary":"Section ajoutée"}"#),
        ]))
        await run.run()
        #expect(run.summary == "Section ajoutée")
        #expect(run.draft("README.md")?.contains("## Contribuer") == true)
        #expect(run.draft("README.md")?.hasPrefix("# Projet") == true)
    }

    @Test("un seul bloc pour edit_file : ajout à la fin, une seule fois")
    func oneBlock() async {
        let once = NexoraKitTests.act(["tool": "edit_file", "args": ["path": "README.md"]]) + "\n```\n## Contribuer\n```"
        let run = build(ScriptLLM([once, once, act("finish", ["summary": "ok"])]))
        await run.run()
        #expect(run.draft("README.md")?.components(separatedBy: "## Contribuer").count == 2)
        #expect(run.summary == "ok")
    }

    @Test("une boucle sur la même action est arrêtée")
    func loop() async {
        let read = act("read_file", ["path": "README.md"])
        let run = build(ScriptLLM([read, read, read, read, read]))
        await run.run()
        #expect(run.steps.last?.kind == .error)
        #expect(run.steps.last?.text.contains("en boucle") == true)
    }

    @Test("réponses vides : redemandées, puis message clair")
    func empty() async {
        let run = build(ScriptLLM(["", "", ""]))
        await run.run()
        #expect(run.steps.last?.text.contains("réponse vide") == true)
        #expect(!run.history.contains { $0.role == "assistant" })
    }

    @Test("limite d'étapes : l'agent fait le point et continue jusqu'au bout")
    func limit() async {
        let run = build(ScriptLLM([
            act("read_file", ["path": "README.md", "start": 1]),
            act("read_file", ["path": "README.md", "start": 2]),
            act("read_file", ["path": "README.md", "start": 3]),
            act("finish", ["summary": "Fini après le point"]),
        ]), max: 2)
        await run.run()
        #expect(run.summary == "Fini après le point")
        #expect(run.steps.contains { $0.text.contains("je fais le point et je continue") })
    }

    @Test("modèle qui ne répond plus : l'agent continue avec un autre")
    func fallback() async {
        let llm = ScriptLLM()
        llm.dynamic = { _, _, host in
            host.contains("groq")
                ? .error(401, #"{"error":{"message":"Invalid API Key"}}"#)
                : .text(NexoraKitTests.act(["tool": "finish", "args": ["summary": "Fini avec Pollinations"]]))
        }
        let run = makeRun(llm, hub: Routes { _ in (200, #"{"tree":[]}"#) }, task: "Dis bonjour", checks: false)
        let polli = Catalog.providers.first { $0.id == "pollinations" }!
        run.fallback = { _, tried in tried.contains("pollinations::openai") ? nil : (polli, nil, "openai") }
        await run.run()
        #expect(run.summary == "Fini avec Pollinations")
        #expect(run.provider.id == "pollinations")
        #expect(run.steps.contains { $0.text.contains("Je continue avec") })
        #expect(llm.count >= 2)
    }

    @Test("search_code cherche dans le contenu, avec le code autour (et les noms collés)")
    func search() async throws {
        let run = build(ScriptLLM([act("search_code", ["query": "un projet"]), act("finish", ["summary": "ok"])]))
        await run.run()
        let result = try #require(run.history.first { $0.content.hasPrefix("Résultat de search_code") }).content
        #expect(result.contains("README.md"))
        #expect(result.contains(">3: Un projet."))

        let run2 = build(ScriptLLM([act("search_code", ["query": "unProjet"]), act("finish", ["summary": "ok"])]))
        await run2.run()
        let r2 = try #require(run2.history.first { $0.content.hasPrefix("Résultat de search_code") }).content
        #expect(r2.contains("ignorant espaces"))
        #expect(r2.contains(">3: Un projet."))
    }

    @Test("conversation trop longue : historique allégé, l'agent continue")
    func tooLong() async {
        let run = build(ScriptLLM(replies: [
            .error(400, #"{"error":{"message":"This model's maximum context length is 8192 tokens"}}"#),
            .text(act("read_file", ["path": "README.md"])),
            .text(act("finish", ["summary": "ok"])),
        ]))
        await run.run()
        #expect(run.summary == "ok")
        #expect(run.steps.contains { $0.text.contains("historique allégé") })
    }

    @Test("arguments mal échappés : la modification est faite ; coupés : renvoyés")
    func badArgs() async {
        let main = "fn app() -> App {\n    let mut app = App::new();\n    app.get(\"/\", accueil);\n    app\n}\n"
        let hub = repoHub(["src/main.rs": main])
        let run = makeRun(ScriptLLM(replies: [
            .native("repo_browser.edit_file", "{\"path\":\"src/main.rs\",\"old\":\"    app\n}\",\"new\":\"    app.get(\"/sante\", sante);\n    app\n}\"}"),
            .native("finish", #"{"summary":"Route ajoutée"}"#),
        ]), hub: hub, task: "Ajoute une route /sante", checks: false)
        run.specs.append("déjà compris")
        await run.run()
        #expect(run.summary == "Route ajoutée")
        #expect(run.draft("src/main.rs")?.contains("app.get(\"/sante\", sante);") == true)
        #expect(run.draft("src/main.rs")?.hasPrefix("fn app() -> App {") == true)
        #expect(!run.steps.contains { $0.kind == .error })

        let cut = makeRun(ScriptLLM(replies: [
            .native("edit_file", #"{"path":"src/main.rs","old":"    app\n}","new":"    app.get("#),
            .native("finish", #"{"summary":"Abandon"}"#),
        ]), hub: hub, task: "Ajoute une route /sante", checks: false)
        cut.specs.append("déjà compris")
        await cut.run()
        let err = cut.steps.first { $0.kind == .error }?.text ?? ""
        #expect(err.contains("pas du JSON valide"))
        #expect(!err.contains("il manque le texte"))
        #expect(cut.changes.isEmpty)
    }

    @Test("modèle qui ne choisit jamais d'action : arrêt rapide ; ou un autre modèle termine")
    func neverActs() async {
        let stuck = "```json\n{\"demande\": \"Ajoute une fonction somme\", \"thought\": \"Accès refusé, je ne peux rien faire.\"}\n```"
        let done = "```json\n{\"tool\": \"finish\", \"args\": {\"summary\": \"Fait autrement\"}}\n```"
        let llm = ScriptLLM()
        llm.dynamic = { _, _, _ in .text(stuck) }
        let run = makeRun(llm, hub: Routes { _ in (200, #"{"tree":[]}"#) }, task: "Ajoute une fonction somme")
        await run.run()
        #expect(!run.finished && !run.running)
        #expect(run.steps.last?.text.contains("sans jamais choisir d'action") == true)
        #expect(llm.count < 10)
        let thoughts = run.steps.filter { $0.kind == .thought }
        #expect(!thoughts.isEmpty)
        #expect(!thoughts.contains { $0.text.contains("```") })

        // Un autre modèle prend la suite (après trois réponses sans action) et termine.
        let llm2 = ScriptLLM([stuck, stuck, stuck, done, done])
        let run2 = makeRun(llm2, hub: Routes { _ in (200, #"{"tree":[]}"#) }, task: "Ajoute une fonction somme")
        run2.fallback = { _, tried in tried.contains("groq::m2") ? nil : (groq, "k", "m2") }
        await run2.run()
        #expect(run2.model == "m2")
        #expect(run2.summary == "Fait autrement")
        #expect(run2.steps.contains { $0.text.contains("Je continue avec") })
    }
}
