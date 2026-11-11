import Foundation
import Testing
@testable import NexoraKit

// Les bancs d'essai : chacun chronomètre un travail réel de l'app sur des données
// réalistes (longues conversations, centaines de conversations enregistrées,
// réponses Markdown longues…) et vérifie une borne large (ces tests tournent
// aussi en mode debug, en parallèle d'autres). Les temps sont affichés pour
// comparer avant et après une optimisation.

/// La durée d'un travail, en millisecondes.
private func ms(_ body: () throws -> Void) rethrows -> Double {
    let clock = ContinuousClock()
    let start = clock.now
    try body()
    let d = clock.now - start
    return Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
}

private func msAsync(_ body: () async throws -> Void) async rethrows -> Double {
    let clock = ContinuousClock()
    let start = clock.now
    try await body()
    let d = clock.now - start
    return Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
}

private func report(_ name: String, _ value: Double) {
    print("⏱ \(name) : \(String(format: "%.2f", value)) ms")
}

/// Un paragraphe réaliste (texte, code, listes).
private func answer(_ i: Int) -> String {
    """
    Voici la réponse n° \(i). **Les lifetimes** en Rust disent combien de temps vit une référence.

    - point un, avec `du code`
    - point deux
    1. étape une
    2. étape deux

    ```rust
    fn longest<'a>(x: &'a str, y: &'a str) -> &'a str { if x.len() > y.len() { x } else { y } }
    ```
    """
}

private func conversation(_ id: String, messages n: Int, title: String = "Conversation") -> Conversation {
    var c = Conversation(id: id, title: title)
    for i in 0..<n {
        c.messages.append(ChatMessage(role: i % 2 == 0 ? .user : .assistant, content: answer(i), model: "groq::llama"))
    }
    return c
}

private func tempDir() -> URL {
    URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("nexora-perf-\(UUID())")
}

@Suite("Performances", .serialized)
struct PerformanceTests {
    @Test("conversation de 600 messages : enregistrée puis relue")
    func encodeDecodeMessages() throws {
        let c = conversation("long", messages: 600)
        var data = Data()
        let enc = try ms { for _ in 0..<5 { data = try JSONEncoder().encode(c.messages) } } / 5
        var back: [ChatMessage] = []
        let dec = try ms { for _ in 0..<5 { back = try JSONDecoder().decode([ChatMessage].self, from: data) } } / 5
        report("encodage 600 messages", enc)
        report("décodage 600 messages", dec)
        #expect(back.count == 600)
        #expect(back[3].at.timeIntervalSince1970.rounded() == c.messages[3].at.timeIntervalSince1970.rounded())
        #expect(enc + dec < 2000)
    }

    @Test("150 conversations : enregistrements pendant une réponse, liste, recherche")
    func storeIndexAndSearch() async throws {
        let dir = tempDir()
        let store = ConversationStore(directory: dir)
        for i in 0..<150 {
            try await store.save(conversation("c\(i)", messages: 30, title: "Sujet \(i)"))
        }
        var c = conversation("c42", messages: 30, title: "Sujet 42")
        // Comme ChatStore : chaque enregistrement relit l'index.
        let saves = try await msAsync {
            for i in 0..<40 {
                c.messages[29].content += " \(i)"
                try await store.save(c)
                _ = await store.index()
            }
        } / 40
        report("enregistrement + index (150 conversations)", saves)
        let list = await msAsync { for _ in 0..<20 { _ = await store.index() } } / 20
        report("index()", list)
        let open = await msAsync { for i in 0..<20 { _ = await store.load("c\(i * 7)") } } / 20
        report("ouverture d'une conversation", open)
        // Une recherche tapée lettre à lettre (absente des titres : tous les fichiers sont lus).
        var found: [ConversationStore.Meta] = []
        let typed = await msAsync {
            for q in ["l", "lo", "lon", "long", "longe", "longes", "longest"] {
                found = await store.search(q)
            }
        }
        report("recherche tapée (7 frappes)", typed)
        #expect(found.count == 150)
        #expect(await store.search("absent-de-partout").isEmpty)
        #expect(saves < 500 && typed < 20000)
        try await store.deleteAll()
    }

    @Test("Markdown : une longue réponse relue à chaque morceau du flux")
    func markdownStreaming() {
        let text = (0..<120).map(answer).joined(separator: "\n\n")
        var blocks: [MarkdownBlock] = []
        let t = ms { for _ in 0..<10 { blocks = MarkdownBlock.parse(text) } } / 10
        report("MarkdownBlock.parse (\(text.count) car.)", t)
        #expect(blocks.count > 500)
        #expect(t < 2000)
    }

