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
}
