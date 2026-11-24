import Foundation
import Testing
@testable import NexoraKit

/// edit_file avec un seul numéro de ligne (port de Flutter 2.2.92) : le texte est
/// inséré après cette ligne, au lieu de « il manque le texte » ou « old vide ».
@Suite("Agent : insertion après un numéro de ligne")
struct AgentInsertAfterTests {
    static let code = "fn a() -> i32 {\n    1\n}\n\nfn b() -> i32 {\n    2\n}\n"
    static let added = "fn reading_time() -> i32 {\n    3\n}\n"

    @MainActor
    func codeRun(_ llm: ScriptLLM) -> AgentRun {
        llm.whenEmpty = "```json\n{\"tool\":\"finish\",\"args\":{\"summary\":\"fin\"}}\n```"
        let run = makeRun(llm, hub: repoHub(["site/src/lib.rs": Self.code]), task: "Ajoute reading_time", checks: false)
        run.specs.append("déjà compris")
        return run
    }

    /// Le code avec `added` inséré après la ligne `after`.
    func expected(after: Int, _ added: String) -> String {
        var lines = Self.code.components(separatedBy: "\n")
        lines.removeLast()
        lines.insert(contentsOf: added.components(separatedBy: "\n"), at: after)
        return lines.joined(separator: "\n") + "\n"
    }

    @Test("ligne seule : les lignes autour sont montrées, puis le texte suivant est inséré")
    @MainActor
    func lineThenText() async {
        let llm = ScriptLLM([
            "```json\n{\"tool\":\"edit_file\",\"args\":{\"path\":\"site/src/lib.rs\",\"line\":4}}\n```",
            "```rust\n" + Self.added + "```",
        ])
        let run = codeRun(llm)
        await run.run()
        let second = llm.messages(1).last?["content"] ?? ""
        #expect(second.contains("EN ATTENTE du texte à INSÉRER après la ligne 4"))
        #expect(second.contains("3: }"))
        #expect(!second.contains("il manque le texte"))
        let third = llm.messages(2).last?["content"] ?? ""
        #expect(third.contains("insérée(s) après la ligne 4"))
        #expect(run.draft("site/src/lib.rs") == expected(after: 4, "fn reading_time() -> i32 {\n    3\n}"))
    }

    @Test("ligne avec old vide et new : inséré tout de suite")
    @MainActor
    func blankOldWithText() async {
        let llm = ScriptLLM([
            "```json\n{\"tool\":\"edit_file\",\"args\":{\"path\":\"site/src/lib.rs\",\"line\":3,\"old\":\"\",\"new\":\"\\nfn c() -> i32 { 0 }\"}}\n```",
        ])
        let run = codeRun(llm)
        await run.run()
        #expect(run.draft("site/src/lib.rs") == expected(after: 3, "\nfn c() -> i32 { 0 }"))
        let second = llm.messages(1).last?["content"] ?? ""
        #expect(second.contains("insérée(s) après la ligne 3"))
        #expect(!second.contains("ERREUR"))
    }

    @Test("insert_after explicite et ligne juste après la dernière : ajout à la fin")
    @MainActor
    func afterLast() async {
        let llm = ScriptLLM([
            "```json\n{\"tool\":\"edit_file\",\"args\":{\"path\":\"site/src/lib.rs\",\"insert_after\":8,\"new\":\"// fin\"}}\n```",
        ])
        let run = codeRun(llm)
        await run.run()
        #expect(run.draft("site/src/lib.rs") == Self.code + "// fin\n")
    }

    @Test("ligne hors du fichier : erreur claire, rien n'est modifié")
    @MainActor
    func outside() async {
        let llm = ScriptLLM([
            "```json\n{\"tool\":\"edit_file\",\"args\":{\"path\":\"site/src/lib.rs\",\"line\":600}}\n```",
        ])
        let run = codeRun(llm)
        await run.run()
        #expect((llm.messages(1).last?["content"] ?? "").contains("a 7 lignes, la ligne 600 n'existe pas"))
        #expect(run.draft("site/src/lib.rs") == nil)
    }

    @Test("un vrai passage à remplacer garde son rôle")
    @MainActor
    func realOldKept() async {
        let llm = ScriptLLM([
            "```json\n{\"tool\":\"edit_file\",\"args\":{\"path\":\"site/src/lib.rs\",\"line\":6,\"old\":\"    2\",\"new\":\"    20\"}}\n```",
        ])
        let run = codeRun(llm)
        await run.run()
        #expect(run.draft("site/src/lib.rs") == Self.code.replacingOccurrences(of: "    2\n", with: "    20\n"))
    }

    @Test("un commentaire de remplissage n'est jamais inséré")
    @MainActor
    func fillerRefused() async {
        let llm = ScriptLLM([
            "```json\n{\"tool\":\"edit_file\",\"args\":{\"path\":\"site/src/lib.rs\",\"line\":4,\"old\":\"\",\"new\":\"// ... existing code\\nfn z() {}\"}}\n```",
        ])
        let run = codeRun(llm)
        await run.run()
        #expect((llm.messages(1).last?["content"] ?? "").contains("tient la place de code"))
        #expect(run.draft("site/src/lib.rs") == nil)
    }
}