    @Test("journal de session : textes nettoyés (expressions régulières)")
    func regexPlain() {
        let lines = (0..<1500).map { "## Étape \($0) : **lire** `lib/main.dart` et __corriger__" }
        var out = ""
        let t = ms { for l in lines { out = WorkspaceText.plain(l) } }
        report("WorkspaceText.plain × 1500", t)
        #expect(out == "Étape 1499 : lire lib/main.dart et corriger")
        #expect(t < 5000)
    }

    @Test("JSON écrit de travers : un long objet réparé")
    func repairLongJSON() {
        let items = (0..<2500).map { #"{"path": "lib/f\#($0).dart", "line": \#($0),}"# }.joined(separator: ", ")
        let text = #"{"actions": [\#(items),], "note": "fin"}"#
        var fixed: String?
        let t = ms { fixed = LooseJSON.repair(text) }
        report("LooseJSON.repair (2500 objets)", t)
        #expect((LooseJSON.object(fixed ?? "") as? [String: Any])?["note"] as? String == "fin")
        #expect(t < 5000)
    }

    @Test("sessions enregistrées : relues au lancement")
    func sessionsAtLaunch() async throws {
        let dir = tempDir()
        let files = FileSessionFiles(directory: dir)
        for i in 0..<40 {
            let steps: [[String: Any]] = (0..<400).map { ["k": "result", "t": answer($0), "tool": "read_file"] }
            let data = try #require(SessionJSON.encode(["id": "s\(i)", "task": "Mission \(i)", "steps": steps, "provider": "groq"]))
            await files.save("s\(i)", data)
        }
        var n = 0
        let t = await msAsync { n = await files.loadObjects().count }
        report("40 sessions relues", t)
        #expect(n == 40)
        #expect(t < 10000)
        try? FileManager.default.removeItem(at: dir)
    }

    @Test("liste des modèles d'un fournisseur (400 modèles lus en direct)")
    func modelList() throws {
        let p = try #require(Catalog.providers.first { $0.id == "openrouter" })
        let catalog = ModelCatalog.bundled
        let cat = catalog.providers[p.id] ?? []
        let live = cat.map { ModelInfo($0.id) } + (0..<(400 - min(cat.count, 400))).map { ModelInfo("vendor/model-\($0)") }
        var list: [ModelInfo] = []
        let t = ms {
            for _ in 0..<20 {
                list = ModelList.models(p, live: live, catalog: catalog) { id in
                    catalog.price(p.id, id) ?? Catalog.price(provider: p.id, model: id)
                }
            }
        } / 20
        report("ModelList.models (\(live.count) modèles)", t)
        #expect(list.count >= live.count)
        #expect(t < 2000)
    }

    @Test("suggestions « / » et « @ » pendant la frappe")
    func suggestions() {
        let agents = Catalog.builtinAgents
        let library = UserLibrary(commands: (0..<40).map { SlashCommand(id: "c\($0)", name: "cmd\($0)", description: "Commande \($0)", body: "Fais \($0)") })
        var n = 0
        let t = ms {
            for i in 0..<2000 {
                n = ChatLibrary.suggestions(for: i % 2 == 0 ? "/cm" : "@co", library: library, agents: agents)?.count ?? 0
                _ = ChatLibrary.suggestions(for: "Une phrase ordinaire \(i)", library: library, agents: agents)
            }
        }
        report("ChatLibrary.suggestions × 4000", t)
        #expect(n >= 0)
        #expect(t < 5000)
    }
}

/// Les optimisations ne changent rien à ce que l'app voit.
@Suite("Optimisations : mêmes résultats")
struct OptimizationParityTests {
    @Test("index en mémoire : une entrée abîmée est ignorée, le disque et la mémoire concordent")
    func indexCache() async throws {
        let dir = tempDir()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try #"[{"id":"a","title":"A","updated":"2026-11-10T08:30:00.000Z"}, 42, {"title":"sans id"}, {"id":"b","title":"B","pinned":true}]"#
            .write(to: dir.appendingPathComponent("index.json"), atomically: true, encoding: .utf8)
        let store = ConversationStore(directory: dir)
        #expect(await store.index().map(\.id) == ["b", "a"])
        var c = conversation("c", messages: 2, title: "C")
        try await store.save(c)
        c.title = "C2"
        try await store.saveMeta(ConversationStore.Meta(c))
        try await store.delete("a")
        // Un autre lecteur du même dossier voit exactement la même chose.
        let fresh = ConversationStore(directory: dir)
        #expect(await fresh.index().map(\.id) == (await store.index()).map(\.id))
        #expect(await fresh.index().map(\.title) == ["B", "C2"])
        try await store.deleteAll()
        #expect(await store.index().isEmpty)
    }

    @Test("recherche : prolongée, raccourcie, et à jour après un enregistrement")
    func searchRefinement() async throws {
        let store = ConversationStore(directory: tempDir())
        var a = Conversation(id: "a", title: "Un")
        a.messages = [ChatMessage(role: .user, content: "Parlons de Swift"), ChatMessage(role: .assistant, content: "ok")]
        var b = Conversation(id: "b", title: "Deux")
        b.messages = [ChatMessage(role: .user, content: "Et de Rust"), ChatMessage(role: .assistant, content: "ok")]
        try await store.save(a)
        try await store.save(b)
        #expect(await store.search("s").map(\.id).sorted() == ["a", "b"])
        #expect(await store.search("sw").map(\.id) == ["a"])
        #expect(await store.search("swift").map(\.id) == ["a"])
        // Raccourcie : tout est cherché de nouveau.
        #expect(await store.search("s").map(\.id).sorted() == ["a", "b"])
        #expect(await store.search("sw").map(\.id) == ["a"])
        // Une conversation enregistrée entre deux frappes est relue.
        b.messages.append(ChatMessage(role: .user, content: "Et Swiftly ?"))
        try await store.save(b)
        #expect(await store.search("swi").map(\.id).sorted() == ["a", "b"])
        try await store.deleteAll()
    }

    @Test("Markdown : puces, listes et blancs reconnus exactement comme par les expressions")
    func markdownParity() {
        let samples = [
            "- a", "-a", "-  a", "-\ta", "- ", "-", "* b", "+ c", "+\u{00A0}nbsp", "-\u{3000}idéo", "-\u{2028}ls",
            "-\u{0B}vt", "-\u{85}nel", "- \u{0301}accent", "1. un", "12) douze", "1.deux", "1.", "1. ", "٣. arabe",
            "１. pleine chasse", "½. fraction", "1\u{20E3}. touche", "a. lettre", "1 . espace", "1.\r", "-\r", "--- règle",
            "***", "**gras**", "*italique*", "- [x] fait", "- [ ] à faire", "  - sous-puce", "\t1. tab", "# Titre",
            "| a | b |\n|---|---|\n| 1 | 2 |", "> cité", "- un\r\n- deux\r\n\r\n1. a", "texte\r\nsuite\n\n\n", "", "```swift\nlet a = 1\n```", "\u{00A0}- nbsp devant",
        ]
        for s in samples + [samples.joined(separator: "\n")] {
            #expect(MarkdownBlock.parse(s) == referenceParse(s), "\(s.debugDescription)")
        }
        for s in samples { #expect(MarkdownBlock.trim(s) == s.trimmingCharacters(in: .whitespaces)) }
    }

    /// `MarkdownBlock.parse` avant optimisation (expressions régulières, Foundation).
    private func referenceParse(_ text: String) -> [MarkdownBlock] {
        var out: [MarkdownBlock] = []
        var paragraph: [String] = []
        var lines = text.components(separatedBy: "\n")[...]
        func flushParagraph() {
            if !paragraph.isEmpty {
                out.append(.paragraph(paragraph.joined(separator: "\n")))
                paragraph = []
            }
        }
        func heading(_ s: String) -> Int? {
            let hashes = s.prefix(while: { $0 == "#" }).count
            guard (1...6).contains(hashes), s.dropFirst(hashes).first == " " else { return nil }
            return hashes
        }
        func cells(_ line: String) -> [String] {
            var t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("|") { t.removeFirst() }
            if t.hasSuffix("|") { t.removeLast() }
            return t.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        }
        while let line = lines.popFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let indent = line.prefix(while: { $0 == " " }).count / 2
            if trimmed.hasPrefix("```") {
                flushParagraph()
                let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var code: [String] = []
                while let l = lines.popFirst() {
                    if l.trimmingCharacters(in: .whitespaces).hasPrefix("```") { break }
                    code.append(l)
                }
                out.append(.code(language, code.joined(separator: "\n")))
            } else if trimmed.isEmpty {
                flushParagraph()
            } else if let level = heading(trimmed) {
                flushParagraph()
                out.append(.heading(level, String(trimmed.drop(while: { $0 == "#" })).trimmingCharacters(in: .whitespaces)))
            } else if ["---", "***", "___"].contains(trimmed) {
                flushParagraph()
                out.append(.rule)
            } else if trimmed.hasPrefix("> ") || trimmed == ">" {
                flushParagraph()
                out.append(.quote(String(trimmed.dropFirst(trimmed == ">" ? 1 : 2))))
            } else if let r = trimmed.range(of: #"^[-*+]\s+"#, options: .regularExpression) {
                flushParagraph()
                var item = String(trimmed[r.upperBound...])
                if item.hasPrefix("[ ] ") { item = "☐ " + item.dropFirst(4) }
                if item.hasPrefix("[x] ") || item.hasPrefix("[X] ") { item = "☑︎ " + item.dropFirst(4) }
                out.append(.bullet(item, indent))
            } else if let r = trimmed.range(of: #"^\d+[.)]\s+"#, options: .regularExpression) {
                flushParagraph()
                let n = Int(trimmed.prefix(while: \.isNumber)) ?? 1
                out.append(.numbered(n, String(trimmed[r.upperBound...]), indent))
            } else if trimmed.hasPrefix("|"), let next = lines.first, next.contains("---"), next.trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                flushParagraph()
                _ = lines.popFirst()
                var rows = [cells(trimmed)]
                while let l = lines.first, l.trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                    rows.append(cells(l))
                    _ = lines.popFirst()
                }
                out.append(.table(rows))
            } else {
                paragraph.append(line)
            }
        }
        flushParagraph()
        return out
    }

    @Test("dates : celles de Dart (heure locale) et les nôtres, relues à l'identique")
    func dates() throws {
        let d = Date(timeIntervalSince1970: 1_794_300_000.123)
        let s = ISO8601.string(d)
        #expect(s.hasSuffix("Z") && s.contains(".123"))
        #expect(abs((ISO8601.parse(s) ?? .distantPast).timeIntervalSince(d)) < 0.001)
        #expect(ISO8601.parse("2026-11-10T08:30:00Z") != nil)
        let local = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 8, minute: 30))!
        #expect(ISO8601.parse("2026-11-10T08:30:00.000000") == local)
        #expect(ISO8601.parse("2026-11-10T08:30:00") == local)
        #expect(ISO8601.parse("pas une date") == nil && ISO8601.parse("") == nil)
    }

    @Test("catalogue : recherche par index identique à la recherche linéaire")
    func catalogLookup() {
        let list = [
            CatalogModel(id: "GPT-5", input: 1, output: 2), CatalogModel(id: "gpt-5", input: 3, output: 4),
            CatalogModel(id: "beam", name: "Beam 1"), CatalogModel(id: "beam", name: "Beam 2", input: 0, output: 0),
            CatalogModel(id: "free", input: 0, output: 0),
        ]
        let c = ModelCatalog(updated: "2026-11-01", providers: ["x": list])
        for id in ["GPT-5", "gpt-5", "Gpt-5", "beam", "BEAM", "free", "absent"] {
            #expect(c.find("x", id) == list.first { $0.id == id })
            let linear = list.first { $0.id.lowercased() == id.lowercased() }
                .flatMap { m in m.input.flatMap { i in m.output.map { ModelPrice(input: i, output: $0) } } }
            #expect(c.price("x", id) == linear)
            #expect(c.find("y", id) == nil && c.price("y", id) == nil)
        }
        #expect(c == ModelCatalog(updated: "2026-11-01", providers: ["x": list]))
        #expect(c != ModelCatalog(updated: "2026-11-02", providers: ["x": list]))
        #expect(ModelCatalog.day("2026-11-01T10:00") == Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 1)))
        #expect(ModelCatalog.day("") == nil && ModelCatalog.day("bientôt") == nil)
    }

    @Test("noms d'agents après @ : mêmes résultats que l'expression régulière")
    func slugParity() {
        for name in ["Code Reviewer", "  Testeur  Pro ", "Data\tScience", "A\u{00A0}B", "Idéo\u{3000}グラフ", "x\u{2028}y",
                     "a\u{0B}b", "n\u{85}e", "🦀 Rust  Expert", "", "Un", "a - b"] {
            let reference = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                .replacingOccurrences(of: #"\s+"#, with: "-", options: .regularExpression)
            #expect(ChatLibrary.slug(name) == reference, "\(name.debugDescription)")
        }
        #expect(ChatLibrary.suggestions(for: "Bonjour", library: UserLibrary(), agents: Catalog.builtinAgents) == nil)
        #expect(ChatLibrary.suggestions(for: " @code", library: UserLibrary(), agents: Catalog.builtinAgents) == nil)
        #expect(ChatLibrary.suggestions(for: "@", library: UserLibrary(), agents: Catalog.builtinAgents)?.count == Catalog.builtinAgents.count)
    }
}
